import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/transport/fallback_session_manager.dart';

enum FakeConnectResult { connected, connecting, failed, throwsError }

class SentMessage {
  const SentMessage(this.peerId, this.channel, this.data);

  final String peerId;
  final SessionChannel channel;
  final Object data;
}

class FakeSessionManager implements SessionManager {
  FakeSessionManager({
    required this.connectionType,
    required this.connectResult,
  });

  final ConnectionType connectionType;
  FakeConnectResult connectResult;
  var connectCalls = 0;
  var disconnectCalls = 0;
  var registerCalls = 0;
  var unregisterCalls = 0;
  final sentMessages = <SentMessage>[];
  final sessions = <String, Session>{};

  final _connected = StreamController<Session>.broadcast();
  final _disconnected = StreamController<String>.broadcast();
  final _messages = StreamController<SessionMessage>.broadcast();
  final _changed = StreamController<Session>.broadcast();

  @override
  Stream<Session> get onPeerConnected => _connected.stream;

  @override
  Stream<String> get onPeerDisconnected => _disconnected.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _messages.stream;

  @override
  Stream<Session> get onSessionChanged => _changed.stream;

  @override
  Future<Session> connect(String peerId) async {
    connectCalls++;
    if (connectResult == FakeConnectResult.throwsError) {
      throw StateError('connect failed');
    }
    final session = _session(peerId, switch (connectResult) {
      FakeConnectResult.connected => SessionState.connected,
      FakeConnectResult.connecting => SessionState.connecting,
      FakeConnectResult.failed => SessionState.failed,
      FakeConnectResult.throwsError => SessionState.failed,
    });
    sessions[peerId] = session;
    _changed.add(session);
    if (session.state == SessionState.connected) {
      _connected.add(session);
    }
    return session;
  }

  @override
  Future<void> disconnect(String peerId) async {
    disconnectCalls++;
    sessions.remove(peerId);
    _disconnected.add(peerId);
  }

  @override
  Future<void> registerPeer(String peerId) async {
    registerCalls++;
  }

  @override
  Future<void> unregisterPeer(String peerId) async {
    unregisterCalls++;
  }

  @override
  List<Session> getSessions() => sessions.values.toList(growable: false);

  @override
  Session? getSession(String peerId) => sessions[peerId];

  @override
  void sendControl(String peerId, String data) {
    send(peerId, SessionChannel.control, data);
  }

  @override
  void send(String peerId, SessionChannel channel, Object data) {
    sentMessages.add(SentMessage(peerId, channel, data));
  }

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) async {}

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async => 7;

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) {
    return sessions[peerId]?.state == SessionState.connected;
  }

  Future<void> dispose() async {
    await _connected.close();
    await _disconnected.close();
    await _messages.close();
    await _changed.close();
  }

  Session _session(String peerId, SessionState state) {
    return Session(
      peerId: peerId,
      state: state,
      connectionType: connectionType,
      detail: state == SessionState.failed ? 'failed' : 'ok',
      error: state == SessionState.failed ? 'failed' : null,
      sender: (_) {},
    );
  }
}

void main() {
  test('uses WebRTC when WebRTC connects', () async {
    final webRtc = FakeSessionManager(
      connectionType: ConnectionType.signaling,
      connectResult: FakeConnectResult.connected,
    );
    final iroh = FakeSessionManager(
      connectionType: ConnectionType.iroh,
      connectResult: FakeConnectResult.connected,
    );
    final fallback = FallbackSessionManager(
      webRtc: webRtc,
      iroh: iroh,
      webRtcConnectTimeout: const Duration(milliseconds: 1),
    );

    final session = await fallback.connect('bob');

    expect(session.connectionType, ConnectionType.signaling);
    expect(webRtc.connectCalls, 1);
    expect(iroh.connectCalls, 0);
    await fallback.dispose();
    await webRtc.dispose();
    await iroh.dispose();
  });

  test('tries Iroh after WebRTC throws', () async {
    final webRtc = FakeSessionManager(
      connectionType: ConnectionType.signaling,
      connectResult: FakeConnectResult.throwsError,
    );
    final iroh = FakeSessionManager(
      connectionType: ConnectionType.iroh,
      connectResult: FakeConnectResult.connected,
    );
    final fallback = FallbackSessionManager(
      webRtc: webRtc,
      iroh: iroh,
      webRtcConnectTimeout: const Duration(milliseconds: 1),
    );

    final session = await fallback.connect('bob');

    expect(session.connectionType, ConnectionType.iroh);
    expect(webRtc.disconnectCalls, 1);
    expect(iroh.connectCalls, 1);
    await fallback.dispose();
    await webRtc.dispose();
    await iroh.dispose();
  });

  test('tries Iroh after WebRTC times out connecting', () async {
    final webRtc = FakeSessionManager(
      connectionType: ConnectionType.signaling,
      connectResult: FakeConnectResult.connecting,
    );
    final iroh = FakeSessionManager(
      connectionType: ConnectionType.iroh,
      connectResult: FakeConnectResult.connected,
    );
    final fallback = FallbackSessionManager(
      webRtc: webRtc,
      iroh: iroh,
      webRtcConnectTimeout: const Duration(milliseconds: 1),
    );

    final session = await fallback.connect('bob');

    expect(session.connectionType, ConnectionType.iroh);
    expect(webRtc.disconnectCalls, 1);
    expect(iroh.connectCalls, 1);
    await fallback.dispose();
    await webRtc.dispose();
    await iroh.dispose();
  });

  test('send uses the active transport only', () async {
    final webRtc = FakeSessionManager(
      connectionType: ConnectionType.signaling,
      connectResult: FakeConnectResult.throwsError,
    );
    final iroh = FakeSessionManager(
      connectionType: ConnectionType.iroh,
      connectResult: FakeConnectResult.connected,
    );
    final fallback = FallbackSessionManager(
      webRtc: webRtc,
      iroh: iroh,
      webRtcConnectTimeout: const Duration(milliseconds: 1),
    );

    await fallback.connect('bob');
    fallback.send('bob', SessionChannel.chat, 'hello');

    expect(webRtc.sentMessages, isEmpty);
    expect(iroh.sentMessages.single.data, 'hello');
    await fallback.dispose();
    await webRtc.dispose();
    await iroh.dispose();
  });

  test('disconnect closes both transports', () async {
    final webRtc = FakeSessionManager(
      connectionType: ConnectionType.signaling,
      connectResult: FakeConnectResult.connected,
    );
    final iroh = FakeSessionManager(
      connectionType: ConnectionType.iroh,
      connectResult: FakeConnectResult.connected,
    );
    final fallback = FallbackSessionManager(webRtc: webRtc, iroh: iroh);

    await fallback.connect('bob');
    await fallback.disconnect('bob');

    expect(webRtc.disconnectCalls, 1);
    expect(iroh.disconnectCalls, 1);
    await fallback.dispose();
    await webRtc.dispose();
    await iroh.dispose();
  });

  test('connectWebRtcOnly uses WebRTC without trying Iroh', () async {
    final webRtc = FakeSessionManager(
      connectionType: ConnectionType.signaling,
      connectResult: FakeConnectResult.connected,
    );
    final iroh = FakeSessionManager(
      connectionType: ConnectionType.iroh,
      connectResult: FakeConnectResult.connected,
    );
    final fallback = FallbackSessionManager(webRtc: webRtc, iroh: iroh);

    final session = await fallback.connectWebRtcOnly('bob');

    expect(session.connectionType, ConnectionType.signaling);
    expect(webRtc.connectCalls, 1);
    expect(iroh.connectCalls, 0);
    fallback.send('bob', SessionChannel.chat, 'hello');
    expect(webRtc.sentMessages.single.data, 'hello');
    expect(iroh.sentMessages, isEmpty);
    await fallback.dispose();
    await webRtc.dispose();
    await iroh.dispose();
  });

  test('connectIrohOnly uses Iroh without trying WebRTC', () async {
    final webRtc = FakeSessionManager(
      connectionType: ConnectionType.signaling,
      connectResult: FakeConnectResult.connected,
    );
    final iroh = FakeSessionManager(
      connectionType: ConnectionType.iroh,
      connectResult: FakeConnectResult.connected,
    );
    final fallback = FallbackSessionManager(webRtc: webRtc, iroh: iroh);

    final session = await fallback.connectIrohOnly('bob');

    expect(session.connectionType, ConnectionType.iroh);
    expect(webRtc.connectCalls, 0);
    expect(iroh.connectCalls, 1);
    fallback.send('bob', SessionChannel.chat, 'hello');
    expect(iroh.sentMessages.single.data, 'hello');
    expect(webRtc.sentMessages, isEmpty);
    await fallback.dispose();
    await webRtc.dispose();
    await iroh.dispose();
  });
}
