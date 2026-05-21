import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:protocol_brain/protocol_brain.dart';

import 'iroh_bridge_client.dart';
import 'iroh_models.dart';

typedef IrohNow = DateTime Function();
typedef IrohIdFactory = String Function();

class IrohSessionManager implements SessionManager {
  IrohSessionManager({
    required this.selfUsername,
    required this.adapter,
    required this.bridge,
    required this.alpn,
    this.connectTimeout = const Duration(seconds: 25),
    IrohNow? now,
    IrohIdFactory? attemptIdFactory,
    IrohIdFactory? sessionSecretFactory,
  }) : _now = now ?? DateTime.now,
       _attemptIdFactory = attemptIdFactory ?? _defaultAttemptId,
       _sessionSecretFactory = sessionSecretFactory ?? _defaultSessionSecret {
    _eventSubscription = bridge.eventStream().listen(_handleEvent);
  }

  final String selfUsername;
  final SignalingAdapter adapter;
  final IrohBridgeClient bridge;
  final String alpn;
  final Duration connectTimeout;
  final IrohNow _now;
  final IrohIdFactory _attemptIdFactory;
  final IrohIdFactory _sessionSecretFactory;

  final Map<String, Session> _sessions = <String, Session>{};
  final Map<String, Set<SessionChannel>> _openChannels =
      <String, Set<SessionChannel>>{};
  final StreamController<Session> _peerConnectedController =
      StreamController<Session>.broadcast();
  final StreamController<String> _peerDisconnectedController =
      StreamController<String>.broadcast();
  final StreamController<SessionMessage> _peerMessageController =
      StreamController<SessionMessage>.broadcast();
  final StreamController<Session> _sessionChangedController =
      StreamController<Session>.broadcast();
  late final StreamSubscription<IrohTransportEvent> _eventSubscription;

  @override
  Stream<Session> get onPeerConnected => _peerConnectedController.stream;

  @override
  Stream<String> get onPeerDisconnected => _peerDisconnectedController.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _peerMessageController.stream;

  @override
  Stream<Session> get onSessionChanged => _sessionChangedController.stream;

  @override
  Stream<IncomingOfferRejection> get onIncomingOfferRejected =>
      const Stream<IncomingOfferRejection>.empty();

  @override
  Future<Session> connect(String peerId) async {
    final normalizedPeerId = _normalized(peerId);
    final localAttemptId = _attemptIdFactory();
    final localSecret = _sessionSecretFactory();
    final endpoint = await bridge.startEndpoint(
      username: _normalized(selfUsername),
      alpn: alpn,
    );
    final nowMs = _now().millisecondsSinceEpoch;
    final localPayload = IrohAddressPayload(
      protocolVersion: 1,
      connectAttemptId: localAttemptId,
      username: _normalized(selfUsername),
      nodeId: endpoint.nodeId,
      endpointAddr: endpoint.endpointAddr,
      sessionSecret: localSecret,
      createdAt: nowMs,
      expiresAt: nowMs + const Duration(seconds: 30).inMilliseconds,
    );
    final room = _roomId(selfUsername, normalizedPeerId);
    await adapter.writeIrohAddress(room, localPayload);
    _setSession(
      _session(
        normalizedPeerId,
        SessionState.connecting,
        detail: 'Waiting for Iroh peer address.',
        connectAttemptId: localAttemptId,
      ),
    );

    final remotePayload = await adapter
        .onIrohAddress(room)
        .where(
          (payload) =>
              payload.username.trim().toLowerCase() == normalizedPeerId &&
              payload.isUsableAt(_now().millisecondsSinceEpoch),
        )
        .first
        .timeout(connectTimeout);

    final selfIsDialer = _isDialer(normalizedPeerId);
    final authorityPayload = selfIsDialer ? localPayload : remotePayload;
    if (selfIsDialer) {
      await bridge.connectPeer(
        peerId: normalizedPeerId,
        endpointAddr: remotePayload.endpointAddr,
        expectedNodeId: remotePayload.nodeId,
        alpn: alpn,
        connectAttemptId: authorityPayload.connectAttemptId,
        sessionSecret: authorityPayload.sessionSecret,
      );
    } else {
      await bridge.acceptPeer(
        peerId: normalizedPeerId,
        expectedNodeId: remotePayload.nodeId,
        alpn: alpn,
        connectAttemptId: authorityPayload.connectAttemptId,
        sessionSecret: authorityPayload.sessionSecret,
      );
    }

    final connected = _session(
      normalizedPeerId,
      SessionState.connected,
      detail: selfIsDialer
          ? 'Connected over Iroh fallback.'
          : 'Accepted Iroh fallback connection.',
      connectAttemptId: authorityPayload.connectAttemptId,
    );
    _openChannels[normalizedPeerId] = Set<SessionChannel>.from(
      SessionChannel.values,
    );
    _setSession(connected);
    _peerConnectedController.add(connected);
    return connected;
  }

  @override
  Future<void> disconnect(String peerId) async {
    final normalizedPeerId = _normalized(peerId);
    await bridge.disconnectPeer(peerId: normalizedPeerId);
    _sessions.remove(normalizedPeerId);
    _openChannels.remove(normalizedPeerId);
    _peerDisconnectedController.add(normalizedPeerId);
  }

  @override
  Future<void> registerPeer(
    String peerId, {
    IncomingOfferGuard? incomingOfferGuard,
  }) async {}

  @override
  Future<void> unregisterPeer(String peerId) async {
    final normalizedPeerId = _normalized(peerId);
    if (_sessions.containsKey(normalizedPeerId)) {
      await disconnect(normalizedPeerId);
    }
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
  List<Session> getSessions() => _sessions.values.toList(growable: false);

  @override
  Session? getSession(String peerId) => _sessions[_normalized(peerId)];

  @override
  void sendControl(String peerId, String data) {
    send(peerId, SessionChannel.control, data);
  }

  @override
  void send(String peerId, SessionChannel channel, Object data) {
    final normalizedPeerId = _normalized(peerId);
    if (_sessions[normalizedPeerId]?.state != SessionState.connected) {
      throw StateError('No active Iroh session for $normalizedPeerId');
    }
    unawaited(
      bridge.send(
        peerId: normalizedPeerId,
        channel: _channelId(channel),
        payload: data,
      ),
    );
  }

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) async {
    final normalizedPeerId = _normalized(peerId);
    if (_sessions[normalizedPeerId]?.state != SessionState.connected) {
      throw StateError('No active Iroh session for $normalizedPeerId');
    }
    _openChannels
        .putIfAbsent(normalizedPeerId, () => <SessionChannel>{})
        .add(channel);
  }

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) {
    return bridge.bufferedAmount(
      peerId: _normalized(peerId),
      channel: _channelId(channel),
    );
  }

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) {
    return _openChannels[_normalized(peerId)]?.contains(channel) ?? false;
  }

  Future<void> dispose() async {
    await _eventSubscription.cancel();
    await bridge.stopEndpoint();
    await _peerConnectedController.close();
    await _peerDisconnectedController.close();
    await _peerMessageController.close();
    await _sessionChangedController.close();
  }

  void _setSession(Session session) {
    _sessions[session.peerId] = session;
    _sessionChangedController.add(session);
  }

  void _handleEvent(IrohTransportEvent event) {
    final peerId = _normalized(event.peerId);
    if (peerId.isEmpty) {
      return;
    }
    switch (event.type) {
      case IrohTransportEventType.data:
        _handleDataEvent(peerId, event);
      case IrohTransportEventType.diagnostics:
        _handleDiagnosticsEvent(peerId, event);
      case IrohTransportEventType.disconnected:
        final removed = _sessions.remove(peerId);
        _openChannels.remove(peerId);
        if (removed != null) {
          _peerDisconnectedController.add(peerId);
        }
      case IrohTransportEventType.error:
        final current = _sessions[peerId];
        if (current != null) {
          _setSession(
            current.copyWith(
              detail: event.error ?? 'Iroh transport error.',
              error: event.error ?? 'Iroh transport error.',
              updatedAt: event.receivedAt.millisecondsSinceEpoch,
            ),
          );
        }
      case IrohTransportEventType.unknown:
        break;
    }
  }

  void _handleDataEvent(String peerId, IrohTransportEvent event) {
    final channel = _sessionChannel(event.channel);
    final payload = event.payload;
    if (channel == null || payload == null) {
      return;
    }
    final data = switch (channel) {
      SessionChannel.chat ||
      SessionChannel.control => utf8.decode(payload, allowMalformed: true),
      SessionChannel.file => payload,
    };
    _peerMessageController.add(
      SessionMessage(
        channel: channel,
        data: data,
        receivedAt: event.receivedAt,
        peerId: peerId,
      ),
    );
  }

  void _handleDiagnosticsEvent(String peerId, IrohTransportEvent event) {
    final current = _sessions[peerId];
    if (current == null) {
      return;
    }
    final route = _routeFromDiagnostics(event);
    _setSession(
      current.copyWith(
        detail: _routeDetail(route.kind),
        route: route,
        updatedAt: event.receivedAt.millisecondsSinceEpoch,
      ),
    );
  }

  Session _session(
    String peerId,
    SessionState state, {
    required String detail,
    String? connectAttemptId,
  }) {
    return Session(
      peerId: peerId,
      state: state,
      connectionType: ConnectionType.iroh,
      phase: state == SessionState.connected
          ? SessionPhase.connected
          : SessionPhase.openingDataChannels,
      detail: detail,
      updatedAt: _now().millisecondsSinceEpoch,
      connectAttemptId: connectAttemptId,
      sender: (data) => send(peerId, SessionChannel.chat, data),
    );
  }

  bool _isDialer(String peerId) {
    final users = <String>[_normalized(selfUsername), _normalized(peerId)]
      ..sort();
    return users.first == _normalized(selfUsername);
  }
}

String _normalized(String value) => value.trim().toLowerCase();

String _roomId(String first, String second) {
  final users = <String>[_normalized(first), _normalized(second)]..sort();
  return '${users[0]}:${users[1]}';
}

String _channelId(SessionChannel channel) {
  return switch (channel) {
    SessionChannel.chat => 'rain.chat',
    SessionChannel.control => 'rain.ctrl',
    SessionChannel.file => 'rain.file',
  };
}

SessionChannel? _sessionChannel(String? channel) {
  return switch (channel) {
    'rain.chat' => SessionChannel.chat,
    'rain.ctrl' => SessionChannel.control,
    'rain.file' => SessionChannel.file,
    _ => null,
  };
}

PeerConnectionRoute _routeFromDiagnostics(IrohTransportEvent event) {
  final kind = switch (event.route) {
    'direct' => PeerRouteKind.direct,
    'relay' => PeerRouteKind.relay,
    _ => PeerRouteKind.unknown,
  };
  return PeerConnectionRoute(
    kind: kind,
    localCandidateType: switch (kind) {
      PeerRouteKind.direct => 'iroh-direct',
      PeerRouteKind.relay => 'iroh-relay',
      PeerRouteKind.unknown => null,
    },
    protocol: 'quic',
    relayProtocol: kind == PeerRouteKind.relay ? 'iroh' : null,
    rtt: event.rttMs == null ? null : event.rttMs! / 1000,
    updatedAt: event.receivedAt.millisecondsSinceEpoch,
  );
}

String _routeDetail(PeerRouteKind kind) {
  return switch (kind) {
    PeerRouteKind.direct => 'Connected over direct Iroh route.',
    PeerRouteKind.relay => 'Connected over Iroh relay route.',
    PeerRouteKind.unknown => 'Connected over Iroh fallback.',
  };
}

String _defaultAttemptId() {
  return 'iroh-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}

String _defaultSessionSecret() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes);
}
