/// # peer_connectivity_provider_test.dart
///
/// Tests for peerConnectivityProvider that reports connected peer sessions with presence state. Covers session lifecycle, stale presence handling, and Riverpod provider integration.
///
/// **Key types:** peerConnectivityProvider, RainRuntimeController, RainIdentity, _TestSessionManager
///
/// **Depends on:** flutter_test, flutter_riverpod, protocol_brain, rain app_bootstrap, rain_core

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCSessionDescription;
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'peerConnectivityProvider reports connected session with stale presence',
    () async {
      final database = RainDatabase(NativeDatabase.memory());
      final messageStore = MessageStore(database);
      final offlineQueueStore = OfflineQueueStore(database);
      final brain = _TestSessionManager()
        ..seedConnected('bob', roomId: 'room-bob-alice')
        ..setChannelOpen('bob', SessionChannel.chat, true);
      final runtime = RainRuntimeController(
        selfIdentity: const RainIdentity(
          username: 'alice',
          displayName: 'Alice',
          createdAt: 1,
          gender: null,
        ),
        adapter: NoopSignalingAdapter(),
        brain: brain,
        database: database,
        friendStore: FriendStore(database),
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
        messageDeliveryService: MessageDeliveryService(
          messageStore: messageStore,
          offlineQueueStore: offlineQueueStore,
        ),
      );
      final friends = <FriendRecord>[
        const FriendRecord(
          username: 'bob',
          displayName: 'Bob',
          state: FriendState.friend,
          addedAt: 1,
          lastOnlineAt: 1,
          isOnline: false,
          unreadCount: 0,
          gender: null,
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap(database)),
          runtimeControllerProvider.overrideWith(
            () => _StaticRuntimeController(runtime),
          ),
          friendsProvider.overrideWith(() => _StaticFriendsController(friends)),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await runtime.dispose();
        await brain.dispose();
        await database.close();
      });

      await container.read(runtimeControllerProvider.future);
      await container.read(friendsProvider.future);

      final snapshot = container.read(peerConnectivityProvider)['bob'];

      expect(snapshot, isNotNull);
      expect(snapshot!.sessionState, SessionState.connected);
      expect(snapshot.presenceOnline, isFalse);
      expect(snapshot.presenceFresh, isFalse);
      expect(snapshot.isConnectedWithStalePresence, isTrue);
      expect(snapshot.canSendData, isTrue);
    },
  );

  test(
    'peerConnectivityProvider reports disconnected peer without session',
    () async {
      final database = RainDatabase(NativeDatabase.memory());
      final brain = _TestSessionManager();
      final runtime = RainRuntimeController(
        selfIdentity: const RainIdentity(
          username: 'alice',
          displayName: 'Alice',
          createdAt: 1,
          gender: null,
        ),
        adapter: NoopSignalingAdapter(),
        brain: brain,
        database: database,
        friendStore: FriendStore(database),
        messageStore: MessageStore(database),
        offlineQueueStore: OfflineQueueStore(database),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(database),
          offlineQueueStore: OfflineQueueStore(database),
        ),
      );
      final friends = <FriendRecord>[
        const FriendRecord(
          username: 'charlie',
          displayName: 'Charlie',
          state: FriendState.friend,
          addedAt: 1,
          lastOnlineAt: null,
          isOnline: false,
          unreadCount: 0,
          gender: null,
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap(database)),
          runtimeControllerProvider.overrideWith(
            () => _StaticRuntimeController(runtime),
          ),
          friendsProvider.overrideWith(() => _StaticFriendsController(friends)),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await runtime.dispose();
        await brain.dispose();
        await database.close();
      });

      await container.read(runtimeControllerProvider.future);
      await container.read(friendsProvider.future);

      final snapshot = container.read(peerConnectivityProvider)['charlie'];

      expect(snapshot, isNotNull);
      expect(snapshot!.sessionState, isNull);
      expect(snapshot.presenceOnline, isFalse);
      expect(snapshot.presenceFresh, isFalse);
      expect(snapshot.canSendData, isFalse);
    },
  );

  test(
    'buildPeerConnectivitySnapshots does not trust local online without backend presence',
    () {
      final brain = _TestSessionManager()
        ..seedConnected('bob', roomId: 'room-bob-alice')
        ..setChannelOpen('bob', SessionChannel.chat, true);
      addTearDown(brain.dispose);

      final snapshots = buildPeerConnectivitySnapshots(
        brain: brain,
        friends: const <FriendRecord>[
          FriendRecord(
            username: 'bob',
            displayName: 'Bob',
            state: FriendState.friend,
            addedAt: 1,
            lastOnlineAt: null,
            isOnline: true,
            unreadCount: 0,
            gender: null,
          ),
        ],
        manualDisconnectedPeers: const <String>{},
        lastDataEventTimestamps: const <String, int>{},
      );

      final snapshot = snapshots['bob'];

      expect(snapshot, isNotNull);
      expect(snapshot!.presenceOnline, isNull);
      expect(snapshot.presenceFresh, isFalse);
      expect(snapshot.peerOnlineForAction, isNull);
      expect(snapshot.requiresOfflineConnectionRequest, isFalse);
      expect(snapshot.isConnected, isFalse);
      expect(snapshot.isConnectedWithStalePresence, isTrue);
      expect(snapshot.canSendData, isTrue);
    },
  );

  test(
    'buildPeerConnectivitySnapshots uses cached backend presence for direct actions',
    () {
      final brain = _TestSessionManager()
        ..seedConnected('bob', roomId: 'room-bob-alice')
        ..setChannelOpen('bob', SessionChannel.chat, true);
      addTearDown(brain.dispose);

      final snapshots = buildPeerConnectivitySnapshots(
        brain: brain,
        friends: const <FriendRecord>[
          FriendRecord(
            username: 'bob',
            displayName: 'Bob',
            state: FriendState.friend,
            addedAt: 1,
            lastOnlineAt: null,
            isOnline: true,
            unreadCount: 0,
            gender: null,
          ),
        ],
        manualDisconnectedPeers: const <String>{},
        lastDataEventTimestamps: const <String, int>{},
        backendPresenceSnapshots: const <String, RuntimePeerPresenceSnapshot>{
          'bob': RuntimePeerPresenceSnapshot(
            peerId: 'bob',
            online: true,
            rawOnline: true,
            observedAtMs: 1000,
            lastHeartbeat: 990,
            lastSeen: 990,
            presenceAgeMs: 10,
            presenceSessionId: 'presence-session-1',
            presenceStartedAt: 900,
            presenceState: 'online',
          ),
        },
      );

      final snapshot = snapshots['bob'];

      expect(snapshot, isNotNull);
      expect(snapshot!.presenceOnline, isTrue);
      expect(snapshot.presenceFresh, isTrue);
      expect(snapshot.peerOnlineForAction, isTrue);
      expect(snapshot.requiresOfflineConnectionRequest, isFalse);
      expect(snapshot.backendPresenceSessionId, 'presence-session-1');
      expect(snapshot.presenceAgeMs, 10);
      expect(snapshot.isConnected, isTrue);
    },
  );

  test(
    'buildPeerConnectivitySnapshots uses cached stale backend presence for offline request routing',
    () {
      final brain = _TestSessionManager()
        ..seedConnected('bob', roomId: 'room-bob-alice');
      addTearDown(brain.dispose);

      final snapshots = buildPeerConnectivitySnapshots(
        brain: brain,
        friends: const <FriendRecord>[
          FriendRecord(
            username: 'bob',
            displayName: 'Bob',
            state: FriendState.friend,
            addedAt: 1,
            lastOnlineAt: null,
            isOnline: true,
            unreadCount: 0,
            gender: null,
          ),
        ],
        manualDisconnectedPeers: const <String>{},
        lastDataEventTimestamps: const <String, int>{},
        backendPresenceSnapshots: const <String, RuntimePeerPresenceSnapshot>{
          'bob': RuntimePeerPresenceSnapshot(
            peerId: 'bob',
            online: false,
            rawOnline: true,
            observedAtMs: 1000,
            lastHeartbeat: 1,
            lastSeen: 1,
            presenceAgeMs: 45000,
            presenceSessionId: 'presence-session-1',
            presenceStartedAt: 1,
            presenceState: 'online',
          ),
        },
      );

      final snapshot = snapshots['bob'];

      expect(snapshot, isNotNull);
      expect(snapshot!.presenceOnline, isFalse);
      expect(snapshot.presenceFresh, isFalse);
      expect(snapshot.peerOnlineForAction, isFalse);
      expect(snapshot.requiresOfflineConnectionRequest, isTrue);
      expect(snapshot.isConnected, isFalse);
      expect(snapshot.isConnectedWithStalePresence, isTrue);
    },
  );

  test('backendIdentityIsFreshlyOnline rejects stale raw-online presence', () {
    const now = 60000;

    expect(
      backendIdentityIsFreshlyOnline(
        _backendIdentity(
          online: true,
          lastHeartbeat: now - 1000,
          presenceState: 'online',
        ),
        nowMs: now,
      ),
      isTrue,
    );
    expect(
      backendIdentityIsFreshlyOnline(
        _backendIdentity(
          online: true,
          lastHeartbeat: now - peerPresenceFreshnessWindowMs - 1,
          presenceState: 'online',
        ),
        nowMs: now,
      ),
      isFalse,
    );
    expect(
      backendIdentityIsFreshlyOnline(
        _backendIdentity(
          online: true,
          lastHeartbeat: now - peerPresenceFreshnessWindowMs - 1,
          presenceState: 'online',
        ),
        nowMs: now,
        freshnessWindowMs: connectionRequestTtl.inMilliseconds,
      ),
      isTrue,
    );
    expect(
      backendIdentityIsFreshlyOnline(
        _backendIdentity(
          online: true,
          lastHeartbeat: now - 1000,
          presenceState: 'offline',
        ),
        nowMs: now,
      ),
      isFalse,
    );
  });
}

BackendIdentity _backendIdentity({
  required bool online,
  required int lastHeartbeat,
  String? presenceState,
}) {
  return BackendIdentity(
    username: 'bob',
    uid: 'uid-bob',
    displayName: 'Bob',
    gender: null,
    registeredAt: 1,
    lastSeen: lastHeartbeat,
    lastHeartbeat: lastHeartbeat,
    online: online,
    presenceSessionId: 'presence-session-1',
    presenceStartedAt: 1,
    presenceState: presenceState,
  );
}

AppBootstrapState _bootstrap(RainDatabase database) {
  return AppBootstrapState(
    environment: AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{'RAIN_BACKEND': 'noop'},
    ),
    database: database,
    adapter: NoopSignalingAdapter(),
    forceUpdateService: ForceUpdateService(
      remoteConfig: null,
      updateUrl: 'https://example.com',
    ),
  );
}

class _StaticRuntimeController extends RuntimeController {
  _StaticRuntimeController(this._runtime);

  final RainRuntimeController _runtime;

  @override
  Future<RainRuntimeController?> build() async => _runtime;
}

class _StaticFriendsController extends FriendsController {
  _StaticFriendsController(this._friends);

  final List<FriendRecord> _friends;

  @override
  Future<List<FriendRecord>> build() async => _friends;
}

class _TestSessionManager implements SessionManager {
  final Map<String, Session> _sessions = {};
  final Set<String> _openChannels = {};
  final _sessionController = StreamController<Session>.broadcast();
  final _connectedController = StreamController<Session>.broadcast();
  final _disconnectedController = StreamController<String>.broadcast();
  final _messageController = StreamController<SessionMessage>.broadcast();
  final _trackController = StreamController<SessionRemoteTrack>.broadcast();
  final _rejectionController =
      StreamController<IncomingOfferRejection>.broadcast();

  void seedConnected(String peerId, {String? roomId}) {
    _sessions[peerId] = Session(
      peerId: peerId,
      state: SessionState.connected,
      connectionType: ConnectionType.signaling,
      sender: (_) {},
      roomId: roomId,
    );
  }

  void setChannelOpen(String peerId, SessionChannel channel, bool open) {
    final key = '$peerId:${channel.name}';
    if (open) {
      _openChannels.add(key);
    } else {
      _openChannels.remove(key);
    }
  }

  @override
  List<Session> getSessions() => _sessions.values.toList();

  @override
  Session? getSession(String peerId) => _sessions[peerId];

  @override
  Stream<Session> get onPeerConnected => _connectedController.stream;

  @override
  Stream<String> get onPeerDisconnected => _disconnectedController.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _messageController.stream;

  @override
  Stream<SessionRemoteTrack> get onRemoteTrack => _trackController.stream;

  @override
  Stream<Session> get onSessionChanged => _sessionController.stream;

  @override
  Stream<IncomingOfferRejection> get onIncomingOfferRejected =>
      _rejectionController.stream;

  @override
  Future<void> registerPeer(
    String peerId, {
    IncomingOfferGuard? incomingOfferGuard,
  }) async {}

  @override
  Future<void> unregisterPeer(String peerId) async {}

  @override
  Future<Session> connect(String peerId) async {
    final session = Session(
      peerId: peerId,
      state: SessionState.connected,
      connectionType: ConnectionType.signaling,
      sender: (_) {},
    );
    _sessions[peerId] = session;
    return session;
  }

  @override
  Future<void> disconnect(String peerId) async {
    _sessions.remove(peerId);
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
  Future<void> openChannel(String peerId, SessionChannel channel) async {
    setChannelOpen(peerId, channel, true);
  }

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async => 0;

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) {
    return _openChannels.contains('$peerId:${channel.name}');
  }

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

  Future<void> dispose() async {
    await _sessionController.close();
    await _connectedController.close();
    await _disconnectedController.close();
    await _messageController.close();
    await _trackController.close();
    await _rejectionController.close();
  }
}
