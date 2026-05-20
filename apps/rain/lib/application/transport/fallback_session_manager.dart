import 'dart:async';

import 'package:protocol_brain/protocol_brain.dart';

enum _TransportKind { webRtc, iroh }

class FallbackSessionManager implements SessionManager {
  FallbackSessionManager({
    required this.webRtc,
    required this.iroh,
    this.webRtcConnectTimeout = const Duration(seconds: 45),
    this.irohConnectTimeout = const Duration(seconds: 25),
  }) {
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      webRtc.onPeerConnected.listen(
        (Session session) => _forwardConnected(_TransportKind.webRtc, session),
      ),
      iroh.onPeerConnected.listen(
        (Session session) => _forwardConnected(_TransportKind.iroh, session),
      ),
      webRtc.onPeerDisconnected.listen(
        (String peerId) => _forwardDisconnected(_TransportKind.webRtc, peerId),
      ),
      iroh.onPeerDisconnected.listen(
        (String peerId) => _forwardDisconnected(_TransportKind.iroh, peerId),
      ),
      webRtc.onPeerMessage.listen(
        (SessionMessage message) =>
            _forwardMessage(_TransportKind.webRtc, message),
      ),
      iroh.onPeerMessage.listen(
        (SessionMessage message) =>
            _forwardMessage(_TransportKind.iroh, message),
      ),
      webRtc.onSessionChanged.listen(
        (Session session) =>
            _forwardSessionChanged(_TransportKind.webRtc, session),
      ),
      iroh.onSessionChanged.listen(
        (Session session) =>
            _forwardSessionChanged(_TransportKind.iroh, session),
      ),
    ]);
  }

  final SessionManager webRtc;
  final SessionManager iroh;
  final Duration webRtcConnectTimeout;
  final Duration irohConnectTimeout;

  final Map<String, _TransportKind> _activeTransports =
      <String, _TransportKind>{};
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  final StreamController<Session> _peerConnectedController =
      StreamController<Session>.broadcast();
  final StreamController<String> _peerDisconnectedController =
      StreamController<String>.broadcast();
  final StreamController<SessionMessage> _peerMessageController =
      StreamController<SessionMessage>.broadcast();
  final StreamController<Session> _sessionChangedController =
      StreamController<Session>.broadcast();

  @override
  Stream<Session> get onPeerConnected => _peerConnectedController.stream;

  @override
  Stream<String> get onPeerDisconnected => _peerDisconnectedController.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _peerMessageController.stream;

  @override
  Stream<Session> get onSessionChanged => _sessionChangedController.stream;

  @override
  Future<Session> connect(String peerId) async {
    final normalizedPeerId = _normalizedPeerId(peerId);
    await registerPeer(normalizedPeerId);

    Object? webRtcFailure;
    _activeTransports[normalizedPeerId] = _TransportKind.webRtc;
    try {
      final started = await webRtc.connect(normalizedPeerId);
      final result = await _waitForConnectResult(
        webRtc,
        normalizedPeerId,
        initial: started,
        timeout: webRtcConnectTimeout,
      );
      if (result.state == SessionState.connected) {
        _activeTransports[normalizedPeerId] = _TransportKind.webRtc;
        return result;
      }
      webRtcFailure = result.error ?? result.detail;
    } catch (error) {
      webRtcFailure = error;
    }

    await _disconnectSilently(webRtc, normalizedPeerId);

    Object? irohFailure;
    _activeTransports[normalizedPeerId] = _TransportKind.iroh;
    try {
      final started = await iroh.connect(normalizedPeerId);
      final result = await _waitForConnectResult(
        iroh,
        normalizedPeerId,
        initial: started,
        timeout: irohConnectTimeout,
      );
      if (result.state == SessionState.connected) {
        _activeTransports[normalizedPeerId] = _TransportKind.iroh;
        return result;
      }
      irohFailure = result.error ?? result.detail;
    } catch (error) {
      irohFailure = error;
    }

    _activeTransports.remove(normalizedPeerId);
    final message = _combinedFailure(webRtcFailure, irohFailure);
    final failedSession = Session(
      peerId: normalizedPeerId,
      state: SessionState.failed,
      connectionType: ConnectionType.iroh,
      detail: message,
      error: message,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      sender: (_) {},
    );
    _sessionChangedController.add(failedSession);
    throw StateError(message);
  }

  Future<Session> connectWebRtcOnly(String peerId, {Duration? timeout}) {
    return _connectOnly(
      _TransportKind.webRtc,
      webRtc,
      peerId,
      timeout ?? webRtcConnectTimeout,
    );
  }

  Future<Session> connectIrohOnly(String peerId, {Duration? timeout}) {
    return _connectOnly(
      _TransportKind.iroh,
      iroh,
      peerId,
      timeout ?? irohConnectTimeout,
    );
  }

  @override
  Future<void> disconnect(String peerId) async {
    final normalizedPeerId = _normalizedPeerId(peerId);
    _activeTransports.remove(normalizedPeerId);
    await Future.wait(<Future<void>>[
      _disconnectSilently(webRtc, normalizedPeerId),
      _disconnectSilently(iroh, normalizedPeerId),
    ]);
    _peerDisconnectedController.add(normalizedPeerId);
  }

  @override
  Future<void> registerPeer(String peerId) async {
    final normalizedPeerId = _normalizedPeerId(peerId);
    await Future.wait(<Future<void>>[
      webRtc.registerPeer(normalizedPeerId),
      iroh.registerPeer(normalizedPeerId),
    ]);
  }

  @override
  Future<void> unregisterPeer(String peerId) async {
    final normalizedPeerId = _normalizedPeerId(peerId);
    _activeTransports.remove(normalizedPeerId);
    await Future.wait(<Future<void>>[
      webRtc.unregisterPeer(normalizedPeerId),
      iroh.unregisterPeer(normalizedPeerId),
    ]);
  }

  @override
  List<Session> getSessions() {
    final sessions = <String, Session>{};
    for (final session in webRtc.getSessions()) {
      sessions[session.peerId] = session;
    }
    for (final session in iroh.getSessions()) {
      if (_activeTransports[session.peerId] == _TransportKind.iroh ||
          !sessions.containsKey(session.peerId)) {
        sessions[session.peerId] = session;
      }
    }
    return sessions.values.toList(growable: false);
  }

  @override
  Session? getSession(String peerId) {
    final normalizedPeerId = _normalizedPeerId(peerId);
    return switch (_activeTransports[normalizedPeerId]) {
      _TransportKind.webRtc => webRtc.getSession(normalizedPeerId),
      _TransportKind.iroh => iroh.getSession(normalizedPeerId),
      null =>
        webRtc.getSession(normalizedPeerId) ??
            iroh.getSession(normalizedPeerId),
    };
  }

  @override
  void sendControl(String peerId, String data) {
    send(peerId, SessionChannel.control, data);
  }

  @override
  void send(String peerId, SessionChannel channel, Object data) {
    _activeManager(peerId).send(_normalizedPeerId(peerId), channel, data);
  }

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) {
    return _activeManager(
      peerId,
    ).openChannel(_normalizedPeerId(peerId), channel);
  }

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) {
    return _activeManager(
      peerId,
    ).bufferedAmount(_normalizedPeerId(peerId), channel);
  }

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) {
    final normalizedPeerId = _normalizedPeerId(peerId);
    final active = _activeTransports[normalizedPeerId];
    return switch (active) {
      _TransportKind.webRtc => webRtc.isChannelOpen(normalizedPeerId, channel),
      _TransportKind.iroh => iroh.isChannelOpen(normalizedPeerId, channel),
      null => false,
    };
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _peerConnectedController.close();
    await _peerDisconnectedController.close();
    await _peerMessageController.close();
    await _sessionChangedController.close();
  }

  SessionManager _activeManager(String peerId) {
    final normalizedPeerId = _normalizedPeerId(peerId);
    return switch (_activeTransports[normalizedPeerId]) {
      _TransportKind.webRtc => webRtc,
      _TransportKind.iroh => iroh,
      null => throw StateError('No active session for $normalizedPeerId'),
    };
  }

  Future<Session> _waitForConnectResult(
    SessionManager manager,
    String peerId, {
    required Session initial,
    required Duration timeout,
  }) async {
    if (initial.state == SessionState.connected ||
        initial.state == SessionState.failed) {
      return initial;
    }

    Session latest = initial;
    final completer = Completer<Session>();
    late final StreamSubscription<Session> connectedSubscription;
    late final StreamSubscription<Session> changedSubscription;
    Timer? timer;

    void complete(Session session) {
      if (!completer.isCompleted) {
        completer.complete(session);
      }
    }

    connectedSubscription = manager.onPeerConnected.listen((Session session) {
      if (session.peerId == peerId) {
        latest = session;
        complete(session);
      }
    });
    changedSubscription = manager.onSessionChanged.listen((Session session) {
      if (session.peerId != peerId) {
        return;
      }
      latest = session;
      if (session.state == SessionState.connected ||
          session.state == SessionState.failed) {
        complete(session);
      }
    });
    timer = Timer(timeout, () {
      final current = manager.getSession(peerId);
      complete(
        current ??
            latest.copyWith(
              state: SessionState.failed,
              detail: 'Data channel did not open.',
              error: 'Data channel did not open.',
            ),
      );
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await connectedSubscription.cancel();
      await changedSubscription.cancel();
    }
  }

  Future<Session> _connectOnly(
    _TransportKind kind,
    SessionManager manager,
    String peerId,
    Duration timeout,
  ) async {
    final normalizedPeerId = _normalizedPeerId(peerId);
    await registerPeer(normalizedPeerId);
    _activeTransports[normalizedPeerId] = kind;
    try {
      final started = await manager.connect(normalizedPeerId);
      final result = await _waitForConnectResult(
        manager,
        normalizedPeerId,
        initial: started,
        timeout: timeout,
      );
      if (result.state == SessionState.connected) {
        _activeTransports[normalizedPeerId] = kind;
        return result;
      }
      _activeTransports.remove(normalizedPeerId);
      throw StateError(result.error ?? result.detail);
    } catch (_) {
      _activeTransports.remove(normalizedPeerId);
      rethrow;
    }
  }

  Future<void> _disconnectSilently(
    SessionManager manager,
    String peerId,
  ) async {
    try {
      await manager.disconnect(peerId);
    } catch (_) {}
  }

  void _forwardConnected(_TransportKind kind, Session session) {
    if (_activeTransports[session.peerId] == kind) {
      _peerConnectedController.add(session);
    }
  }

  void _forwardDisconnected(_TransportKind kind, String peerId) {
    final normalizedPeerId = _normalizedPeerId(peerId);
    if (_activeTransports[normalizedPeerId] == kind) {
      _activeTransports.remove(normalizedPeerId);
      _peerDisconnectedController.add(normalizedPeerId);
    }
  }

  void _forwardMessage(_TransportKind kind, SessionMessage message) {
    final peerId = message.peerId;
    if (peerId != null && _activeTransports[peerId] == kind) {
      _peerMessageController.add(message);
    }
  }

  void _forwardSessionChanged(_TransportKind kind, Session session) {
    if (_activeTransports[session.peerId] == kind) {
      _sessionChangedController.add(session);
    }
  }
}

String _normalizedPeerId(String peerId) => peerId.trim().toLowerCase();

String _combinedFailure(Object? webRtcFailure, Object? irohFailure) {
  final webRtcMessage = _cleanError(webRtcFailure) ?? 'unknown WebRTC error';
  final irohMessage = _cleanError(irohFailure) ?? 'unknown Iroh error';
  return 'All connection routes failed. WebRTC failed: $webRtcMessage. '
      'Iroh fallback failed: $irohMessage.';
}

String? _cleanError(Object? error) {
  final raw = error?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length).trim();
    }
  }
  return raw;
}
