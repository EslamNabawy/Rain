import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart';

import '../adapters/signaling_adapter.dart';
import '../adapters/signaling_cipher.dart';
import 'connection_memory.dart';
import 'session_manager.dart';

String _normalizedPeerId(String peerId) => peerId.trim().toLowerCase();

String roomId(String a, String b) {
  final sorted = <String>[_normalizedPeerId(a), _normalizedPeerId(b)]..sort();
  return sorted.join(':');
}

const Duration _handshakeTimeout = Duration(seconds: 60);
const Duration _routeRefreshDelay = Duration(milliseconds: 850);

Duration _maxDuration(Duration a, Duration b) {
  return a.compareTo(b) >= 0 ? a : b;
}

class ProtocolBrainImpl implements ProtocolBrain {
  ProtocolBrainImpl({
    required this.selfUsername,
    required this.adapter,
    required this.peerConfig,
    required this.peerFactory,
    required this.connectionMemoryStore,
    this.reconnectGrace = const Duration(seconds: 2),
  });

  final String selfUsername;
  final SignalingAdapter adapter;
  final PeerConfig peerConfig;
  final PeerCoreFactory peerFactory;
  final ConnectionMemoryStore connectionMemoryStore;
  final Duration reconnectGrace;

  final Map<String, _ActiveSession> _sessions = <String, _ActiveSession>{};
  final Map<String, StreamSubscription<SDPPayload>> _offerSubscriptions =
      <String, StreamSubscription<SDPPayload>>{};

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
    await registerPeer(peerId);
    final active = await _ensureSession(peerId);
    active.shouldReconnect = true;
    if (active.bound &&
        (active.snapshot.state == SessionState.connected ||
            active.snapshot.state == SessionState.connecting ||
            active.snapshot.state == SessionState.reconnecting)) {
      return active.snapshot;
    }
    try {
      if (_isOfferOwner(peerId)) {
        await _startOffer(active, isRetry: false);
      } else {
        await _waitForOffer(active, isRetry: false);
      }
    } catch (error) {
      await _failConnectAttempt(active, error);
      rethrow;
    }
    return active.snapshot;
  }

  @override
  Future<void> disconnect(String peerId) async {
    final active = _sessions[peerId];
    active?.shouldReconnect = false;
    if (active != null) {
      _markPhase(
        active,
        SessionPhase.disconnecting,
        'Disconnecting from peer.',
      );
    }
    _sessions.remove(peerId);
    if (active != null) {
      await _deleteRoomSilently(active);
    }
    await active?.dispose();
    _peerDisconnectedController.add(peerId);
  }

  @override
  Session? getSession(String peerId) => _sessions[peerId]?.snapshot;

  @override
  List<Session> getSessions() {
    return _sessions.values
        .map((_ActiveSession value) => value.snapshot)
        .toList();
  }

  @override
  Future<void> registerPeer(String peerId) async {
    if (_offerSubscriptions.containsKey(peerId)) {
      return;
    }
    final shouldHandleIncomingOffers = !_isOfferOwner(peerId);
    final subscription = adapter
        .onOffer(roomId(selfUsername, peerId))
        .listen(
          (SDPPayload offer) {
            if (!shouldHandleIncomingOffers) {
              return;
            }
            unawaited(_handleIncomingOffer(peerId, offer));
          },
          onError: (Object error, StackTrace stackTrace) {
            _handleSignalingStreamError(peerId, error, source: 'offer');
          },
        );
    _offerSubscriptions[peerId] = subscription;
  }

  @override
  void sendControl(String peerId, String data) {
    send(peerId, SessionChannel.control, data);
  }

  @override
  void send(String peerId, SessionChannel channel, Object data) {
    final active = _sessions[peerId];
    if (active == null) {
      throw StateError('No active session for $peerId');
    }
    active.peer.send(_toPeerChannel(channel), data);
  }

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) async {
    final active = _sessions[peerId];
    if (active == null) {
      throw StateError('No active session for $peerId');
    }
    await active.peer.openChannel(_toPeerChannel(channel));
  }

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async {
    final active = _sessions[peerId];
    if (active == null) {
      throw StateError('No active session for $peerId');
    }
    return active.peer.bufferedAmount(_toPeerChannel(channel));
  }

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) {
    final active = _sessions[peerId];
    if (active == null) {
      return false;
    }
    return active.peer.isChannelOpen(_toPeerChannel(channel));
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
        _markPhase(
          active,
          SessionPhase.exchangingIce,
          'Sending local ICE candidate.',
        );
        await adapter.writeICE(active.roomId, localRole, candidate);
      }),
    );

    active.subscriptions.add(
      active.peer.onMessage.listen((PeerMessage message) {
        _peerMessageController.add(_toSessionMessage(message, active.peerId));
      }),
    );

    active.subscriptions.add(
      active.peer.onConnected.listen((_) {
        _handlePeerConnected(active);
      }),
    );

    active.subscriptions.add(
      active.peer.onDisconnected.listen((_) {
        if (!active.shouldReconnect) {
          return;
        }
        _markPhase(
          active,
          SessionPhase.reconnecting,
          'Peer disconnected. Scheduling reconnect.',
          state: SessionState.reconnecting,
        );
        unawaited(
          _scheduleReconnect(active.peerId, minimumDelay: reconnectGrace),
        );
      }),
    );

    active.subscriptions.add(
      active.peer.onStateChange.listen((PeerState state) {
        switch (state) {
          case PeerState.offering:
            _markPhase(
              active,
              SessionPhase.creatingOffer,
              'Local offer created.',
            );
            break;
          case PeerState.answering:
            _markPhase(
              active,
              SessionPhase.writingAnswer,
              'Remote offer accepted. Writing answer.',
            );
            break;
          case PeerState.connecting:
            _markPhase(
              active,
              SessionPhase.openingDataChannels,
              'Opening chat and control channels.',
            );
            break;
          case PeerState.reconnecting:
            _markPhase(
              active,
              SessionPhase.reconnecting,
              'Peer transport reconnecting.',
              state: SessionState.reconnecting,
            );
            break;
          case PeerState.failed:
            unawaited(_deleteRoomSilently(active));
            _markPhase(
              active,
              SessionPhase.failed,
              'Peer transport failed.',
              state: SessionState.failed,
              error: 'Peer transport failed.',
            );
            break;
          case PeerState.idle:
          case PeerState.ready:
          case PeerState.connected:
            break;
        }
      }),
    );
  }

  void _handlePeerConnected(_ActiveSession active) {
    active.cancelPendingReconnect();
    active.cancelHandshakeTimeout();
    active.retryAttempt = 0;
    active.usedCachedReconnect = false;
    final connectedAt = DateTime.now().millisecondsSinceEpoch;
    _updateSession(
      active.peerId,
      active.snapshot.copyWith(
        connectedAt: connectedAt,
        state: SessionState.connected,
        phase: SessionPhase.connected,
        detail: 'Detecting route...',
        updatedAt: connectedAt,
        retryAttempt: 0,
        route: PeerConnectionRoute.unknown(updatedAt: connectedAt),
        clearError: true,
      ),
    );
    unawaited(_refreshRoute(active));
    unawaited(
      Future<void>.delayed(_routeRefreshDelay, () => _refreshRoute(active)),
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
  }

  Future<void> _handleIncomingOffer(String peerId, SDPPayload offer) async {
    final active = await _ensureSession(peerId);
    if (active.snapshot.state == SessionState.connected ||
        active.peer.state == PeerState.connected) {
      return;
    }
    if (active.lastOfferTs != null && offer.ts <= active.lastOfferTs!) {
      return;
    }
    active.lastOfferTs = offer.ts;
    if (active.peer.state != PeerState.ready) {
      await _recreatePeer(active);
    }
    await _bindPeerCore(active, IceRole.callee);
    active.remoteIceCache.clear();
    _markPhase(
      active,
      SessionPhase.writingAnswer,
      'Received offer. Creating answer.',
      state: SessionState.connecting,
    );
    active.startHandshakeTimeout(() => _handleHandshakeTimeout(active.peerId));

    _listenForRemoteIce(active, IceRole.caller);
    final answer = await active.peer.setOffer(offer.sdp);
    await adapter.writeAnswer(
      active.roomId,
      SDPPayload(sdp: answer, ts: DateTime.now().millisecondsSinceEpoch),
    );
    _markPhase(
      active,
      SessionPhase.exchangingIce,
      'Answer written. Exchanging network candidates.',
    );
  }

  Future<void> _listenForAnswer(_ActiveSession active) async {
    if (active.answerSubscription != null) {
      return;
    }
    active.answerSubscription = adapter
        .onAnswer(active.roomId)
        .listen(
          (SDPPayload payload) async {
            if (active.snapshot.state == SessionState.connected ||
                active.peer.state != PeerState.offering ||
                (active.lastAnswerTs != null &&
                    payload.ts <= active.lastAnswerTs!)) {
              return;
            }
            active.lastAnswerTs = payload.ts;
            _markPhase(
              active,
              SessionPhase.openingDataChannels,
              'Received answer. Opening data channels.',
            );
            await active.peer.setAnswer(payload.sdp);
            await active.answerSubscription?.cancel();
            active.answerSubscription = null;
          },
          onError: (Object error, StackTrace stackTrace) {
            _handleSignalingStreamError(active.peerId, error, source: 'answer');
          },
        );
  }

  void _listenForRemoteIce(_ActiveSession active, IceRole remoteRole) {
    if (active.iceSubscriptions.containsKey(remoteRole)) {
      return;
    }
    active.iceSubscriptions[remoteRole] = adapter
        .onICE(active.roomId, remoteRole)
        .listen(
          (RTCIceCandidate candidate) async {
            active.remoteIceCache.add(candidate);
            _markPhase(
              active,
              SessionPhase.exchangingIce,
              'Received remote ICE candidate.',
            );
            await active.peer.addIceCandidate(candidate);
          },
          onError: (Object error, StackTrace stackTrace) {
            _handleSignalingStreamError(
              active.peerId,
              error,
              source: '${remoteRole.name} ICE',
            );
          },
        );
  }

  Future<void> _scheduleReconnect(
    String peerId, {
    Duration minimumDelay = Duration.zero,
  }) async {
    final active = _sessions[peerId];
    if (active == null || !active.shouldReconnect) {
      return;
    }
    if (active.snapshot.state == SessionState.connected ||
        active.reconnectInProgress) {
      return;
    }
    if (active.retryAttempt >= maxRetries) {
      active.stopReconnecting();
      await _deleteRoomSilently(active);
      _updateSession(
        peerId,
        active.snapshot.copyWith(
          state: SessionState.failed,
          phase: SessionPhase.failed,
          detail: 'Connection failed after retries.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          error: 'Connection failed after retries.',
          route: PeerConnectionRoute.unknown(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      return;
    }

    active.reconnectInProgress = true;
    if (active.usedCachedReconnect) {
      await _recordConnectionFailure(peerId);
      active.usedCachedReconnect = false;
    }
    if (_sessions[peerId] != active ||
        !active.shouldReconnect ||
        active.snapshot.state == SessionState.connected) {
      active.reconnectInProgress = false;
      return;
    }

    _updateSession(
      peerId,
      active.snapshot.copyWith(
        state: SessionState.reconnecting,
        phase: SessionPhase.reconnecting,
        detail: 'Reconnect attempt ${active.retryAttempt + 1} scheduled.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        retryAttempt: active.retryAttempt + 1,
        route: PeerConnectionRoute.unknown(
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );

    final baseDelay = Duration(
      milliseconds:
          retryDelays[active.retryAttempt.clamp(0, retryDelays.length - 1)],
    );
    final delay = _maxDuration(baseDelay, minimumDelay);
    active.retryAttempt += 1;
    final generation = active.nextReconnectGeneration();
    active.reconnectTimer = Timer(delay, () {
      active.reconnectTimer = null;
      unawaited(_runScheduledReconnect(peerId, active, generation));
    });
  }

  Future<void> _runScheduledReconnect(
    String peerId,
    _ActiveSession active,
    int generation,
  ) async {
    try {
      if (_sessions[peerId] != active ||
          !active.shouldReconnect ||
          active.reconnectGeneration != generation ||
          active.snapshot.state == SessionState.connected) {
        return;
      }
      final recreated = await _recreatePeer(
        active,
        shouldContinue: () =>
            _canRunScheduledReconnect(peerId, active, generation),
        restoreRole: _localRoleFor(peerId),
      );
      if (!recreated) {
        return;
      }
      if (_sessions[peerId] != active ||
          !active.shouldReconnect ||
          active.reconnectGeneration != generation ||
          active.snapshot.state == SessionState.connected) {
        return;
      }
      if (_isOfferOwner(peerId)) {
        await _startOffer(active, isRetry: true);
      } else {
        await _waitForOffer(active, isRetry: true);
      }
    } finally {
      if (_sessions[peerId] == active &&
          active.reconnectGeneration == generation) {
        active.reconnectInProgress = false;
      }
    }
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
        phase: SessionPhase.registeringPeer,
        detail: 'Preparing peer session.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        roomId: roomId(selfUsername, peerId),
        isOfferOwner: _isOfferOwner(peerId),
        sender: (String data) => active.peer.send(PeerChannels.chat, data),
      ),
    );
    _sessions[peerId] = active;
    return active;
  }

  Future<void> _startOffer(
    _ActiveSession active, {
    required bool isRetry,
  }) async {
    if (active.peer.state != PeerState.ready) {
      await _recreatePeer(active);
    }
    await _resetRoomForNewOffer(active);
    await _bindPeerCore(active, IceRole.caller);
    active.startHandshakeTimeout(() => _handleHandshakeTimeout(active.peerId));
    _markPhase(
      active,
      SessionPhase.creatingOffer,
      isRetry ? 'Creating retry offer.' : 'Creating signaling offer.',
      state: isRetry ? SessionState.reconnecting : SessionState.connecting,
    );

    var memory = await connectionMemoryStore.read(active.peerId);
    if (memory != null && memory.isExpired) {
      await connectionMemoryStore.delete(active.peerId);
      memory = null;
    }

    final useCachedReconnect =
        isRetry &&
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
    _markPhase(
      active,
      SessionPhase.writingOffer,
      'Writing offer to signaling room.',
    );
    await adapter.writeOffer(
      active.roomId,
      SDPPayload(sdp: offer, ts: DateTime.now().millisecondsSinceEpoch),
    );
    _markPhase(
      active,
      SessionPhase.waitingForAnswer,
      'Offer written. Waiting for answer.',
    );
  }

  Future<void> _resetRoomForNewOffer(_ActiveSession active) async {
    await adapter.deleteRoom(active.roomId);
    active.lastAnswerTs = null;
    active.remoteIceCache.clear();
  }

  Future<void> _failConnectAttempt(_ActiveSession active, Object error) async {
    active.stopReconnecting();
    active.cancelHandshakeTimeout();
    await active.disposePeerBindings();
    active.bound = false;
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    _updateSession(
      active.peerId,
      active.snapshot.copyWith(
        state: SessionState.failed,
        phase: SessionPhase.failed,
        detail: 'Connection setup failed.',
        updatedAt: updatedAt,
        error: _connectSetupFailureMessage(error),
        route: PeerConnectionRoute.unknown(updatedAt: updatedAt),
      ),
    );
  }

  String _connectSetupFailureMessage(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    if (message.startsWith('Bad state: ')) {
      return message.substring('Bad state: '.length);
    }
    if (message.startsWith('StateError: ')) {
      return message.substring('StateError: '.length);
    }
    return message;
  }

  Future<void> _waitForOffer(
    _ActiveSession active, {
    required bool isRetry,
  }) async {
    if (active.peer.state != PeerState.ready) {
      await _recreatePeer(active);
    }
    active.startHandshakeTimeout(() => _handleHandshakeTimeout(active.peerId));
    _markPhase(
      active,
      SessionPhase.waitingForOffer,
      isRetry ? 'Waiting for retry offer.' : 'Waiting for remote offer.',
      state: isRetry ? SessionState.reconnecting : SessionState.connecting,
    );
  }

  bool _isOfferOwner(String peerId) {
    return _normalizedPeerId(
          selfUsername,
        ).compareTo(_normalizedPeerId(peerId)) <=
        0;
  }

  IceRole _localRoleFor(String peerId) {
    return _isOfferOwner(peerId) ? IceRole.caller : IceRole.callee;
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

  Future<bool> _recreatePeer(
    _ActiveSession active, {
    bool Function()? shouldContinue,
    IceRole? restoreRole,
  }) async {
    if (shouldContinue != null && !shouldContinue()) {
      return false;
    }
    await active.disposePeerBindings();
    if (shouldContinue != null && !shouldContinue()) {
      active.bound = false;
      if (_sessions[active.peerId] == active &&
          active.shouldReconnect &&
          active.peer.state == PeerState.connected &&
          restoreRole != null) {
        await _bindPeerCore(active, restoreRole);
        if (active.snapshot.state != SessionState.connected) {
          _handlePeerConnected(active);
        }
      }
      return false;
    }
    await active.peer.destroy();
    active.peer = await _newPeer();
    active.bound = false;
    active.remoteIceCache.clear();
    active.answerSubscription = null;
    active.iceSubscriptions.clear();
    return true;
  }

  bool _canRunScheduledReconnect(
    String peerId,
    _ActiveSession active,
    int generation,
  ) {
    return _sessions[peerId] == active &&
        active.shouldReconnect &&
        active.reconnectGeneration == generation &&
        active.snapshot.state != SessionState.connected &&
        active.peer.state != PeerState.connected;
  }

  void _updateSession(String peerId, Session session) {
    final active = _sessions[peerId];
    if (active == null) {
      return;
    }
    active.snapshot = session;
    _sessionChangedController.add(session);
  }

  void _markPhase(
    _ActiveSession active,
    SessionPhase phase,
    String detail, {
    SessionState? state,
    String? error,
  }) {
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    final route = switch (state) {
      SessionState.connecting ||
      SessionState.reconnecting ||
      SessionState.failed => PeerConnectionRoute.unknown(updatedAt: updatedAt),
      SessionState.connected || null => null,
    };
    _updateSession(
      active.peerId,
      active.snapshot.copyWith(
        state: state,
        phase: phase,
        detail: detail,
        updatedAt: updatedAt,
        error: error,
        clearError: error == null,
        retryAttempt: active.retryAttempt,
        roomId: active.roomId,
        isOfferOwner: _isOfferOwner(active.peerId),
        route: route,
      ),
    );
  }

  Future<void> _refreshRoute(_ActiveSession active) async {
    if (!_canPublishRoute(active)) {
      return;
    }
    try {
      final route = await active.peer.currentRoute();
      if (!_canPublishRoute(active)) {
        return;
      }
      final updatedAt =
          route.updatedAt ?? DateTime.now().millisecondsSinceEpoch;
      _updateSession(
        active.peerId,
        active.snapshot.copyWith(
          detail: _routeDetail(route),
          updatedAt: updatedAt,
          route: route,
          clearError: true,
        ),
      );
    } catch (_) {
      // Route stats are diagnostic only; they must not fail the peer session.
    }
  }

  bool _canPublishRoute(_ActiveSession active) {
    return _sessions[active.peerId] == active &&
        active.snapshot.state == SessionState.connected &&
        active.peer.state == PeerState.connected;
  }

  String _routeDetail(PeerConnectionRoute route) {
    return switch (route.kind) {
      PeerRouteKind.direct => 'Direct encrypted peer lane is open.',
      PeerRouteKind.relay => 'Encrypted peer lane is relayed through TURN.',
      PeerRouteKind.unknown => 'Detecting route...',
    };
  }

  void _handleSignalingStreamError(
    String peerId,
    Object error, {
    required String source,
  }) {
    final active = _sessions[peerId];
    if (active == null) {
      return;
    }
    active.stopReconnecting();
    unawaited(_deleteRoomSilently(active));
    unawaited(active.disposePeerBindings());
    _updateSession(
      peerId,
      active.snapshot.copyWith(
        state: SessionState.failed,
        phase: SessionPhase.failed,
        detail: 'Signaling failed while reading $source data.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        error: _signalingFailureMessage(error),
        route: PeerConnectionRoute.unknown(
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  String _signalingFailureMessage(Object error) {
    if (error is SignalingEncryptionException) {
      return 'Encrypted signaling data could not be read. Make sure both devices use the same latest build and signaling encryption key, then clear stale Firebase rooms before retrying.';
    }
    return 'Peer signaling data could not be read: $error';
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
    await _deleteRoomSilently(active);
    active.bound = false;
    active.remoteIceCache.clear();
    active.answerSubscription = null;
    active.iceSubscriptions.clear();
    if (!active.shouldReconnect) {
      active.stopReconnecting();
      _updateSession(
        peerId,
        active.snapshot.copyWith(
          state: SessionState.failed,
          phase: SessionPhase.failed,
          detail: 'Handshake timed out.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          error: 'Handshake timed out.',
          route: PeerConnectionRoute.unknown(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      return;
    }

    if (active.retryAttempt >= maxRetries) {
      active.stopReconnecting();
      await _deleteRoomSilently(active);
      _updateSession(
        peerId,
        active.snapshot.copyWith(
          state: SessionState.failed,
          phase: SessionPhase.failed,
          detail: 'Connection failed after retries.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          error: 'Connection failed after retries.',
          route: PeerConnectionRoute.unknown(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      return;
    }

    unawaited(_scheduleReconnect(peerId));
  }

  Future<void> _deleteRoomSilently(_ActiveSession active) async {
    try {
      await adapter.deleteRoom(active.roomId);
    } catch (_) {
      // Room cleanup is best-effort; connection state still reports failure.
    }
  }
}

SessionMessage _toSessionMessage(PeerMessage message, String peerId) {
  return SessionMessage(
    channel: _toSessionChannel(message.channelId),
    data: message.data,
    receivedAt: message.receivedAt,
    peerId: peerId,
  );
}

SessionChannel _toSessionChannel(String channelId) {
  switch (channelId) {
    case PeerChannels.chat:
      return SessionChannel.chat;
    case PeerChannels.control:
      return SessionChannel.control;
    case PeerChannels.file:
      return SessionChannel.file;
  }
  throw StateError('Unknown peer channel: $channelId');
}

String _toPeerChannel(SessionChannel channel) {
  switch (channel) {
    case SessionChannel.chat:
      return PeerChannels.chat;
    case SessionChannel.control:
      return PeerChannels.control;
    case SessionChannel.file:
      return PeerChannels.file;
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
  bool reconnectInProgress = false;
  int reconnectGeneration = 0;
  int? lastOfferTs;
  int? lastAnswerTs;
  StreamSubscription<SDPPayload>? answerSubscription;
  Timer? handshakeTimeoutTimer;
  Timer? reconnectTimer;

  Future<void> dispose() async {
    shouldReconnect = false;
    stopReconnecting();
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

  int nextReconnectGeneration() {
    reconnectGeneration += 1;
    return reconnectGeneration;
  }

  void cancelPendingReconnect() {
    reconnectTimer?.cancel();
    reconnectTimer = null;
    reconnectInProgress = false;
    reconnectGeneration += 1;
  }

  void stopReconnecting() {
    shouldReconnect = false;
    cancelPendingReconnect();
  }
}
