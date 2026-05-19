import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart';

import '../adapters/signaling_adapter.dart';
import '../adapters/signaling_cipher.dart';
import 'connection_memory.dart';
import 'ice_attempt.dart';
import 'session_manager.dart';

String _normalizedPeerId(String peerId) => peerId.trim().toLowerCase();

String roomId(String a, String b) {
  final sorted = <String>[_normalizedPeerId(a), _normalizedPeerId(b)]..sort();
  return sorted.join(':');
}

const Duration _directHandshakeTimeout = Duration(seconds: 12);
const Duration _waitingForOfferTimeout = Duration(seconds: 45);
const Duration _routeRefreshDelay = Duration(milliseconds: 850);

typedef PeerConfigProvider =
    Future<PeerConfig> Function(PeerIceTransportPolicy policy);
typedef IceAttemptConfigProvider =
    Future<PeerConfig> Function(IceAttemptDescriptor attempt);
typedef IceAttemptResultRecorder =
    FutureOr<void> Function(IceAttemptResult result);

Duration _maxDuration(Duration a, Duration b) {
  return a.compareTo(b) >= 0 ? a : b;
}

bool _cachedIceReconnectEnabled() {
  return false;
}

class ProtocolBrainImpl implements ProtocolBrain {
  ProtocolBrainImpl({
    required this.selfUsername,
    required this.adapter,
    required this.peerConfig,
    required this.peerFactory,
    required this.connectionMemoryStore,
    this.peerConfigProvider,
    this.iceAttemptConfigProvider,
    this.iceAttemptResultRecorder,
    this.enableExperimentalRelay = false,
    this.reconnectGrace = const Duration(seconds: 2),
  });

  final String selfUsername;
  final SignalingAdapter adapter;
  final PeerConfig peerConfig;
  final PeerCoreFactory peerFactory;
  final ConnectionMemoryStore connectionMemoryStore;
  final PeerConfigProvider? peerConfigProvider;
  final IceAttemptConfigProvider? iceAttemptConfigProvider;
  final IceAttemptResultRecorder? iceAttemptResultRecorder;
  final bool enableExperimentalRelay;
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
    final plan = IceAttemptPlan.staged(
      peerId: peerId,
      selfUsername: selfUsername,
      now: DateTime.now(),
      enableExperimentalRelay: enableExperimentalRelay,
    );
    final firstAttempt = plan.first;
    if (firstAttempt == null) {
      throw StateError('No ICE connection attempts are configured.');
    }
    final existing = _sessions[peerId];
    final active = await _ensureSession(peerId, initialAttempt: firstAttempt);
    active.shouldReconnect = true;
    if (active.bound &&
        (active.snapshot.state == SessionState.connected ||
            active.snapshot.state == SessionState.connecting ||
            active.snapshot.state == SessionState.reconnecting)) {
      return active.snapshot;
    }
    active.startAttemptPlan(plan);
    active.icePolicy = firstAttempt.policy;
    active.retryAttempt = 0;
    if (existing != null ||
        active.peer.state != PeerState.ready ||
        active.snapshot.state == SessionState.failed) {
      await _recreatePeer(active, attempt: firstAttempt);
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
            unawaited(
              _handleIncomingOffer(peerId, offer).catchError((Object error) {
                _handleIncomingOfferFailure(peerId, error);
              }),
            );
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
        await adapter.writeICE(
          active.roomId,
          localRole,
          IceCandidatePayload(
            candidate: candidate,
            connectAttemptId: active.currentAttempt?.connectAttemptId,
            iceStage: active.currentAttempt?.stage.wireName,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
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
            unawaited(active.disposePeerBindings());
            if (active.shouldReconnect &&
                active.snapshot.state != SessionState.connected) {
              unawaited(_tryNextIceAttempt(active, 'Direct path failed.'));
              break;
            }
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
        iceStage: active.currentAttempt?.stage,
        providerTier: active.currentAttempt?.providerTier,
        providerId: active.currentAttempt?.providerId,
        connectAttemptId: active.currentAttempt?.connectAttemptId,
        attemptIndex: active.currentAttempt?.attemptIndex ?? 0,
        clearError: true,
      ),
    );
    unawaited(_refreshRoute(active));
    unawaited(
      Future<void>.delayed(_routeRefreshDelay, () => _refreshRoute(active)),
    );
    _recordAttemptResult(active, succeeded: true, route: active.snapshot.route);
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
    var policyChanged = false;
    final offerAttempt = _attemptFromPayload(active, offer);
    final offerPolicy = offerAttempt?.policy ?? _icePolicyFromPayload(offer);
    if (offerAttempt != null &&
        offerAttempt.connectAttemptId !=
            active.currentAttempt?.connectAttemptId) {
      active.currentAttempt = offerAttempt;
      active.icePolicy = offerAttempt.policy;
      policyChanged = true;
    } else if (offerPolicy != null && offerPolicy != active.icePolicy) {
      active.icePolicy = offerPolicy;
      policyChanged = true;
    }
    if (policyChanged || active.peer.state != PeerState.ready) {
      await _recreatePeer(
        active,
        attempt: offerAttempt,
        policy: offerAttempt == null ? active.icePolicy : null,
      );
    }
    await _bindPeerCore(active, IceRole.callee);
    active.remoteIceCache.clear();
    _markPhase(
      active,
      SessionPhase.writingAnswer,
      'Received offer. Creating answer.',
      state: SessionState.connecting,
    );
    active.startHandshakeTimeout(
      () => _handleHandshakeTimeout(active.peerId),
      duration: _handshakeTimeoutFor(active),
    );

    _listenForRemoteIce(active, IceRole.caller);
    final answer = await active.peer.setOffer(offer.sdp);
    await adapter.writeAnswer(
      active.roomId,
      SDPPayload(
        sdp: answer,
        ts: DateTime.now().millisecondsSinceEpoch,
        icePolicy: _icePolicyPayload(active.icePolicy),
        connectAttemptId: active.currentAttempt?.connectAttemptId,
        iceStage: active.currentAttempt?.stage.wireName,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
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
                !_payloadMatchesCurrentAttempt(active, payload) ||
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
          (IceCandidatePayload payload) async {
            if (!_icePayloadMatchesCurrentAttempt(active, payload)) {
              return;
            }
            active.remoteIceCache.add(payload.candidate);
            _markPhase(
              active,
              SessionPhase.exchangingIce,
              'Received remote ICE candidate.',
            );
            await active.peer.addIceCandidate(payload.candidate);
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

  Future<_ActiveSession> _ensureSession(
    String peerId, {
    IceAttemptDescriptor? initialAttempt,
  }) async {
    final existing = _sessions[peerId];
    if (existing != null) {
      return existing;
    }

    late final _ActiveSession active;
    final peer = await _newPeer(
      policy: initialAttempt?.policy ?? PeerIceTransportPolicy.all,
      attempt: initialAttempt,
    );
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
    active.startHandshakeTimeout(
      () => _handleHandshakeTimeout(active.peerId),
      duration: _handshakeTimeoutFor(active),
    );
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
        _cachedIceReconnectEnabled() &&
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
      SDPPayload(
        sdp: offer,
        ts: DateTime.now().millisecondsSinceEpoch,
        icePolicy: _icePolicyPayload(active.icePolicy),
        connectAttemptId: active.currentAttempt?.connectAttemptId,
        iceStage: active.currentAttempt?.stage.wireName,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _markPhase(
      active,
      SessionPhase.waitingForAnswer,
      _waitingForAnswerDetail(active),
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
    active.startHandshakeTimeout(
      () => _handleHandshakeTimeout(active.peerId),
      duration: _waitingForOfferTimeout,
    );
    _markPhase(
      active,
      SessionPhase.waitingForOffer,
      _waitingForOfferDetail(active, isRetry: isRetry),
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

  Future<PeerCore> _newPeer({
    PeerIceTransportPolicy policy = PeerIceTransportPolicy.all,
    IceAttemptDescriptor? attempt,
  }) async {
    final peer = peerFactory();
    final config = attempt != null && iceAttemptConfigProvider != null
        ? await iceAttemptConfigProvider!(attempt)
        : peerConfigProvider == null
        ? peerConfig.copyWith(iceTransportPolicy: policy)
        : await peerConfigProvider!(policy);
    final effectivePolicy = attempt?.policy ?? policy;
    await peer.init(config.copyWith(iceTransportPolicy: effectivePolicy));
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
    PeerIceTransportPolicy? policy,
    IceAttemptDescriptor? attempt,
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
    final nextAttempt =
        attempt ?? (policy == null ? active.currentAttempt : null);
    final nextPolicy = policy ?? nextAttempt?.policy ?? active.icePolicy;
    active.peer = await _newPeer(policy: nextPolicy, attempt: nextAttempt);
    active.icePolicy = nextPolicy;
    if (nextAttempt != null) {
      active.currentAttempt = nextAttempt;
    }
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
        iceStage: active.currentAttempt?.stage,
        providerTier: active.currentAttempt?.providerTier,
        providerId: active.currentAttempt?.providerId,
        connectAttemptId: active.currentAttempt?.connectAttemptId,
        attemptIndex: active.currentAttempt?.attemptIndex ?? 0,
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
    if (await _tryNextIceAttempt(
      active,
      _timeoutFailureFor(active.currentAttempt),
    )) {
      return;
    }
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

  Duration _handshakeTimeoutFor(_ActiveSession active) {
    final attemptTimeout =
        active.currentAttempt?.timeout ?? _directHandshakeTimeout;
    final startedAt = active.connectStartedAt;
    final budget = active.attemptPlan?.maxBudget;
    if (startedAt == null || budget == null) {
      return attemptTimeout;
    }
    final elapsed = Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch - startedAt,
    );
    final remaining = budget - elapsed;
    if (remaining <= Duration.zero) {
      return const Duration(milliseconds: 1);
    }
    return remaining < attemptTimeout ? remaining : attemptTimeout;
  }

  Future<bool> _tryNextIceAttempt(
    _ActiveSession active,
    String failureReason,
  ) async {
    if (_sessions[active.peerId] != active || !active.shouldReconnect) {
      return false;
    }

    if (iceAttemptConfigProvider == null &&
        active.currentAttempt?.requiresRelay == true) {
      _recordAttemptResult(active, succeeded: false, reason: failureReason);
      _failAllAttempts(active, failureReason);
      return false;
    }

    final nextAttempt = active.attemptPlan?.after(active.currentAttempt);
    if (nextAttempt == null) {
      _recordAttemptResult(active, succeeded: false, reason: failureReason);
      _failAllAttempts(active, failureReason);
      return false;
    }

    _recordAttemptResult(active, succeeded: false, reason: failureReason);
    active.cancelPendingReconnect();
    active.cancelHandshakeTimeout();
    active.retryAttempt = nextAttempt.attemptIndex;
    active.currentAttempt = nextAttempt;
    active.icePolicy = nextAttempt.policy;
    _markPhase(
      active,
      SessionPhase.reconnecting,
      _attemptStartDetail(nextAttempt),
      state: SessionState.reconnecting,
      error: failureReason,
    );

    try {
      final recreated = await _recreatePeer(active, attempt: nextAttempt);
      if (!recreated || _sessions[active.peerId] != active) {
        return false;
      }
      if (_isOfferOwner(active.peerId)) {
        await _startOffer(active, isRetry: true);
      } else {
        await _waitForOffer(active, isRetry: true);
      }
      return true;
    } catch (error) {
      return _tryNextIceAttempt(
        active,
        _attemptFailedMessage(nextAttempt, _connectSetupFailureMessage(error)),
      );
    }
  }

  void _failAllAttempts(_ActiveSession active, String failureReason) {
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    final error = _finalConnectFailure(failureReason);
    active.stopReconnecting();
    _updateSession(
      active.peerId,
      active.snapshot.copyWith(
        state: SessionState.failed,
        phase: SessionPhase.failed,
        detail: error,
        updatedAt: updatedAt,
        error: error,
        retryAttempt:
            active.currentAttempt?.attemptIndex ?? active.retryAttempt,
        route: PeerConnectionRoute.unknown(updatedAt: updatedAt),
        iceStage: active.currentAttempt?.stage,
        providerTier: active.currentAttempt?.providerTier,
        providerId: active.currentAttempt?.providerId,
        connectAttemptId: active.currentAttempt?.connectAttemptId,
        attemptIndex: active.currentAttempt?.attemptIndex ?? 0,
      ),
    );
  }

  void _recordAttemptResult(
    _ActiveSession active, {
    required bool succeeded,
    String? reason,
    PeerConnectionRoute route = const PeerConnectionRoute.unknown(),
  }) {
    final attempt = active.currentAttempt;
    final recorder = iceAttemptResultRecorder;
    if (attempt == null || recorder == null) {
      return;
    }
    unawaited(
      Future<void>.sync(() {
        return recorder(
          IceAttemptResult(
            attempt: attempt,
            succeeded: succeeded,
            completedAt: DateTime.now(),
            failureReason: reason,
            route: route,
          ),
        );
      }),
    );
  }

  String _timeoutFailureFor(IceAttemptDescriptor? attempt) {
    return switch (attempt?.stage) {
      IceAttemptStage.directStunOnly => 'Direct path blocked.',
      IceAttemptStage.primaryRelay ||
      IceAttemptStage.backupRelay ||
      IceAttemptStage.experimentalRelay => 'Relay provider timed out.',
      IceAttemptStage.fullRestart => 'Data channel did not open.',
      null => 'Handshake timed out.',
    };
  }

  String _attemptStartDetail(IceAttemptDescriptor attempt) {
    return switch (attempt.stage) {
      IceAttemptStage.directStunOnly => 'Trying direct peer route.',
      IceAttemptStage.primaryRelay =>
        'Direct path blocked. Trying primary TURN relay.',
      IceAttemptStage.backupRelay => 'Trying backup TURN relay.',
      IceAttemptStage.experimentalRelay =>
        'Trying experimental relay fallback.',
      IceAttemptStage.fullRestart =>
        'Refreshing ICE credentials and restarting connection.',
    };
  }

  String _waitingForAnswerDetail(_ActiveSession active) {
    final attempt = active.currentAttempt;
    if (attempt == null ||
        attempt.stage == IceAttemptStage.directStunOnly ||
        attempt.stage == IceAttemptStage.fullRestart) {
      return 'Offer written. Waiting for answer.';
    }
    return '${_attemptStartDetail(attempt)} Offer written. Waiting for answer.';
  }

  String _waitingForOfferDetail(
    _ActiveSession active, {
    required bool isRetry,
  }) {
    final base = isRetry
        ? 'Waiting for retry offer.'
        : 'Waiting for remote offer.';
    final attempt = active.currentAttempt;
    if (attempt == null ||
        attempt.stage == IceAttemptStage.directStunOnly ||
        attempt.stage == IceAttemptStage.fullRestart) {
      return base;
    }
    return '${_attemptStartDetail(attempt)} $base';
  }

  String _attemptFailedMessage(IceAttemptDescriptor attempt, String reason) {
    final cleanReason = reason.trim().isEmpty ? 'unknown error' : reason.trim();
    return switch (attempt.stage) {
      IceAttemptStage.directStunOnly => 'Direct path blocked.',
      IceAttemptStage.primaryRelay ||
      IceAttemptStage.backupRelay ||
      IceAttemptStage.experimentalRelay =>
        'Relay provider unavailable: $cleanReason',
      IceAttemptStage.fullRestart => 'Data channel did not open: $cleanReason',
    };
  }

  String _finalConnectFailure(String reason) {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      return 'All connection routes failed.';
    }
    if (cleanReason.contains('Relay credentials unavailable') ||
        cleanReason.contains('TURN broker') ||
        cleanReason.contains('Relay authorization')) {
      return cleanReason;
    }
    if (cleanReason == 'Direct path blocked.') {
      return 'Direct path blocked. Relay providers failed.';
    }
    if (cleanReason.contains('Relay provider')) {
      return '$cleanReason All connection routes failed.';
    }
    return cleanReason.endsWith('.')
        ? '$cleanReason All connection routes failed.'
        : '$cleanReason. All connection routes failed.';
  }

  bool _payloadMatchesCurrentAttempt(
    _ActiveSession active,
    SDPPayload payload,
  ) {
    final currentAttemptId = active.currentAttempt?.connectAttemptId;
    final payloadAttemptId = payload.connectAttemptId;
    if (currentAttemptId == null ||
        payloadAttemptId == null ||
        payloadAttemptId.isEmpty) {
      return true;
    }
    return currentAttemptId == payloadAttemptId;
  }

  bool _icePayloadMatchesCurrentAttempt(
    _ActiveSession active,
    IceCandidatePayload payload,
  ) {
    final currentAttemptId = active.currentAttempt?.connectAttemptId;
    final payloadAttemptId = payload.connectAttemptId;
    if (currentAttemptId == null) {
      return true;
    }
    if (payloadAttemptId == null || payloadAttemptId.isEmpty) {
      return false;
    }
    return currentAttemptId == payloadAttemptId;
  }

  IceAttemptDescriptor? _attemptFromPayload(
    _ActiveSession active,
    SDPPayload payload,
  ) {
    final stage = IceAttemptStageX.fromWireName(payload.iceStage);
    final attemptId = payload.connectAttemptId?.trim();
    if (stage == null || attemptId == null || attemptId.isEmpty) {
      return null;
    }
    final existing = active.attemptPlan?.matchingStage(stage, attemptId);
    if (existing != null) {
      return existing;
    }
    return IceAttemptDescriptor(
      stage: stage,
      policy:
          _icePolicyFromPayload(payload) ??
          (stage == IceAttemptStage.directStunOnly ||
                  stage == IceAttemptStage.fullRestart
              ? PeerIceTransportPolicy.all
              : PeerIceTransportPolicy.relayOnly),
      providerTier: _tierForStage(stage),
      providerId: stage.wireName,
      timeout: _timeoutForStage(stage),
      connectAttemptId: attemptId,
      attemptIndex: active.currentAttempt?.attemptIndex ?? 0,
    );
  }

  IceProviderTier _tierForStage(IceAttemptStage stage) {
    return switch (stage) {
      IceAttemptStage.directStunOnly => IceProviderTier.stunOnly,
      IceAttemptStage.primaryRelay => IceProviderTier.primaryRelay,
      IceAttemptStage.backupRelay ||
      IceAttemptStage.fullRestart => IceProviderTier.backupRelay,
      IceAttemptStage.experimentalRelay => IceProviderTier.experimentalRelay,
    };
  }

  Duration _timeoutForStage(IceAttemptStage stage) {
    return switch (stage) {
      IceAttemptStage.directStunOnly => const Duration(seconds: 12),
      IceAttemptStage.primaryRelay => const Duration(seconds: 30),
      IceAttemptStage.backupRelay ||
      IceAttemptStage.experimentalRelay => const Duration(seconds: 20),
      IceAttemptStage.fullRestart => const Duration(seconds: 25),
    };
  }

  void _handleIncomingOfferFailure(String peerId, Object error) {
    final active = _sessions[peerId];
    if (active == null) {
      return;
    }
    active.stopReconnecting();
    unawaited(_deleteRoomSilently(active));
    unawaited(active.disposePeerBindings());
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    _updateSession(
      peerId,
      active.snapshot.copyWith(
        state: SessionState.failed,
        phase: SessionPhase.failed,
        detail: 'Incoming peer offer failed.',
        updatedAt: updatedAt,
        error: _connectSetupFailureMessage(error),
        route: PeerConnectionRoute.unknown(updatedAt: updatedAt),
      ),
    );
  }

  Future<void> _deleteRoomSilently(_ActiveSession active) async {
    try {
      await adapter.deleteRoom(active.roomId);
    } catch (_) {
      // Room cleanup is best-effort; connection state still reports failure.
    }
  }
}

String _icePolicyPayload(PeerIceTransportPolicy policy) {
  return switch (policy) {
    PeerIceTransportPolicy.all => 'all',
    PeerIceTransportPolicy.relayOnly => 'relay',
  };
}

PeerIceTransportPolicy? _icePolicyFromPayload(SDPPayload payload) {
  return switch (payload.icePolicy?.trim().toLowerCase()) {
    'relay' || 'relayonly' => PeerIceTransportPolicy.relayOnly,
    'all' => PeerIceTransportPolicy.all,
    _ => null,
  };
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
  final Map<IceRole, StreamSubscription<IceCandidatePayload>> iceSubscriptions =
      <IceRole, StreamSubscription<IceCandidatePayload>>{};
  final List<RTCIceCandidate> remoteIceCache = <RTCIceCandidate>[];

  Session snapshot;
  bool bound = false;
  int retryAttempt = 0;
  bool usedCachedReconnect = false;
  bool shouldReconnect = true;
  bool reconnectInProgress = false;
  PeerIceTransportPolicy icePolicy = PeerIceTransportPolicy.all;
  IceAttemptPlan? attemptPlan;
  IceAttemptDescriptor? currentAttempt;
  int reconnectGeneration = 0;
  int? lastOfferTs;
  int? lastAnswerTs;
  StreamSubscription<SDPPayload>? answerSubscription;
  Timer? handshakeTimeoutTimer;
  Timer? reconnectTimer;
  int? connectStartedAt;

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
    final peerSubscriptions = List<StreamSubscription<dynamic>>.of(
      subscriptions,
    );
    subscriptions.clear();
    for (final subscription in peerSubscriptions) {
      await subscription.cancel();
    }
    final iceStreamSubscriptions =
        List<StreamSubscription<IceCandidatePayload>>.of(
          iceSubscriptions.values,
        );
    iceSubscriptions.clear();
    for (final subscription in iceStreamSubscriptions) {
      await subscription.cancel();
    }
  }

  void startHandshakeTimeout(
    Future<void> Function() onTimeout, {
    required Duration duration,
  }) {
    cancelHandshakeTimeout();
    handshakeTimeoutTimer = Timer(duration, () {
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

  void startAttemptPlan(IceAttemptPlan plan) {
    attemptPlan = plan;
    currentAttempt = plan.first;
    connectStartedAt = DateTime.now().millisecondsSinceEpoch;
    icePolicy = currentAttempt?.policy ?? PeerIceTransportPolicy.all;
    remoteIceCache.clear();
    lastOfferTs = null;
    lastAnswerTs = null;
  }
}
