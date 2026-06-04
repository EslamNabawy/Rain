import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCSessionDescription;
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/state/app_providers.dart';
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
      expect(snapshot.sessionId, 'room-bob-alice');
    },
  );
}

final class _StaticRuntimeController extends RuntimeController {
  _StaticRuntimeController(this.runtime);

  final RainRuntimeController runtime;

  @override
  Future<RainRuntimeController?> build() async => runtime;
}

final class _StaticFriendsController extends FriendsController {
  _StaticFriendsController(this.friends);

  final List<FriendRecord> friends;

  @override
  Future<List<FriendRecord>> build() async => friends;
}

final class _TestSessionManager implements SessionManager {
  final Map<String, Session> _sessions = <String, Session>{};
  final Set<String> _openChannels = <String>{};
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

  void seedConnected(String peerId, {String? roomId}) {
    final session = Session(
      peerId: peerId,
      state: SessionState.connected,
      connectionType: ConnectionType.signaling,
      phase: SessionPhase.connected,
      detail: 'Data channels open.',
      roomId: roomId,
      sender: (_) {},
    );
    _sessions[peerId] = session;
  }

  void setChannelOpen(
    String peerId,
    SessionChannel channel,
    bool isOpen,
  ) {
    final key = '$peerId:${channel.name}';
    if (isOpen) {
      _openChannels.add(key);
    } else {
      _openChannels.remove(key);
    }
  }

  Future<void> dispose() async {
    await _peerConnected.close();
    await _peerDisconnected.close();
    await _peerMessages.close();
    await _remoteTracks.close();
    await _sessionChanges.close();
    await _incomingOfferRejected.close();
  }

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
  }) async {}

  @override
  Future<void> unregisterPeer(String peerId) async {}

  @override
  Future<Session> connect(String peerId) async {
    final session = Session(
      peerId: peerId,
      state: SessionState.connecting,
      connectionType: ConnectionType.signaling,
      sender: (_) {},
    );
    _sessions[peerId] = session;
    _sessionChanges.add(session);
    return session;
  }

  @override
  Future<void> disconnect(String peerId) async {
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
}
