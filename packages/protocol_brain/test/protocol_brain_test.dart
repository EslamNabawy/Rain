import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peer_core/peer_core.dart';
import 'package:protocol_brain/protocol_brain.dart';

void main() {
  test('roomId is deterministic regardless of peer order', () {
    expect(roomId('alice', 'bob'), 'alice:bob');
    expect(roomId('bob', 'alice'), 'alice:bob');
  });

  test('SDP payload preserves restart marker', () {
    final payload = SDPPayload(
      sdp: RTCSessionDescription('offer-sdp', 'offer'),
      ts: 7,
      restart: true,
    );

    final decoded = SDPPayload.fromJson(payload.toJson());

    expect(decoded.sdp.sdp, 'offer-sdp');
    expect(decoded.sdp.type, 'offer');
    expect(decoded.ts, 7);
    expect(decoded.restart, isTrue);
  });

  test('incoming offer guard rejects stale unauthorized offers', () async {
    final adapter = _RecordingSignalingAdapter();
    final brain = ProtocolBrainImpl(
      selfUsername: 'bob',
      adapter: adapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: _FakePeerCore.new,
      connectionMemoryStore: _MemoryConnectionStore(),
    );
    final rejections = <IncomingOfferRejection>[];
    final subscription = brain.onIncomingOfferRejected.listen(rejections.add);

    await brain.registerPeer(
      'alice',
      incomingOfferGuard: (_) async {
        return const IncomingOfferDecision.deny('Manual disconnect is active.');
      },
    );
    adapter.emitOffer(
      'alice:bob',
      SDPPayload(sdp: RTCSessionDescription('offer-sdp', 'offer'), ts: 1),
    );
    await pumpEventQueue();

    expect(adapter.writtenAnswers, isEmpty);
    expect(brain.getSession('alice'), isNull);
    expect(rejections, hasLength(1));
    expect(rejections.single.peerId, 'alice');
    expect(rejections.single.reason, 'Manual disconnect is active.');
    expect(rejections.single.offerTimestamp, 1);

    await subscription.cancel();
    await brain.unregisterPeer('alice');
  });

  test('incoming offer is ignored after unregister during guard', () async {
    final adapter = _RecordingSignalingAdapter();
    final guardStarted = Completer<void>();
    final releaseGuard = Completer<void>();
    final brain = ProtocolBrainImpl(
      selfUsername: 'bob',
      adapter: adapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: _FakePeerCore.new,
      connectionMemoryStore: _MemoryConnectionStore(),
    );

    await brain.registerPeer(
      'alice',
      incomingOfferGuard: (_) async {
        if (!guardStarted.isCompleted) {
          guardStarted.complete();
        }
        await releaseGuard.future;
        return const IncomingOfferDecision.allow();
      },
    );
    adapter.emitOffer(
      'alice:bob',
      SDPPayload(sdp: RTCSessionDescription('offer-sdp', 'offer'), ts: 1),
    );
    await guardStarted.future;

    await brain.unregisterPeer('alice');
    releaseGuard.complete();
    await pumpEventQueue(times: 3);

    expect(adapter.writtenAnswers, isEmpty);
    expect(brain.getSession('alice'), isNull);
  });

  test('only canonical room owner creates the initial offer', () async {
    final ownerAdapter = _RecordingSignalingAdapter();
    final ownerBrain = ProtocolBrainImpl(
      selfUsername: 'alice',
      adapter: ownerAdapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: _FakePeerCore.new,
      connectionMemoryStore: _MemoryConnectionStore(),
    );

    await ownerBrain.connect('bob');

    expect(ownerAdapter.writtenOffers, <String>['alice:bob']);

    await ownerBrain.disconnect('bob');

    final answererAdapter = _RecordingSignalingAdapter();
    final answererBrain = ProtocolBrainImpl(
      selfUsername: 'bob',
      adapter: answererAdapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: _FakePeerCore.new,
      connectionMemoryStore: _MemoryConnectionStore(),
    );

    await answererBrain.connect('alice');

    expect(answererAdapter.writtenOffers, isEmpty);
    expect(answererBrain.getSession('alice')?.state, SessionState.connecting);

    await answererBrain.disconnect('alice');
  });

  test('new owner offer clears stale answers before listening', () async {
    final adapter = _RecordingSignalingAdapter();
    adapter.storedAnswers['alice:bob'] = SDPPayload(
      sdp: RTCSessionDescription('stale-answer-sdp', 'answer'),
      ts: 1,
    );
    late _FakePeerCore peer;
    final brain = ProtocolBrainImpl(
      selfUsername: 'alice',
      adapter: adapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: () {
        peer = _FakePeerCore();
        return peer;
      },
      connectionMemoryStore: _MemoryConnectionStore(),
    );

    await brain.connect('bob');
    await pumpEventQueue();

    expect(adapter.deletedRooms, <String>['alice:bob']);
    expect(peer.setAnswerCalls, 0);

    adapter.emitAnswer(
      'alice:bob',
      SDPPayload(
        sdp: RTCSessionDescription('fresh-answer-sdp', 'answer'),
        ts: 2,
      ),
    );
    await pumpEventQueue();

    expect(peer.setAnswerCalls, 1);
    expect(peer.receivedAnswers, <String>['fresh-answer-sdp']);

    await brain.disconnect('bob');
  });

  test('connect setup failure marks session failed and allows retry', () async {
    final adapter = _RecordingSignalingAdapter()
      ..writeOfferError = Exception('permission denied');
    final brain = ProtocolBrainImpl(
      selfUsername: 'alice',
      adapter: adapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: _FakePeerCore.new,
      connectionMemoryStore: _MemoryConnectionStore(),
    );

    await expectLater(brain.connect('bob'), throwsException);

    final failed = brain.getSession('bob');
    expect(failed?.state, SessionState.failed);
    expect(failed?.error, contains('permission denied'));

    adapter.writeOfferError = null;
    await brain.connect('bob');

    expect(adapter.writtenOffers, <String>['alice:bob']);

    await brain.disconnect('bob');
  });

  test('session changes are emitted when peer becomes connected', () async {
    final adapter = _RecordingSignalingAdapter();
    late _FakePeerCore peer;
    final brain = ProtocolBrainImpl(
      selfUsername: 'alice',
      adapter: adapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: () {
        peer = _FakePeerCore();
        return peer;
      },
      connectionMemoryStore: _MemoryConnectionStore(),
    );
    final changes = <Session>[];
    final subscription = brain.onSessionChanged.listen(changes.add);

    await brain.connect('bob');
    peer.route = const PeerConnectionRoute(
      kind: PeerRouteKind.direct,
      localCandidateType: 'host',
      remoteCandidateType: 'srflx',
      protocol: 'udp',
      rtt: 0.03,
      bitrate: 1000000,
      updatedAt: 10,
    );

    expect(
      changes.map((Session session) => session.state),
      everyElement(SessionState.connecting),
    );
    expect(
      changes.map((Session session) => session.phase),
      contains(SessionPhase.creatingOffer),
    );

    peer.emitConnected();
    await pumpEventQueue(times: 3);

    expect(changes.last.state, SessionState.connected);
    expect(changes.last.route.kind, PeerRouteKind.direct);
    expect(changes.last.detail, contains('Direct'));
    expect(brain.getSession('bob')?.state, SessionState.connected);
    expect(brain.getSession('bob')?.route.kind, PeerRouteKind.direct);

    await subscription.cancel();
    await brain.disconnect('bob');
  });

  test('reconnect clears stale route until a new route is detected', () async {
    final adapter = _RecordingSignalingAdapter();
    late _FakePeerCore peer;
    final brain = ProtocolBrainImpl(
      selfUsername: 'alice',
      adapter: adapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: () {
        peer = _FakePeerCore();
        return peer;
      },
      connectionMemoryStore: _MemoryConnectionStore(),
      reconnectGrace: const Duration(seconds: 5),
    );

    await brain.connect('bob');
    peer.route = const PeerConnectionRoute(
      kind: PeerRouteKind.direct,
      localCandidateType: 'host',
      remoteCandidateType: 'host',
      protocol: 'udp',
    );
    peer.emitConnected();
    await pumpEventQueue(times: 3);

    expect(brain.getSession('bob')?.route.kind, PeerRouteKind.direct);

    peer.emitDisconnected();
    await pumpEventQueue();

    final session = brain.getSession('bob');
    expect(session?.state, SessionState.reconnecting);
    expect(session?.route.kind, PeerRouteKind.unknown);

    await brain.disconnect('bob');
  });

  test(
    'connected session negotiates voice media without dropping chat session',
    () async {
      final adapter = _RecordingSignalingAdapter();
      late _FakePeerCore peer;
      final brain = ProtocolBrainImpl(
        selfUsername: 'alice',
        adapter: adapter,
        peerConfig: _fakePeerConfig(),
        peerFactory: () {
          peer = _FakePeerCore();
          return peer;
        },
        connectionMemoryStore: _MemoryConnectionStore(),
      );
      final changes = <Session>[];
      final subscription = brain.onSessionChanged.listen(changes.add);

      await brain.connect('bob');
      peer.emitConnected();
      await pumpEventQueue(times: 3);

      await brain.startLocalAudio('bob');
      final offer = await brain.createMediaOffer('bob');
      final answer = await brain.applyMediaOffer(
        'bob',
        RTCSessionDescription('remote-media-offer', 'offer'),
      );
      await brain.applyMediaAnswer(
        'bob',
        RTCSessionDescription('remote-media-answer', 'answer'),
      );
      await brain.setMicrophoneMuted('bob', muted: true);
      await brain.stopLocalAudio('bob');

      expect(offer.sdp, 'media-offer-sdp');
      expect(answer.sdp, 'media-answer-sdp');
      expect(peer.localAudioStarted, isTrue);
      expect(peer.localAudioStopped, isTrue);
      expect(peer.muteCalls, <bool>[true]);
      expect(peer.receivedMediaOffers, <String?>['remote-media-offer']);
      expect(peer.receivedMediaAnswers, <String?>['remote-media-answer']);
      expect(brain.getSession('bob')?.state, SessionState.connected);
      expect(
        changes.map((Session session) => session.phase),
        contains(SessionPhase.negotiatingMedia),
      );

      await subscription.cancel();
      await brain.disconnect('bob');
    },
  );

  test('failed session does not keep stale direct route', () async {
    final adapter = _RecordingSignalingAdapter();
    late _FakePeerCore peer;
    final brain = ProtocolBrainImpl(
      selfUsername: 'alice',
      adapter: adapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: () {
        peer = _FakePeerCore();
        return peer;
      },
      connectionMemoryStore: _MemoryConnectionStore(),
    );

    await brain.connect('bob');
    peer.route = const PeerConnectionRoute(
      kind: PeerRouteKind.direct,
      localCandidateType: 'host',
      remoteCandidateType: 'srflx',
      protocol: 'udp',
    );
    peer.emitConnected();
    await pumpEventQueue(times: 3);

    expect(brain.getSession('bob')?.route.kind, PeerRouteKind.direct);

    peer.emitFailed();
    await pumpEventQueue();

    final session = brain.getSession('bob');
    expect(session?.state, SessionState.failed);
    expect(session?.route.kind, PeerRouteKind.unknown);

    await brain.disconnect('bob');
  });

  test(
    'direct transport failure triggers one clean relay-only retry',
    () async {
      final adapter = _RecordingSignalingAdapter();
      final peers = <_FakePeerCore>[];
      final requestedPolicies = <PeerIceTransportPolicy>[];
      final brain = ProtocolBrainImpl(
        selfUsername: 'alice',
        adapter: adapter,
        peerConfig: _fakePeerConfig(),
        peerConfigProvider: (PeerIceTransportPolicy policy) async {
          requestedPolicies.add(policy);
          return PeerConfig(
            iceServers: const <Map<String, dynamic>>[
              <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
              <String, dynamic>{
                'urls': 'turn:turn.rain.example:3478?transport=udp',
                'username': 'rain',
                'credential': 'secret',
              },
            ],
            platform: _FakePlatformBridge(),
            iceTransportPolicy: policy,
          );
        },
        peerFactory: () {
          final peer = _FakePeerCore();
          peers.add(peer);
          return peer;
        },
        connectionMemoryStore: _MemoryConnectionStore(),
      );

      await brain.connect('bob');
      peers.single.emitFailed();
      await pumpEventQueue(times: 4);

      expect(peers, hasLength(2));
      expect(
        peers.last.initialConfig?.iceTransportPolicy,
        PeerIceTransportPolicy.relayOnly,
      );
      expect(requestedPolicies, <PeerIceTransportPolicy>[
        PeerIceTransportPolicy.all,
        PeerIceTransportPolicy.relayOnly,
        PeerIceTransportPolicy.relayOnly,
      ]);
      expect(adapter.deletedRooms, contains('alice:bob'));
      expect(adapter.writtenOffers, <String>['alice:bob', 'alice:bob']);
      expect(brain.getSession('bob')?.state, SessionState.reconnecting);

      await brain.disconnect('bob');
    },
  );

  test('transient disconnect recovery cancels pending reconnect', () async {
    final adapter = _RecordingSignalingAdapter();
    var peerCreations = 0;
    late _FakePeerCore peer;
    final brain = ProtocolBrainImpl(
      selfUsername: 'alice',
      adapter: adapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: () {
        peerCreations += 1;
        peer = _FakePeerCore();
        return peer;
      },
      connectionMemoryStore: _MemoryConnectionStore(),
      reconnectGrace: const Duration(milliseconds: 50),
    );
    final terminalDisconnects = <String>[];
    final disconnectedSubscription = brain.onPeerDisconnected.listen(
      terminalDisconnects.add,
    );

    await brain.connect('bob');
    peer.emitConnected();
    await pumpEventQueue();

    peer.emitDisconnected();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    peer.emitConnected();
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(peerCreations, 1);
    expect(adapter.writtenOffers, <String>['alice:bob']);
    expect(brain.getSession('bob')?.state, SessionState.connected);
    expect(terminalDisconnects, isEmpty);

    await disconnectedSubscription.cancel();
    await brain.disconnect('bob');
  });

  test(
    'network recovery keeps an already connected owner peer alive',
    () async {
      final adapter = _RecordingSignalingAdapter();
      final peers = <_FakePeerCore>[];
      final brain = ProtocolBrainImpl(
        selfUsername: 'alice',
        adapter: adapter,
        peerConfig: _fakePeerConfig(),
        peerFactory: () {
          final peer = _FakePeerCore();
          peers.add(peer);
          return peer;
        },
        connectionMemoryStore: _MemoryConnectionStore(),
      );

      await brain.connect('bob');
      peers.single.emitConnected();
      await pumpEventQueue(times: 3);

      await brain.recoverConnection(
        'bob',
        reason: 'Network changed. Restarting peer connection paths.',
      );
      await pumpEventQueue(times: 3);

      expect(peers, hasLength(1));
      expect(adapter.writtenOffers, <String>['alice:bob']);
      expect(brain.getSession('bob')?.state, SessionState.connected);

      await brain.disconnect('bob');
    },
  );

  test(
    'scheduled reconnect waits for in-flight media before destroying peer',
    () async {
      final adapter = _RecordingSignalingAdapter();
      final peers = <_FakePeerCore>[];
      final brain = ProtocolBrainImpl(
        selfUsername: 'alice',
        adapter: adapter,
        peerConfig: _fakePeerConfig(),
        peerFactory: () {
          final peer = _FakePeerCore();
          peers.add(peer);
          return peer;
        },
        connectionMemoryStore: _MemoryConnectionStore(),
        reconnectGrace: Duration.zero,
      );

      await brain.connect('bob');
      peers.single.emitConnected();
      await pumpEventQueue(times: 3);

      final microphoneGate = Completer<void>();
      peers.single.startLocalAudioCompleter = microphoneGate;
      final audioStart = brain.startLocalAudio('bob');
      await pumpEventQueue(times: 3);

      peers.single.emitDisconnected();
      await pumpEventQueue(times: 5);

      expect(peers, hasLength(1));
      expect(peers.single.destroyed, isFalse);

      microphoneGate.complete();
      await expectLater(audioStart, throwsA(isA<StateError>()));
      await pumpEventQueue(times: 5);

      expect(peers.first.destroyed, isTrue);
      expect(peers, hasLength(2));

      await brain.disconnect('bob');
    },
  );

  test('connected answerer ignores stale retry offers', () async {
    final adapter = _RecordingSignalingAdapter();
    var peerCreations = 0;
    late _FakePeerCore peer;
    final brain = ProtocolBrainImpl(
      selfUsername: 'bob',
      adapter: adapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: () {
        peerCreations += 1;
        peer = _FakePeerCore();
        return peer;
      },
      connectionMemoryStore: _MemoryConnectionStore(),
    );

    await brain.connect('alice');
    adapter.emitOffer(
      'alice:bob',
      SDPPayload(
        sdp: RTCSessionDescription('initial-offer', 'offer'),
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await pumpEventQueue();
    peer.emitConnected();
    await pumpEventQueue();

    adapter.emitOffer(
      'alice:bob',
      SDPPayload(
        sdp: RTCSessionDescription('stale-offer', 'offer'),
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await pumpEventQueue();
    await pumpEventQueue();

    expect(peerCreations, 1);
    expect(adapter.writtenAnswers, <String>['alice:bob']);
    expect(brain.getSession('alice')?.state, SessionState.connected);

    await brain.disconnect('alice');
  });

  test('connected answerer accepts marked restart offers', () async {
    final adapter = _RecordingSignalingAdapter();
    var peerCreations = 0;
    late _FakePeerCore peer;
    final brain = ProtocolBrainImpl(
      selfUsername: 'bob',
      adapter: adapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: () {
        peerCreations += 1;
        peer = _FakePeerCore();
        return peer;
      },
      connectionMemoryStore: _MemoryConnectionStore(),
    );

    await brain.connect('alice');
    adapter.emitOffer(
      'alice:bob',
      SDPPayload(sdp: RTCSessionDescription('initial-offer', 'offer'), ts: 1),
    );
    await pumpEventQueue();
    peer.emitConnected();
    await pumpEventQueue();

    adapter.emitOffer(
      'alice:bob',
      SDPPayload(
        sdp: RTCSessionDescription('restart-offer', 'offer'),
        ts: 2,
        restart: true,
      ),
    );
    await pumpEventQueue(times: 3);

    expect(peerCreations, 2);
    expect(adapter.writtenAnswers, <String>['alice:bob', 'alice:bob']);
    expect(brain.getSession('alice')?.state, SessionState.reconnecting);

    await brain.disconnect('alice');
  });

  test('owner accepts only one answer per offer', () async {
    final adapter = _RecordingSignalingAdapter();
    late _FakePeerCore peer;
    final brain = ProtocolBrainImpl(
      selfUsername: 'alice',
      adapter: adapter,
      peerConfig: _fakePeerConfig(),
      peerFactory: () {
        peer = _FakePeerCore();
        return peer;
      },
      connectionMemoryStore: _MemoryConnectionStore(),
    );

    await brain.connect('bob');
    adapter.emitAnswer(
      'alice:bob',
      SDPPayload(
        sdp: RTCSessionDescription('answer-sdp', 'answer'),
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await pumpEventQueue();
    peer.emitConnected();
    await pumpEventQueue();

    adapter.emitAnswer(
      'alice:bob',
      SDPPayload(
        sdp: RTCSessionDescription('duplicate-answer', 'answer'),
        ts: DateTime.now().millisecondsSinceEpoch + 1,
      ),
    );
    await pumpEventQueue();

    expect(peer.setAnswerCalls, 1);
    expect(brain.getSession('bob')?.state, SessionState.connected);

    await brain.disconnect('bob');
  });

  test(
    'answer stream errors fail the owner session with signaling guidance',
    () async {
      final adapter = _RecordingSignalingAdapter();
      final brain = ProtocolBrainImpl(
        selfUsername: 'alice',
        adapter: adapter,
        peerConfig: _fakePeerConfig(),
        peerFactory: _FakePeerCore.new,
        connectionMemoryStore: _MemoryConnectionStore(),
      );

      await brain.connect('bob');
      adapter.emitAnswerError(
        'alice:bob',
        const SignalingEncryptionException('Unable to decrypt answer payload.'),
      );
      await pumpEventQueue();

      final session = brain.getSession('bob');
      expect(session?.state, SessionState.failed);
      expect(session?.phase, SessionPhase.failed);
      expect(session?.error, contains('signaling data'));
      expect(session?.detail, contains('Signaling failed'));
      expect(adapter.deletedRooms, contains('alice:bob'));

      await brain.disconnect('bob');
    },
  );

  test(
    'offer stream errors fail the answerer session with signaling guidance',
    () async {
      final adapter = _RecordingSignalingAdapter();
      final brain = ProtocolBrainImpl(
        selfUsername: 'bob',
        adapter: adapter,
        peerConfig: _fakePeerConfig(),
        peerFactory: _FakePeerCore.new,
        connectionMemoryStore: _MemoryConnectionStore(),
      );

      await brain.connect('alice');
      adapter.emitOfferError(
        'alice:bob',
        const SignalingEncryptionException('Unable to decrypt offer payload.'),
      );
      await pumpEventQueue();

      final session = brain.getSession('alice');
      expect(session?.state, SessionState.failed);
      expect(session?.phase, SessionPhase.failed);
      expect(session?.error, contains('signaling data'));
      expect(session?.detail, contains('Signaling failed'));
      expect(adapter.deletedRooms, contains('alice:bob'));

      await brain.disconnect('alice');
    },
  );

  test('connection memory usability respects cache rules', () {
    final memory = ConnectionMemory(
      peerId: 'bob',
      lastConnectedAt: DateTime.now().millisecondsSinceEpoch,
      cachedIce: const [],
      fingerprint: 'x',
      consecutiveFailures: 0,
    );

    expect(memory.isUsable, isFalse);
  });

  test('backend identity serializes for Firebase', () {
    const identity = BackendIdentity(
      username: 'alice',
      uid: 'uid-1',
      displayName: 'Alice',
      gender: null,
      registeredAt: 1,
      lastSeen: 2,
      lastHeartbeat: 3,
      online: true,
    );

    expect(identity.toFirebaseJson(), <String, Object?>{
      'username': 'alice',
      'displayName': 'Alice',
      'gender': null,
      'registeredAt': 1,
      'lastSeen': 2,
      'lastHeartbeat': 3,
      'online': true,
      'uid': 'uid-1',
    });
  });
}

PeerConfig _fakePeerConfig() {
  return PeerConfig(
    iceServers: const <Map<String, dynamic>>[],
    platform: _FakePlatformBridge(),
  );
}

class _RecordingSignalingAdapter implements SignalingAdapter {
  final List<String> writtenOffers = <String>[];
  final List<String> writtenAnswers = <String>[];
  final List<String> deletedRooms = <String>[];
  final List<SDPPayload> writtenOfferPayloads = <SDPPayload>[];
  final Map<String, SDPPayload> storedAnswers = <String, SDPPayload>{};
  Object? writeOfferError;
  final Map<String, StreamController<SDPPayload>> _offerControllers =
      <String, StreamController<SDPPayload>>{};
  final Map<String, StreamController<SDPPayload>> _answerControllers =
      <String, StreamController<SDPPayload>>{};
  final Map<String, StreamController<RTCIceCandidate>> _iceControllers =
      <String, StreamController<RTCIceCandidate>>{};

  @override
  Future<void> ensureAuthenticated() async {}

  @override
  Future<String> currentUid() async => 'uid';

  @override
  Future<void> signOut() async {}

  @override
  Future<String> register(String username, String password) async => 'uid';

  @override
  Future<String> login(String username, String password) async => 'uid';

  @override
  Future<void> writeOffer(String roomId, SDPPayload offer) async {
    final error = writeOfferError;
    if (error != null) {
      throw error;
    }
    writtenOffers.add(roomId);
    writtenOfferPayloads.add(offer);
  }

  @override
  Future<void> writeAnswer(String roomId, SDPPayload answer) async {
    writtenAnswers.add(roomId);
    storedAnswers[roomId] = answer;
  }

  @override
  Future<void> writeICE(
    String roomId,
    IceRole role,
    RTCIceCandidate candidate,
  ) async {}

  @override
  Stream<SDPPayload> onAnswer(String roomId) {
    final controller = _answerControllers.putIfAbsent(
      roomId,
      () => StreamController<SDPPayload>.broadcast(),
    );
    scheduleMicrotask(() {
      final storedAnswer = storedAnswers[roomId];
      if (storedAnswer != null && !controller.isClosed) {
        controller.add(storedAnswer);
      }
    });
    return controller.stream;
  }

  @override
  Stream<RTCIceCandidate> onICE(String roomId, IceRole role) {
    final key = '$roomId:${role.name}';
    return _iceControllers
        .putIfAbsent(key, () => StreamController<RTCIceCandidate>.broadcast())
        .stream;
  }

  @override
  Stream<SDPPayload> onOffer(String roomId) {
    return _offerControllers
        .putIfAbsent(roomId, () => StreamController<SDPPayload>.broadcast())
        .stream;
  }

  void emitOffer(String roomId, SDPPayload offer) {
    _offerControllers
        .putIfAbsent(roomId, () => StreamController<SDPPayload>.broadcast())
        .add(offer);
  }

  void emitAnswer(String roomId, SDPPayload answer) {
    _answerControllers
        .putIfAbsent(roomId, () => StreamController<SDPPayload>.broadcast())
        .add(answer);
  }

  void emitOfferError(String roomId, Object error) {
    _offerControllers
        .putIfAbsent(roomId, () => StreamController<SDPPayload>.broadcast())
        .addError(error);
  }

  void emitAnswerError(String roomId, Object error) {
    _answerControllers
        .putIfAbsent(roomId, () => StreamController<SDPPayload>.broadcast())
        .addError(error);
  }

  @override
  Future<void> setPresence(String username, bool online) async {}

  @override
  Future<void> sendHeartbeat(String username) async {}

  @override
  Stream<bool> watchPresence(String username) => Stream<bool>.value(true);

  @override
  Future<bool> isUsernameAvailable(String username) async => true;

  @override
  Future<void> upsertIdentity(BackendIdentity identity) async {}

  @override
  Future<BackendIdentity?> fetchIdentity(String username) async => null;

  @override
  Future<void> addToUserSearch(String username) async {}

  @override
  Future<List<BackendIdentity>> searchUsers(String query) async =>
      const <BackendIdentity>[];

  @override
  Future<void> writeFriendRequest(String to, String from) async {}

  @override
  Future<void> deleteFriendRequest(String to, String from) async {}

  @override
  Future<List<String>> loadIncomingFriendRequests(String username) async =>
      const <String>[];

  @override
  Future<List<String>> loadOutgoingFriendRequests(String username) async =>
      const <String>[];

  @override
  Future<List<String>> loadAcceptedFriends(String username) async =>
      const <String>[];

  @override
  Future<List<String>> loadBlockedUsers(String username) async =>
      const <String>[];

  @override
  Future<List<String>> loadUsersBlocking(String username) async =>
      const <String>[];

  @override
  Future<void> upsertFriendship(String firstUser, String secondUser) async {}

  @override
  Future<void> deleteFriendship(String firstUser, String secondUser) async {}

  @override
  Future<void> blockUser(String blocker, String blocked) async {}

  @override
  Future<void> unblockUser(String blocker, String blocked) async {}

  @override
  Stream<String> onFriendRequest(String username) =>
      const Stream<String>.empty();

  @override
  Stream<String> onRelationshipChanged(String username) =>
      const Stream<String>.empty();

  @override
  Future<void> deleteRoom(String roomId) async {
    deletedRooms.add(roomId);
    storedAnswers.remove(roomId);
  }

  @override
  Future<void> dispose() async {
    for (final controller in _offerControllers.values) {
      await controller.close();
    }
    for (final controller in _answerControllers.values) {
      await controller.close();
    }
    for (final controller in _iceControllers.values) {
      await controller.close();
    }
  }
}

class _MemoryConnectionStore implements ConnectionMemoryStore {
  final Map<String, ConnectionMemory> _memories = <String, ConnectionMemory>{};

  @override
  Future<ConnectionMemory?> read(String peerId) async => _memories[peerId];

  @override
  Future<void> write(ConnectionMemory memory) async {
    _memories[memory.peerId] = memory;
  }

  @override
  Future<void> delete(String peerId) async {
    _memories.remove(peerId);
  }
}

class _FakePeerCore implements PeerCore {
  PeerState _state = PeerState.idle;
  int setAnswerCalls = 0;
  PeerConfig? initialConfig;
  final List<String?> receivedAnswers = <String?>[];
  final List<String?> receivedMediaOffers = <String?>[];
  final List<String?> receivedMediaAnswers = <String?>[];
  final List<bool> muteCalls = <bool>[];
  Completer<void>? startLocalAudioCompleter;
  bool localAudioStarted = false;
  bool localAudioStopped = false;
  bool destroyed = false;
  PeerConnectionRoute route = const PeerConnectionRoute.unknown();
  final StreamController<RTCIceCandidate> _iceController =
      StreamController<RTCIceCandidate>.broadcast();
  final StreamController<void> _connectedController =
      StreamController<void>.broadcast();
  final StreamController<void> _disconnectedController =
      StreamController<void>.broadcast();
  final StreamController<PeerMessage> _messageController =
      StreamController<PeerMessage>.broadcast();
  final StreamController<PeerRemoteTrack> _remoteTrackController =
      StreamController<PeerRemoteTrack>.broadcast();
  final StreamController<String> _channelOpenController =
      StreamController<String>.broadcast();
  final StreamController<String> _channelCloseController =
      StreamController<String>.broadcast();
  final StreamController<PeerState> _stateController =
      StreamController<PeerState>.broadcast();

  @override
  Future<void> init(PeerConfig config) async {
    initialConfig = config;
    destroyed = false;
    _state = PeerState.ready;
    _stateController.add(_state);
  }

  @override
  Future<void> destroy() async {
    destroyed = true;
    _state = PeerState.idle;
    _stateController.add(_state);
  }

  @override
  Future<RTCSessionDescription> createOffer() async {
    _state = PeerState.offering;
    _stateController.add(_state);
    return RTCSessionDescription('offer-sdp', 'offer');
  }

  @override
  Future<RTCSessionDescription> setOffer(RTCSessionDescription offer) async {
    _state = PeerState.answering;
    _stateController.add(_state);
    return RTCSessionDescription('answer-sdp', 'answer');
  }

  @override
  Future<void> setAnswer(RTCSessionDescription answer) async {
    setAnswerCalls += 1;
    receivedAnswers.add(answer.sdp);
    if (_state != PeerState.offering) {
      throw StateError('Unexpected answer in $_state');
    }
    _state = PeerState.connecting;
    _stateController.add(_state);
  }

  @override
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {}

  @override
  List<RTCIceCandidate> getLocalCandidates() => const <RTCIceCandidate>[];

  @override
  Future<void> applyMediaAnswer(RTCSessionDescription answer) async {
    receivedMediaAnswers.add(answer.sdp);
  }

  @override
  Future<RTCSessionDescription> applyMediaOffer(
    RTCSessionDescription offer,
  ) async {
    receivedMediaOffers.add(offer.sdp);
    return RTCSessionDescription('media-answer-sdp', 'answer');
  }

  @override
  Future<RTCSessionDescription> createMediaOffer() async {
    return RTCSessionDescription('media-offer-sdp', 'offer');
  }

  @override
  void send(String channelId, data) {}

  @override
  Future<void> openChannel(
    String channelId, {
    RTCDataChannelInit? opts,
  }) async {}

  @override
  Future<void> closeChannel(String channelId) async {}

  @override
  Future<int> bufferedAmount(String channelId) async => 0;

  @override
  bool isChannelOpen(String channelId) => true;

  @override
  Future<PeerConnectionRoute> currentRoute() async => route;

  @override
  Future<void> setMicrophoneMuted({required bool muted}) async {
    muteCalls.add(muted);
  }

  @override
  Future<void> startLocalAudio() async {
    localAudioStarted = true;
    final completer = startLocalAudioCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<void> stopLocalAudio() async {
    localAudioStopped = true;
  }

  @override
  Stream<RTCIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<void> get onConnected => _connectedController.stream;

  @override
  Stream<void> get onDisconnected => _disconnectedController.stream;

  @override
  Stream<PeerMessage> get onMessage => _messageController.stream;

  @override
  Stream<PeerRemoteTrack> get onRemoteTrack => _remoteTrackController.stream;

  @override
  Stream<String> get onChannelOpen => _channelOpenController.stream;

  @override
  Stream<String> get onChannelClose => _channelCloseController.stream;

  @override
  Stream<PeerState> get onStateChange => _stateController.stream;

  @override
  PeerState get state => _state;

  void emitConnected() {
    _state = PeerState.connected;
    _stateController.add(_state);
    _connectedController.add(null);
  }

  void emitDisconnected() {
    _state = PeerState.reconnecting;
    _stateController.add(_state);
    _disconnectedController.add(null);
  }

  void emitFailed() {
    _state = PeerState.failed;
    _stateController.add(_state);
  }
}

class _FakePlatformBridge implements PlatformBridge {
  @override
  Future<RTCPeerConnection> createPeerConnection(Map<String, dynamic> config) {
    throw UnimplementedError();
  }

  @override
  Future<RTCDataChannel> createDataChannel(
    RTCPeerConnection pc,
    String label,
    RTCDataChannelInit init,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> clearVoiceAudio() async {}

  @override
  Future<MediaStream> getUserMedia(Map<String, dynamic> constraints) {
    throw UnimplementedError();
  }

  @override
  StorageBackend getLocalStorage() => MemoryStorageBackend();

  @override
  Future<void> prepareVoiceAudio() async {}

  @override
  Future<void> setMicrophoneMuted(
    MediaStreamTrack track, {
    required bool muted,
  }) async {}
}
