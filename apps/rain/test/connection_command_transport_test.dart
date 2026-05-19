import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/connection_command/connection_command_models.dart';
import 'package:rain/application/connection_command/connection_run_token.dart';
import 'package:rain/application/connection_command/session_manager_connection_transport.dart';

void main() {
  group('SessionManagerConnectionTransport', () {
    test('preflight succeeds without touching a transport', () async {
      final webRtc = _FakeSessionManager(ConnectionType.signaling);
      final transport = SessionManagerConnectionTransport(webRtc: webRtc);

      final result = await transport.runLayer(
        peerId: 'bob',
        layer: ConnectionLayer.preflight,
        token: _token(),
        timeout: const Duration(milliseconds: 10),
      );

      expect(result.succeeded, isTrue);
      expect(webRtc.connectCalls, 0);
      expect(webRtc.registerCalls, 0);
    });

    test('web rtc direct success registers and connects the peer', () async {
      final webRtc = _FakeSessionManager(ConnectionType.signaling)
        ..nextState = SessionState.connected;
      final transport = SessionManagerConnectionTransport(webRtc: webRtc);

      final result = await transport.runLayer(
        peerId: 'bob',
        layer: ConnectionLayer.webRtcDirect,
        token: _token(),
        timeout: const Duration(milliseconds: 10),
      );

      expect(result.succeeded, isTrue);
      expect(webRtc.registerCalls, 1);
      expect(webRtc.connectCalls, 1);
    });

    test('web rtc direct failure maps to direct path blocked', () async {
      final webRtc = _FakeSessionManager(ConnectionType.signaling)
        ..nextState = SessionState.failed
        ..nextError = 'ICE failed';
      final transport = SessionManagerConnectionTransport(webRtc: webRtc);

      final result = await transport.runLayer(
        peerId: 'bob',
        layer: ConnectionLayer.webRtcDirect,
        token: _token(),
        timeout: const Duration(milliseconds: 10),
      );

      expect(result.succeeded, isFalse);
      expect(result.failureCode, ConnectionFailureCode.directPathBlocked);
      expect(result.technicalDetail, contains('ICE failed'));
    });

    test('iroh layer uses iroh manager and maps failures', () async {
      final webRtc = _FakeSessionManager(ConnectionType.signaling);
      final iroh = _FakeSessionManager(ConnectionType.iroh)
        ..nextState = SessionState.failed
        ..nextError = 'handshake rejected';
      final transport = SessionManagerConnectionTransport(
        webRtc: webRtc,
        iroh: iroh,
      );

      final result = await transport.runLayer(
        peerId: 'bob',
        layer: ConnectionLayer.iroh,
        token: _token(),
        timeout: const Duration(milliseconds: 10),
      );

      expect(iroh.registerCalls, 1);
      expect(iroh.connectCalls, 1);
      expect(result.succeeded, isFalse);
      expect(result.failureCode, ConnectionFailureCode.irohConnectFailed);
      expect(result.technicalDetail, contains('handshake rejected'));
    });

    test('cancel layer disconnects and unregisters the active manager', () async {
      final webRtc = _FakeSessionManager(ConnectionType.signaling);
      final transport = SessionManagerConnectionTransport(webRtc: webRtc);

      await transport.cancelLayer(
        peerId: 'bob',
        layer: ConnectionLayer.webRtcPrimaryRelay,
        token: _token(),
      );

      expect(webRtc.disconnectCalls, 1);
      expect(webRtc.unregisterCalls, 1);
    });
  });
}

ConnectionRunToken _token() {
  return ConnectionRunToken(
    peerId: 'bob',
    runId: 'run-1',
    generation: 1,
    startedAt: 1,
  );
}

class _FakeSessionManager implements SessionManager {
  _FakeSessionManager(this.connectionType);

  final ConnectionType connectionType;
  var nextState = SessionState.connected;
  String? nextError;
  var connectCalls = 0;
  var disconnectCalls = 0;
  var registerCalls = 0;
  var unregisterCalls = 0;

  final _connected = StreamController<Session>.broadcast();
  final _disconnected = StreamController<String>.broadcast();
  final _messages = StreamController<SessionMessage>.broadcast();
  final _changed = StreamController<Session>.broadcast();
  final _sessions = <String, Session>{};

  @override
  Stream<Session> get onPeerConnected => _connected.stream;

  @override
  Stream<String> get onPeerDisconnected => _disconnected.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _messages.stream;

  @override
  Stream<Session> get onSessionChanged => _changed.stream;

  @override
  Future<void> registerPeer(String peerId) async {
    registerCalls += 1;
  }

  @override
  Future<Session> connect(String peerId) async {
    connectCalls += 1;
    final session = Session(
      peerId: peerId,
      state: nextState,
      connectionType: connectionType,
      detail: nextError ?? 'detail',
      error: nextError,
      sender: (_) {},
    );
    _sessions[peerId] = session;
    _changed.add(session);
    if (nextState == SessionState.connected) {
      _connected.add(session);
    }
    return session;
  }

  @override
  Future<void> disconnect(String peerId) async {
    disconnectCalls += 1;
    _sessions.remove(peerId);
    _disconnected.add(peerId);
  }

  @override
  Future<void> unregisterPeer(String peerId) async {
    unregisterCalls += 1;
  }

  @override
  Session? getSession(String peerId) => _sessions[peerId];

  @override
  List<Session> getSessions() => _sessions.values.toList(growable: false);

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async => 0;

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) => true;

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) async {}

  @override
  void send(String peerId, SessionChannel channel, Object data) {}

  @override
  void sendControl(String peerId, String data) {}
}
