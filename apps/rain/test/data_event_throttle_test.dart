/// # data_event_throttle_test.dart
///
/// Regression coverage for the leading-edge throttle on data-event
/// connectivity notifications: binary chunk bursts must not rebuild peer
/// snapshots per message while single messages still notify immediately.
///
/// **Key types:** RainRuntimeController, _EmittingSessionManager
///
/// **Depends on:** flutter_test, protocol_brain, rain app runtime, rain_core
///
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCSessionDescription;
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('binary bursts notify once per window instead of per message', () async {
    final database = RainDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final brain = _EmittingSessionManager();
    addTearDown(brain.dispose);
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
    addTearDown(runtime.dispose);

    await runtime.start();
    final events = <void>[];
    final subscription = runtime.watchPeerConnectivityChanges().listen(
      events.add,
    );
    addTearDown(subscription.cancel);

    // Settle the initial yield and any startup-driven notifications so the
    // assertions below measure only emission-driven deltas.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final baseline = events.length;

    var receivedAt = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 6; i++) {
      receivedAt += 1;
      brain.emitMessage(
        SessionMessage(
          channel: SessionChannel.file,
          data: Uint8List.fromList(<int>[i]),
          receivedAt: DateTime.fromMillisecondsSinceEpoch(receivedAt),
          peerId: 'bob',
        ),
      );
    }
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // Leading edge only: six rapid chunks produce one immediate notification.
    expect(events.length - baseline, 1);

    // Trailing edge flushes the newest recorded timestamp once per window.
    await Future<void>.delayed(const Duration(milliseconds: 320));
    expect(events.length - baseline, 2);

    // After the window closes, the next message notifies immediately again.
    receivedAt += 1;
    brain.emitMessage(
      SessionMessage(
        channel: SessionChannel.file,
        data: 'file.complete',
        receivedAt: DateTime.fromMillisecondsSinceEpoch(receivedAt),
        peerId: 'bob',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(events.length - baseline, 3);
  });
}

class _EmittingSessionManager implements SessionManager {
  final Map<String, Session> _sessions = {};
  final StreamController<Session> _sessionController =
      StreamController<Session>.broadcast();
  final StreamController<Session> _connectedController =
      StreamController<Session>.broadcast();
  final StreamController<String> _disconnectedController =
      StreamController<String>.broadcast();
  final StreamController<SessionMessage> _messageController =
      StreamController<SessionMessage>.broadcast();
  final StreamController<SessionRemoteTrack> _trackController =
      StreamController<SessionRemoteTrack>.broadcast();
  final StreamController<IncomingOfferRejection> _rejectionController =
      StreamController<IncomingOfferRejection>.broadcast();

  void emitMessage(SessionMessage message) {
    _messageController.add(message);
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
    throw UnimplementedError();
  }

  @override
  Future<void> disconnect(String peerId) async {}

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
  bool isChannelOpen(String peerId, SessionChannel channel) => false;

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
