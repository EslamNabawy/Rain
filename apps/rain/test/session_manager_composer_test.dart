import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/transport/fallback_session_manager.dart';
import 'package:rain/application/transport/session_manager_composer.dart';

void main() {
  test('returns WebRTC manager when Iroh fallback is disabled', () {
    final webRtc = _NoopSessionManager(ConnectionType.signaling);
    final iroh = _NoopSessionManager(ConnectionType.iroh);

    final manager = composeSessionManager(
      webRtc: webRtc,
      iroh: iroh,
      enableIrohFallback: false,
      connectTimeout: const Duration(seconds: 3),
    );

    expect(manager, same(webRtc));
  });

  test('returns WebRTC manager when no Iroh manager is available', () {
    final webRtc = _NoopSessionManager(ConnectionType.signaling);

    final manager = composeSessionManager(
      webRtc: webRtc,
      iroh: null,
      enableIrohFallback: true,
      connectTimeout: const Duration(seconds: 3),
    );

    expect(manager, same(webRtc));
  });

  test('wraps WebRTC and Iroh when fallback is enabled and available', () {
    final webRtc = _NoopSessionManager(ConnectionType.signaling);
    final iroh = _NoopSessionManager(ConnectionType.iroh);

    final manager = composeSessionManager(
      webRtc: webRtc,
      iroh: iroh,
      enableIrohFallback: true,
      connectTimeout: const Duration(seconds: 3),
    );

    expect(manager, isA<FallbackSessionManager>());
    final fallback = manager as FallbackSessionManager;
    expect(fallback.webRtc, same(webRtc));
    expect(fallback.iroh, same(iroh));
    expect(fallback.webRtcConnectTimeout, const Duration(seconds: 3));
    expect(fallback.irohConnectTimeout, const Duration(seconds: 3));
  });
}

class _NoopSessionManager implements SessionManager {
  _NoopSessionManager(this.connectionType);

  final ConnectionType connectionType;

  @override
  Stream<Session> get onPeerConnected => const Stream<Session>.empty();

  @override
  Stream<String> get onPeerDisconnected => const Stream<String>.empty();

  @override
  Stream<SessionMessage> get onPeerMessage =>
      const Stream<SessionMessage>.empty();

  @override
  Stream<Session> get onSessionChanged => const Stream<Session>.empty();

  @override
  Stream<IncomingOfferRejection> get onIncomingOfferRejected =>
      const Stream<IncomingOfferRejection>.empty();

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async => 0;

  @override
  Future<Session> connect(String peerId) async => Session(
    peerId: peerId,
    state: SessionState.connected,
    connectionType: connectionType,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
    sender: (_) {},
  );

  @override
  Future<void> disconnect(String peerId) async {}

  @override
  Session? getSession(String peerId) => null;

  @override
  List<Session> getSessions() => const <Session>[];

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) => false;

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) async {}

  @override
  Future<void> registerPeer(
    String peerId, {
    IncomingOfferGuard? incomingOfferGuard,
  }) async {}

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
  void send(String peerId, SessionChannel channel, Object data) {}

  @override
  void sendControl(String peerId, String data) {}

  @override
  Future<void> unregisterPeer(String peerId) async {}
}
