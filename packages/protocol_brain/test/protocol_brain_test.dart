import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peer_core/peer_core.dart';
import 'package:protocol_brain/adapters/supabase_auth_error.dart';
import 'package:protocol_brain/adapters/supabase_identity_error.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

void main() {
  test('supabase auth errors map to Rain-friendly guidance', () {
    expect(
      normalizeSupabaseAuthError(
        AuthApiException(
          'email rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        ),
        duringRegistration: true,
      ).toString(),
      contains('Enable email confirmations'),
    );
    expect(
      normalizeSupabaseAuthError(
        AuthApiException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        ),
        duringRegistration: false,
      ).toString(),
      contains('requires email confirmation'),
    );
  });

  test('supabase uid conflicts reset mismatched local identity', () {
    final normalized = normalizeSupabaseIdentityWriteError(
      const PostgrestException(
        message:
            'duplicate key value violates unique constraint "users_uid_key"',
        code: '23505',
        details: 'Conflict',
      ),
      username: 'alice',
    );

    expect(normalized, isA<SignalingSessionExpiredException>());
    expect(normalized.toString(), contains('@alice'));
  });

  test('supabase auth aliases derive from the project host', () {
    expect(
      supabasePreferredEmailFromUsername(
        'alice',
        projectUrl: 'https://project-ref.supabase.co',
      ),
      'alice@auth.project-ref.supabase.co',
    );
    expect(
      supabaseLoginEmailsFromUsername(
        'alice',
        projectUrl: 'https://project-ref.supabase.co',
      ),
      <String>[
        'alice@auth.project-ref.supabase.co',
        'alice@example.com',
        'alice@rain.example.com',
        'alice@rain.local',
        'alice@gmail.com',
      ],
    );
    expect(() => supabaseAuthAliasDomain('not-a-url'), throwsArgumentError);
  });

  test('roomId is deterministic regardless of peer order', () {
    expect(roomId('alice', 'bob'), 'alice:bob');
    expect(roomId('bob', 'alice'), 'alice:bob');
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

    expect(
      changes.map((Session session) => session.state),
      everyElement(SessionState.connecting),
    );
    expect(
      changes.map((Session session) => session.phase),
      contains(SessionPhase.creatingOffer),
    );

    peer.emitConnected();
    await pumpEventQueue();

    expect(changes.last.state, SessionState.connected);
    expect(brain.getSession('bob')?.state, SessionState.connected);

    await subscription.cancel();
    await brain.disconnect('bob');
  });

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

  test('backend identity serializes separately for firebase and supabase', () {
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

    expect(identity.toSupabaseJson(), <String, Object?>{
      'username': 'alice',
      'display_name': 'Alice',
      'gender': null,
      'registered_at': 1,
      'last_seen': 2,
      'last_heartbeat': 3,
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
    writtenOffers.add(roomId);
  }

  @override
  Future<void> writeAnswer(String roomId, SDPPayload answer) async {
    writtenAnswers.add(roomId);
  }

  @override
  Future<void> writeICE(
    String roomId,
    IceRole role,
    RTCIceCandidate candidate,
  ) async {}

  @override
  Stream<SDPPayload> onAnswer(String roomId) {
    return _answerControllers
        .putIfAbsent(roomId, () => StreamController<SDPPayload>.broadcast())
        .stream;
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
  final StreamController<RTCIceCandidate> _iceController =
      StreamController<RTCIceCandidate>.broadcast();
  final StreamController<void> _connectedController =
      StreamController<void>.broadcast();
  final StreamController<void> _disconnectedController =
      StreamController<void>.broadcast();
  final StreamController<PeerMessage> _messageController =
      StreamController<PeerMessage>.broadcast();
  final StreamController<String> _channelOpenController =
      StreamController<String>.broadcast();
  final StreamController<String> _channelCloseController =
      StreamController<String>.broadcast();
  final StreamController<PeerState> _stateController =
      StreamController<PeerState>.broadcast();

  @override
  Future<void> init(PeerConfig config) async {
    _state = PeerState.ready;
    _stateController.add(_state);
  }

  @override
  Future<void> destroy() async {
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
  Stream<RTCIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<void> get onConnected => _connectedController.stream;

  @override
  Stream<void> get onDisconnected => _disconnectedController.stream;

  @override
  Stream<PeerMessage> get onMessage => _messageController.stream;

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
  StorageBackend getLocalStorage() => MemoryStorageBackend();
}
