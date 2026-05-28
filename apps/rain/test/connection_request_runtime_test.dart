import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCSessionDescription;
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/runtime/runtime_interaction_guard.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionRequestRuntime', () {
    test(
      'offline peer is denied with message before adapter mutation',
      () async {
        final harness = await _ConnectionRequestHarness.create(
          bobOnline: false,
        );
        addTearDown(harness.dispose);

        final decision = await harness.runtime.sendConnectionRequest('bob');

        expect(decision.allowed, isFalse);
        expect(decision.reasonCode, ConnectionRequestReasonCode.peerOffline);
        expect(decision.userMessage, contains('@bob is offline'));
        expect(harness.adapter.outgoingForTest('alice'), isEmpty);
        expect(
          harness.runtime.connectionRequestState.lastUserMessage?.message,
          contains('@bob is offline'),
        );
      },
    );

    test(
      'duplicate pending request exposes existing outbound status',
      () async {
        final harness = await _ConnectionRequestHarness.create();
        addTearDown(harness.dispose);

        final first = await harness.runtime.sendConnectionRequest('bob');
        final second = await harness.runtime.sendConnectionRequest('bob');

        expect(first.allowed, isTrue);
        expect(second.allowed, isFalse);
        expect(
          second.reasonCode,
          ConnectionRequestReasonCode.duplicatePendingRequest,
        );
        expect(
          harness.runtime.connectionRequestState.outgoingRequests,
          hasLength(1),
        );
        expect(
          harness.runtime.connectionRequestState.outgoingSurfaces.single.status,
          ConnectionRequestStatus.pending,
        );
      },
    );

    test(
      'inbound request does not auto-connect manual disconnected peer',
      () async {
        final harness = await _ConnectionRequestHarness.create();
        addTearDown(harness.dispose);

        await harness.runtime.disconnectPeer('bob');
        harness.adapter.seedIncomingRequestForTest(
          username: 'alice',
          from: 'bob',
          requestId: 'cr_inbound_1',
        );
        await _waitForCondition(
          () => harness
              .runtime
              .connectionRequestState
              .incomingRequests
              .isNotEmpty,
          'incoming connection request state',
        );

        expect(harness.brain.connectedPeers, isEmpty);
        expect(
          harness.runtime
              .connectionCoordinatorSnapshotFor('bob')
              .manualDisconnect,
          isTrue,
        );
      },
    );

    test('accept clears manual disconnect only for accepted peer', () async {
      final harness = await _ConnectionRequestHarness.create();
      addTearDown(harness.dispose);
      await harness.addAcceptedFriend('cara', online: true);

      await harness.runtime.disconnectPeer('bob');
      await harness.runtime.disconnectPeer('cara');
      harness.adapter.seedIncomingRequestForTest(
        username: 'alice',
        from: 'bob',
        requestId: 'cr_accept_1',
      );
      await _waitForCondition(
        () =>
            harness.runtime.connectionRequestState.incomingRequests.isNotEmpty,
        'incoming connection request state',
      );

      final decision = await harness.runtime.acceptConnectionRequest(
        'cr_accept_1',
      );

      expect(decision.allowed, isTrue);
      expect(harness.brain.connectedPeers, contains('bob'));
      expect(
        harness.runtime
            .connectionCoordinatorSnapshotFor('bob')
            .manualDisconnect,
        isFalse,
      );
      expect(
        harness.runtime
            .connectionCoordinatorSnapshotFor('cara')
            .manualDisconnect,
        isTrue,
      );
    });

    test('restart restores pending outbound state', () async {
      final harness = await _ConnectionRequestHarness.create();

      final decision = await harness.runtime.sendConnectionRequest('bob');
      expect(decision.allowed, isTrue);
      final database = harness.database;
      final adapter = harness.adapter;
      await harness.runtime.dispose();

      final restarted = await _ConnectionRequestHarness.create(
        database: database,
        adapter: adapter,
      );
      addTearDown(() async {
        await restarted.dispose();
        await database.close();
      });

      await _waitForCondition(
        () =>
            restarted.runtime.connectionRequestState.outgoingRequests.length ==
            1,
        'restored pending outbound request',
      );
      expect(
        restarted
            .runtime
            .connectionRequestState
            .outgoingRequests
            .single
            .requestId,
        decision.requestId,
      );
    });

    test('active file transfer blocks request with user message', () async {
      final harness = await _ConnectionRequestHarness.create();
      addTearDown(harness.dispose);
      await harness.fileTransferStore.upsert(
        FileTransferRecord(
          id: 'transfer-1',
          peerId: 'bob',
          messageId: 'message-1',
          direction: FileTransferDirection.outgoing,
          fileName: 'note.txt',
          fileSize: 1,
          bytesTransferred: 0,
          state: FileTransferState.sending,
          createdAt: 1,
          updatedAt: 1,
        ),
      );

      final decision = await harness.runtime.sendConnectionRequest('bob');

      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ConnectionRequestReasonCode.activeTransfer);
      expect(decision.userMessage, contains('Finish the active file transfer'));
      expect(harness.adapter.outgoingForTest('alice'), isEmpty);
    });

    test('adapter failure returns safe backend message', () async {
      final harness = await _ConnectionRequestHarness.create();
      addTearDown(harness.dispose);
      harness.adapter.failNextConnectionRequestMutationForTest(
        StateError('internal backend stack'),
      );

      final decision = await harness.runtime.sendConnectionRequest('bob');

      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ConnectionRequestReasonCode.backendRejected);
      expect(
        decision.userMessage,
        'Connection request could not be sent. Try again.',
      );
      expect(
        harness.runtime.connectionRequestState.lastUserMessage?.message,
        'Connection request could not be sent. Try again.',
      );
    });

    test(
      'diagnostics include user-facing message and exact internal reason',
      () async {
        final runtimeEvents = <Map<String, Object?>>[];
        final harness = await _ConnectionRequestHarness.create(
          bobOnline: false,
          runtimeEvents: runtimeEvents,
        );
        addTearDown(harness.dispose);

        final decision = await harness.runtime.sendConnectionRequest('bob');

        expect(decision.allowed, isFalse);
        final event = runtimeEvents.lastWhere(
          (Map<String, Object?> event) =>
              event['category'] == 'connection_request' &&
              event['name'] == 'connection_request_decision_denied',
        );
        expect(event['message'], decision.userMessage);
        final context = event['context']! as Map<String, Object?>;
        expect(context['requestId'], isNull);
        expect(context['peerId'], 'bob');
        expect(context['direction'], ConnectionRequestDirection.outbound.name);
        expect(context['status'], isNull);
        expect(
          context['reasonCode'],
          ConnectionRequestReasonCode.peerOffline.name,
        );
        expect(
          context['userMessageKey'],
          'connectionRequest.reason.peerOffline',
        );
        expect(context['renderedMessage'], decision.userMessage);
        expect(context['quotaSummary'], isA<Map<String, Object?>>());
        expect(context['retryAfterMs'], isNull);
        expect(context['notificationFallbackState'], 'notEvaluated');
      },
    );
  });

  group('RuntimeInteractionGuard connection requests', () {
    test('active call blocks connection request with message', () {
      final decision = RuntimeInteractionGuard.canSendConnectionRequest(
        peerId: 'cara',
        friend: FriendRecord(
          username: 'cara',
          displayName: 'Cara',
          state: FriendState.friend,
          addedAt: 1,
          lastOnlineAt: null,
          isOnline: true,
          unreadCount: 0,
          gender: null,
        ),
        manualDisconnectedPeers: const <String>{},
        voiceCallState: const VoiceCallState(
          phase: VoiceCallPhase.active,
          peerId: 'bob',
          callId: 'call-1',
          sessionEpoch: 1,
        ),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, RuntimeInteractionReasonCode.activeCall);
      expect(decision.userMessage, contains('already in a call'));
    });
  });
}

final class _ConnectionRequestHarness {
  _ConnectionRequestHarness({
    required this.database,
    required this.adapter,
    required this.brain,
    required this.runtime,
    required this.fileTransferStore,
    required this.ownsDatabase,
  });

  final RainDatabase database;
  final _ConnectionRequestNoopSignalingAdapter adapter;
  final _TestSessionManager brain;
  final RainRuntimeController runtime;
  final FileTransferStore fileTransferStore;
  final bool ownsDatabase;

  static Future<_ConnectionRequestHarness> create({
    RainDatabase? database,
    _ConnectionRequestNoopSignalingAdapter? adapter,
    bool bobOnline = true,
    List<Map<String, Object?>>? runtimeEvents,
  }) async {
    final db = database ?? RainDatabase(NativeDatabase.memory());
    final requestAdapter =
        adapter ?? _ConnectionRequestNoopSignalingAdapter('alice');
    final brain = _TestSessionManager();
    final identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 0,
      gender: RainGender.female,
    );
    final messageStore = MessageStore(db);
    final offlineQueueStore = OfflineQueueStore(db);
    final fileTransferStore = FileTransferStore(db);

    await requestAdapter.ensurePeerIdentity('bob', online: bobOnline);
    await requestAdapter.upsertFriendship('alice', 'bob');

    final runtime = RainRuntimeController(
      selfIdentity: identity,
      adapter: requestAdapter,
      connectionRequestAdapter: requestAdapter,
      brain: brain,
      database: db,
      friendStore: FriendStore(db),
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      messageDeliveryService: MessageDeliveryService(
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
      ),
      fileTransferStore: fileTransferStore,
      eventRecorder: runtimeEvents == null
          ? null
          : ({
              required String category,
              required String name,
              String severity = 'info',
              String? message,
              Map<String, Object?> context = const <String, Object?>{},
            }) {
              runtimeEvents.add(<String, Object?>{
                'category': category,
                'name': name,
                'severity': severity,
                'message': message,
                'context': context,
              });
            },
    );
    await runtime.start();
    return _ConnectionRequestHarness(
      database: db,
      adapter: requestAdapter,
      brain: brain,
      runtime: runtime,
      fileTransferStore: fileTransferStore,
      ownsDatabase: database == null,
    );
  }

  Future<void> addAcceptedFriend(
    String username, {
    required bool online,
  }) async {
    await adapter.ensurePeerIdentity(username, online: online);
    await adapter.upsertFriendship('alice', username);
    await runtime.refreshPeer(username);
  }

  Future<void> dispose() async {
    await runtime.dispose();
    await adapter.dispose();
    if (ownsDatabase) {
      await database.close();
    }
  }
}

final class _ConnectionRequestNoopSignalingAdapter extends NoopSignalingAdapter
    implements ConnectionRequestAdapter {
  _ConnectionRequestNoopSignalingAdapter(String currentUsername)
    : _requests = FakeConnectionRequestAdapter(
        currentUsername: currentUsername,
      );

  final FakeConnectionRequestAdapter _requests;

  Future<void> ensurePeerIdentity(
    String username, {
    required bool online,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await upsertIdentity(
      BackendIdentity(
        username: username,
        uid: 'uid-$username',
        displayName: username,
        gender: null,
        registeredAt: now,
        lastSeen: now,
        lastHeartbeat: now,
        online: online,
      ),
    );
    await setPresence(username, online);
  }

  void seedIncomingRequestForTest({
    required String username,
    required String from,
    required String requestId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalizedUsername = username.trim().toLowerCase();
    final normalizedFrom = from.trim().toLowerCase();
    _requests.seedIncomingRawForTest(
      username: normalizedUsername,
      requestId: requestId,
      value: ConnectionRequestPayload(
        requestId: requestId,
        from: normalizedFrom,
        to: normalizedUsername,
        pairKey: connectionRequestPairKey(normalizedFrom, normalizedUsername),
        status: ConnectionRequestStatus.pending,
        createdAt: now,
        updatedAt: now,
        expiresAt: now + const Duration(seconds: 45).inMilliseconds,
      ).toJson(),
    );
  }

  List<ConnectionRequestPayload> incomingForTest(String username) {
    return _requests.incomingForTest(username);
  }

  List<ConnectionRequestPayload> outgoingForTest(String username) {
    return _requests.outgoingForTest(username);
  }

  void failNextConnectionRequestMutationForTest(Object error) {
    _requests.failNextMutationForTest(error);
  }

  @override
  Future<ConnectionRequestDecision> acceptConnectionRequest(String requestId) {
    return _requests.acceptConnectionRequest(requestId);
  }

  @override
  Future<ConnectionRequestDecision> cancelConnectionRequest(String requestId) {
    return _requests.cancelConnectionRequest(requestId);
  }

  @override
  Future<ConnectionRequestDecision> createConnectionRequest(String peerId) {
    return _requests.createConnectionRequest(peerId);
  }

  @override
  Future<ConnectionRequestQuotaSnapshot> fetchConnectionRequestQuota() {
    return _requests.fetchConnectionRequestQuota();
  }

  @override
  Future<ConnectionRequestDecision> markConnectionRequestSeen(
    String requestId,
  ) {
    return _requests.markConnectionRequestSeen(requestId);
  }

  @override
  Future<ConnectionRequestDecision> muteConnectionRequestsFromPeer(
    String peerId,
  ) {
    return _requests.muteConnectionRequestsFromPeer(peerId);
  }

  @override
  Future<ConnectionRequestDecision> rejectConnectionRequest(String requestId) {
    return _requests.rejectConnectionRequest(requestId);
  }

  @override
  Future<ConnectionRequestDecision> unmuteConnectionRequestsFromPeer(
    String peerId,
  ) {
    return _requests.unmuteConnectionRequestsFromPeer(peerId);
  }

  @override
  Stream<List<ConnectionRequestPayload>> watchIncomingConnectionRequests(
    String username,
  ) {
    return _requests.watchIncomingConnectionRequests(username);
  }

  @override
  Stream<List<ConnectionRequestPayload>> watchOutgoingConnectionRequests(
    String username,
  ) {
    return _requests.watchOutgoingConnectionRequests(username);
  }

  @override
  Future<void> dispose() async {
    _requests.dispose();
    await super.dispose();
  }
}

final class _TestSessionManager implements SessionManager {
  final List<String> registeredPeers = <String>[];
  final List<String> connectedPeers = <String>[];
  final List<String> disconnectedPeers = <String>[];
  final List<String> unregisteredPeers = <String>[];
  final Map<String, Session> _sessions = <String, Session>{};
  final StreamController<Session> _peerConnected =
      StreamController<Session>.broadcast();
  final StreamController<String> _peerDisconnected =
      StreamController<String>.broadcast();
  final StreamController<SessionMessage> _peerMessages =
      StreamController<SessionMessage>.broadcast();
  final StreamController<SessionRemoteTrack> _remoteTracks =
      StreamController<SessionRemoteTrack>.broadcast();
  final StreamController<Session> _sessionChanges =
      StreamController<Session>.broadcast();
  final StreamController<IncomingOfferRejection> _incomingOfferRejected =
      StreamController<IncomingOfferRejection>.broadcast();

  @override
  Stream<Session> get onPeerConnected => _peerConnected.stream;

  @override
  Stream<String> get onPeerDisconnected => _peerDisconnected.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _peerMessages.stream;

  @override
  Stream<SessionRemoteTrack> get onRemoteTrack => _remoteTracks.stream;

  @override
  Stream<Session> get onSessionChanged => _sessionChanges.stream;

  @override
  Stream<IncomingOfferRejection> get onIncomingOfferRejected =>
      _incomingOfferRejected.stream;

  @override
  List<Session> getSessions() => _sessions.values.toList(growable: false);

  @override
  Session? getSession(String peerId) => _sessions[peerId];

  @override
  Future<void> registerPeer(
    String peerId, {
    IncomingOfferGuard? incomingOfferGuard,
  }) async {
    registeredPeers.add(peerId);
  }

  @override
  Future<void> unregisterPeer(String peerId) async {
    unregisteredPeers.add(peerId);
    _sessions.remove(peerId);
  }

  @override
  Future<Session> connect(String peerId) async {
    connectedPeers.add(peerId);
    final session = Session(
      peerId: peerId,
      state: SessionState.connecting,
      connectionType: ConnectionType.signaling,
      phase: SessionPhase.openingDataChannels,
      sender: (_) {},
    );
    _sessions[peerId] = session;
    _sessionChanges.add(session);
    return session;
  }

  @override
  Future<void> disconnect(String peerId) async {
    disconnectedPeers.add(peerId);
    _sessions.remove(peerId);
    _peerDisconnected.add(peerId);
  }

  @override
  Future<void> recoverConnection(
    String peerId, {
    String reason = 'Network changed. Restarting peer connection.',
  }) async {}

  @override
  Future<void> recoverConnections({
    String reason = 'Network changed. Restarting peer connections.',
  }) async {}

  @override
  void sendControl(String peerId, String data) {}

  @override
  void send(String peerId, SessionChannel channel, Object data) {}

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) async {}

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async => 0;

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) => true;

  @override
  Future<void> startLocalAudio(String peerId) async {}

  @override
  Future<void> stopLocalAudio(String peerId) async {}

  @override
  Future<void> setMicrophoneMuted(String peerId, {required bool muted}) async {}

  @override
  Future<VoiceMediaConnection> createVoiceMediaConnection(String peerId) {
    throw UnimplementedError();
  }

  @override
  Future<CallMediaConnection> createCallMediaConnection(String peerId) {
    throw UnimplementedError();
  }

  @override
  Future<RTCSessionDescription> createMediaOffer(String peerId) {
    throw UnimplementedError();
  }

  @override
  Future<RTCSessionDescription> applyMediaOffer(
    String peerId,
    RTCSessionDescription offer,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> applyMediaAnswer(
    String peerId,
    RTCSessionDescription answer,
  ) async {}
}

Future<void> _waitForCondition(bool Function() condition, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for $reason.');
}
