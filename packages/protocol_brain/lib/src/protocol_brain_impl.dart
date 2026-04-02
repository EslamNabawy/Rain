import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart';

import '../adapters/signaling_adapter.dart';
import 'connection_memory.dart';
import 'session_manager.dart';

String roomId(String a, String b) {
  final sorted = <String>[a, b]..sort();
  return sorted.join(':');
}

const Duration _handshakeTimeout = Duration(seconds: 30);

class ProtocolBrainImpl implements ProtocolBrain {
  ProtocolBrainImpl({
    required this.selfUsername,
    required this.adapter,
    required this.peerConfig,
    required this.peerFactory,
    required this.connectionMemoryStore,
  });

  final String selfUsername;
  final SignalingAdapter adapter;
  final PeerConfig peerConfig;
  final PeerCoreFactory peerFactory;
  final ConnectionMemoryStore connectionMemoryStore;

  final Map<String, _ActiveSession> _sessions = <String, _ActiveSession>{};
  final Map<String, StreamSubscription<SDPPayload>> _offerSubscriptions =
      <String, StreamSubscription<SDPPayload>>{};

  final StreamController<Session> _peerConnectedController =
      StreamController<Session>.broadcast();
  final StreamController<String> _peerDisconnectedController =
      StreamController<String>.broadcast();
  final StreamController<PeerMessage> _peerMessageController =
      StreamController<PeerMessage>.broadcast();

  @override
  Stream<Session> get onPeerConnected => _peerConnectedController.stream;

  @override
  Stream<String> get onPeerDisconnected => _peerDisconnectedController.stream;

  @override
  Stream<PeerMessage> get onPeerMessage => _peerMessageController.stream;

  @override
  Future<Session> connect(String peerId) async {
    await registerPeer(peerId);
    final active = await _ensureSession(peerId);
    active.shouldReconnect = true;
    if (active.bound &&
        (active.snapshot.state == SessionState.connected ||
            active.snapshot.state == SessionState.connecting ||
            active.snapshot.state == SessionState.reconnecting)) {
      return active.snapshot;
    }
    await _startOffer(active, isRetry: false);
    return active.snapshot;
  }

  @override
  Future<void> disconnect(String peerId) async {
    final active = _sessions.remove(peerId);
    active?.shouldReconnect = false;
    await active?.dispose();
  }

  @override
  Session? getSession(String peerId) => _sessions[peerId]?.snapshot;

  @override
  List<Session> getSessions() {
    return _sessions.values.map((_ActiveSession value) => value.snapshot).toList();
  }

  @override
  Future<void> registerPeer(String peerId) async {
    if (_offerSubscriptions.containsKey(peerId)) {
      return;
    }
    final subscription = adapter.onOffer(roomId(selfUsername, peerId)).listen((
      SDPPayload offer,
    ) {
      unawaited(_handleIncomingOffer(peerId, offer));
    });
    _offerSubscriptions[peerId] = subscription;
  }

  @override
  void sendControl(String peerId, String data) {
    final active = _sessions[peerId];
    if (active == null) {
      throw StateError('No active session for $peerId');
    }
    active.peer.send(PeerChannels.control, data);
  }

  @override
  Future<void> unregisterPeer(String peerId) async {
    await _offerSubscriptions.remove(peerId)?.cancel();
  }

  Future<void> _bindPeerCore(_ActiveSession active, IceRole localRole) async {
    if (active.bound) {
      return;
    }
    active.bound = true;

    active.subscriptions.add(
      active.peer.onIceCandidate.listen((RTCIceCandidate candidate) async {
        await adapter.writeICE(active.roomId, localRole, candidate);
      }),
    );

    active.subscriptions.add(
      active.peer.onMessage.listen((PeerMessage message) {
        _peerMessageController.add(
          PeerMessage(
            channelId: message.channelId,
            data: message.data,
            receivedAt: message.receivedAt,
            peerId: active.peerId,
          ),
        );
      }),
    );

    active.subscriptions.add(
      active.peer.onConnected.listen((_) {
        active.cancelHandshakeTimeout();
        active.retryAttempt = 0;
        final connectedAt = DateTime.now().millisecondsSinceEpoch;
        _updateSession(
          active.peerId,
          active.snapshot.copyWith(
            connectedAt: connectedAt,
            state: SessionState.connected,
          ),
        );
        _peerConnectedController.add(active.snapshot);
        unawaited(adapter.deleteRoom(active.roomId));
        unawaited(
          connectionMemoryStore.write(
            ConnectionMemory(
              peerId: active.peerId,
              lastConnectedAt: connectedAt,
              cachedIce: List<RTCIceCandidate>.unmodifiable(active.remoteIceCache),
              fingerprint: active.remoteIceCache
                  .map((RTCIceCandidate candidate) => candidate.candidate ?? '')
                  .join('|'),
              consecutiveFailures: 0,
            ),
          ),
        );
      }),
    );

    active.subscriptions.add(
      active.peer.onDisconnected.listen((_) {
        if (!active.shouldReconnect) {
          return;
        }
        _peerDisconnectedController.add(active.peerId);
        unawaited(_scheduleReconnect(active.peerId));
      }),
    );
  }

  Future<void> _handleIncomingOffer(String peerId, SDPPayload offer) async {
    final active = await _ensureSession(peerId);
    if (active.peer.state != PeerState.ready &&
        active.peer.state != PeerState.failed) {
      await _recreatePeer(active);
    }
    await _bindPeerCore(active, IceRole.callee);
    active.remoteIceCache.clear();
    _updateSession(
      peerId,
      active.snapshot.copyWith(state: SessionState.connecting),
    );

    _listenForRemoteIce(active, IceRole.caller);
    final answer = await active.peer.setOffer(offer.sdp);
    await adapter.writeAnswer(
      active.roomId,
      SDPPayload(sdp: answer, ts: DateTime.now().millisecondsSinceEpoch),
    );
  }

  Future<void> _listenForAnswer(_ActiveSession active) async {
    if (active.answerSubscription != null) {
      return;
    }
    active.answerSubscription = adapter.onAnswer(active.roomId).listen((
      SDPPayload payload,
    ) async {
      active.cancelHandshakeTimeout();
      await active.peer.setAnswer(payload.sdp);
    });
  }

  void _listenForRemoteIce(_ActiveSession active, IceRole remoteRole) {
    if (active.iceSubscriptions.containsKey(remoteRole)) {
      return;
    }
    active.iceSubscriptions[remoteRole] = adapter
        .onICE(active.roomId, remoteRole)
        .listen((RTCIceCandidate candidate) async {
          active.remoteIceCache.add(candidate);
          await active.peer.addIceCandidate(candidate);
        });
  }

  Future<void> _scheduleReconnect(String peerId) async {
    final active = _sessions[peerId];
    if (active == null || !active.shouldReconnect) {
      return;
    }
    if (active.retryAttempt >= maxRetries) {
      _updateSession(
        peerId,
        active.snapshot.copyWith(state: SessionState.failed),
      );
      return;
    }

    if (active.usedCachedReconnect) {
      await _recordConnectionFailure(peerId);
      active.usedCachedReconnect = false;
    }

    _updateSession(
      peerId,
      active.snapshot.copyWith(state: SessionState.reconnecting),
    );

    final delayMs = retryDelays[active.retryAttempt.clamp(0, retryDelays.length - 1)];
    active.retryAttempt += 1;
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    if (!_sessions.containsKey(peerId) || !active.shouldReconnect) {
      return;
    }
    await _recreatePeer(active);
    await _startOffer(active, isRetry: true);
  }

  Future<_ActiveSession> _ensureSession(String peerId) async {
    final existing = _sessions[peerId];
    if (existing != null) {
      return existing;
    }

    late final _ActiveSession active;
    final peer = await _newPeer();
    active = _ActiveSession(
      peerId: peerId,
      roomId: roomId(selfUsername, peerId),
      peer: peer,
      snapshot: Session(
        peerId: peerId,
        state: SessionState.connecting,
        connectionType: ConnectionType.signaling,
        sender: (String data) => active.peer.send(PeerChannels.chat, data),
      ),
    );
    _sessions[peerId] = active;
    return active;
  }

  Future<void> _startOffer(_ActiveSession active, {required bool isRetry}) async {
    if (active.peer.state != PeerState.ready &&
        active.peer.state != PeerState.failed) {
      await _recreatePeer(active);
    }
    await _bindPeerCore(active, IceRole.caller);
    active.startHandshakeTimeout(
      () => _handleHandshakeTimeout(active.peerId),
    );
    _updateSession(
      active.peerId,
      active.snapshot.copyWith(
        state: isRetry ? SessionState.reconnecting : SessionState.connecting,
      ),
    );

    var memory = await connectionMemoryStore.read(active.peerId);
    if (memory != null && memory.isExpired) {
      await connectionMemoryStore.delete(active.peerId);
      memory = null;
    }

    final useCachedReconnect = isRetry &&
        memory != null &&
        memory.isUsable &&
        active.retryAttempt <= cachedIceAttempts;
    active.usedCachedReconnect = useCachedReconnect;

    if (useCachedReconnect) {
      for (final candidate in memory.cachedIce) {
        await active.peer.addIceCandidate(candidate);
      }
    }

    await _listenForAnswer(active);
    _listenForRemoteIce(active, IceRole.callee);
    final offer = await active.peer.createOffer();
    await adapter.writeOffer(
      active.roomId,
      SDPPayload(sdp: offer, ts: DateTime.now().millisecondsSinceEpoch),
    );
  }

  Future<PeerCore> _newPeer() async {
    final peer = peerFactory();
    await peer.init(peerConfig);
    return peer;
  }

  Future<void> _recordConnectionFailure(String peerId) async {
    final existing = await connectionMemoryStore.read(peerId);
    if (existing == null) {
      return;
    }

    final nextFailures = existing.consecutiveFailures + 1;
    if (nextFailures >= maxCacheFailures || existing.isExpired) {
      await connectionMemoryStore.delete(peerId);
      return;
    }

    await connectionMemoryStore.write(
      existing.copyWith(consecutiveFailures: nextFailures),
    );
  }

  Future<void> _recreatePeer(_ActiveSession active) async {
    await active.disposePeerBindings();
    await active.peer.destroy();
    active.peer = await _newPeer();
    active.bound = false;
    active.remoteIceCache.clear();
    active.answerSubscription = null;
    active.iceSubscriptions.clear();
  }

  void _updateSession(String peerId, Session session) {
    final active = _sessions[peerId];
    if (active == null) {
      return;
    }
    active.snapshot = session;
  }

  Future<void> _handleHandshakeTimeout(String peerId) async {
    final active = _sessions[peerId];
    if (active == null) {
      return;
    }
    if (active.snapshot.state == SessionState.connected) {
      return;
    }

    await active.disposePeerBindings();
    await active.peer.destroy();
    active.bound = false;
    active.remoteIceCache.clear();
    active.answerSubscription = null;
    active.iceSubscriptions.clear();
    active.retryAttempt = 0;
    _updateSession(
      peerId,
      active.snapshot.copyWith(state: SessionState.failed),
    );
  }
}

class _ActiveSession {
  _ActiveSession({
    required this.peerId,
    required this.roomId,
    required this.peer,
    required this.snapshot,
  });

  final String peerId;
  final String roomId;
  PeerCore peer;
  final List<StreamSubscription<dynamic>> subscriptions =
      <StreamSubscription<dynamic>>[];
  final Map<IceRole, StreamSubscription<RTCIceCandidate>> iceSubscriptions =
      <IceRole, StreamSubscription<RTCIceCandidate>>{};
  final List<RTCIceCandidate> remoteIceCache = <RTCIceCandidate>[];

  Session snapshot;
  bool bound = false;
  int retryAttempt = 0;
  bool usedCachedReconnect = false;
  bool shouldReconnect = true;
  StreamSubscription<SDPPayload>? answerSubscription;
  Timer? handshakeTimeoutTimer;

  Future<void> dispose() async {
    shouldReconnect = false;
    await disposePeerBindings();
    await peer.destroy();
  }

  Future<void> disposePeerBindings() async {
    cancelHandshakeTimeout();
    await answerSubscription?.cancel();
    answerSubscription = null;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
    for (final subscription in iceSubscriptions.values) {
      await subscription.cancel();
    }
    iceSubscriptions.clear();
  }

  void startHandshakeTimeout(Future<void> Function() onTimeout) {
    cancelHandshakeTimeout();
    handshakeTimeoutTimer = Timer(_handshakeTimeout, () {
      unawaited(onTimeout());
    });
  }

  void cancelHandshakeTimeout() {
    handshakeTimeoutTimer?.cancel();
    handshakeTimeoutTimer = null;
  }
}
