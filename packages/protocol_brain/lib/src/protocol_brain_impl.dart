import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart';

import '../adapters/signaling_adapter.dart';
import '../adapters/signaling_cipher.dart';
import 'connection_memory.dart';
import 'session_manager.dart';

part 'active_session.dart';
part 'ice_candidate_policy.dart';
part 'session_retry_policy.dart';

class ProtocolBrainImpl implements ProtocolBrain {
  ProtocolBrainImpl({
    required this.selfUsername,
    required this.adapter,
    required this.peerConfig,
    required this.peerFactory,
    required this.connectionMemoryStore,
    this.peerConfigProvider,
    this.reconnectGrace = const Duration(seconds: 2),
  });

  final String selfUsername;
  final SignalingAdapter adapter;
  final PeerConfig peerConfig;
  final PeerCoreFactory peerFactory;
  final ConnectionMemoryStore connectionMemoryStore;
  final PeerConfigProvider? peerConfigProvider;
  final Duration reconnectGrace;

  final Map<String, _ActiveSession> _sessions = <String, _ActiveSession>{};
  final Map<String, StreamSubscription<SDPPayload>> _offerSubscriptions =
      <String, StreamSubscription<SDPPayload>>{};
  final Map<String, IncomingOfferGuard> _incomingOfferGuards =
      <String, IncomingOfferGuard>{};

  final StreamController<Session> _peerConnectedController =
      StreamController<Session>.broadcast();
  final StreamController<String> _peerDisconnectedController =
      StreamController<String>.broadcast();
  final StreamController<SessionMessage> _peerMessageController =
      StreamController<SessionMessage>.broadcast();
  final StreamController<SessionRemoteTrack> _remoteTrackController =
      StreamController<SessionRemoteTrack>.broadcast();
  final StreamController<Session> _sessionChangedController =
      StreamController<Session>.broadcast();
  final StreamController<IncomingOfferRejection>
  _incomingOfferRejectedController =
      StreamController<IncomingOfferRejection>.broadcast();

  @override
  Stream<Session> get onPeerConnected => _peerConnectedController.stream;

  @override
  Stream<String> get onPeerDisconnected => _peerDisconnectedController.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _peerMessageController.stream;

  @override
  Stream<SessionRemoteTrack> get onRemoteTrack => _remoteTrackController.stream;

  @override
  Stream<Session> get onSessionChanged => _sessionChangedController.stream;

  @override
  Stream<IncomingOfferRejection> get onIncomingOfferRejected =>
      _incomingOfferRejectedController.stream;

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
    final previousPolicy = active.icePolicy;
    active.icePolicy = PeerIceTransportPolicy.all;
    active.relayFallbackTried = false;
    active.directAttemptFailure = null;
    active.retryAttempt = 0;
    if (previousPolicy != PeerIceTransportPolicy.all ||
        active.peer.state != PeerState.ready ||
        active.snapshot.state == SessionState.failed) {
      await _recreatePeer(active, policy: PeerIceTransportPolicy.all);
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
  Future<void> recoverConnection(
    String peerId, {
    String reason = 'Network changed. Restarting peer connection.',
  }) async {
    final active = _sessions[peerId];
    if (active == null || !active.shouldReconnect) {
      return;
    }
    await _restartForNetworkChange(active, reason: reason);
  }

  @override
  Future<void> recoverConnections({
    String reason = 'Network changed. Restarting peer connections.',
  }) async {
    final activeSessions = _sessions.values.toList(growable: false);
    for (final active in activeSessions) {
      if (_sessions[active.peerId] != active || !active.shouldReconnect) {
        continue;
      }
      await _restartForNetworkChange(active, reason: reason);
    }
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
  Future<void> registerPeer(
    String peerId, {
    IncomingOfferGuard? incomingOfferGuard,
  }) async {
    if (incomingOfferGuard != null) {
      _incomingOfferGuards[peerId] = incomingOfferGuard;
    }
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
  Future<RTCSessionDescription> applyMediaOffer(
    String peerId,
    RTCSessionDescription offer,
  ) async {
    // Legacy connected-session media support. App calls use dedicated media
    // connections so chat/data peer lifecycle cannot dispose active call media.
    final active = _requireConnectedSession(peerId);
    _markPhase(
      active,
      SessionPhase.negotiatingMedia,
      'Applying voice media offer.',
      state: SessionState.connected,
    );
    final answer = await _runConnectedPeerOperation(
      active,
      'applying voice media offer',
      (PeerCore peer) => peer.applyMediaOffer(offer),
    );
    _markPhase(
      active,
      SessionPhase.connected,
      'Voice media negotiation answered.',
      state: SessionState.connected,
    );
    return answer;
  }

  @override
  Future<void> applyMediaAnswer(
    String peerId,
    RTCSessionDescription answer,
  ) async {
    // Legacy connected-session media support. App calls use dedicated media
    // connections so chat/data peer lifecycle cannot dispose active call media.
    final active = _requireConnectedSession(peerId);
    _markPhase(
      active,
      SessionPhase.negotiatingMedia,
      'Applying voice media answer.',
      state: SessionState.connected,
    );
    await _runConnectedPeerOperation(
      active,
      'applying voice media answer',
      (PeerCore peer) => peer.applyMediaAnswer(answer),
    );
    _markPhase(
      active,
      SessionPhase.connected,
      'Voice media negotiation complete.',
      state: SessionState.connected,
    );
  }

  @override
  Future<RTCSessionDescription> createMediaOffer(String peerId) async {
    // Legacy connected-session media support. App calls use dedicated media
    // connections so chat/data peer lifecycle cannot dispose active call media.
    final active = _requireConnectedSession(peerId);
    _markPhase(
      active,
      SessionPhase.negotiatingMedia,
      'Creating voice media offer.',
      state: SessionState.connected,
    );
    final offer = await _runConnectedPeerOperation(
      active,
      'creating voice media offer',
      (PeerCore peer) => peer.createMediaOffer(),
    );
    _markPhase(
      active,
      SessionPhase.connected,
      'Voice media offer created.',
      state: SessionState.connected,
    );
    return offer;
  }

  @override
  Future<void> setMicrophoneMuted(String peerId, {required bool muted}) async {
    final active = _requireConnectedSession(peerId);
    await _runConnectedPeerOperation(
      active,
      'muting voice media',
      (PeerCore peer) => peer.setMicrophoneMuted(muted: muted),
    );
  }

  @override
  Future<void> startLocalAudio(String peerId) async {
    final active = _requireConnectedSession(peerId);
    await _runConnectedPeerOperation(
      active,
      'starting local voice media',
      (PeerCore peer) => peer.startLocalAudio(),
    );
  }

  @override
  Future<void> stopLocalAudio(String peerId) async {
    final active = _sessions[peerId];
    if (active == null) {
      return;
    }
    await active.runPeerOperation(() async {
      if (_sessions[peerId] != active) {
        return;
      }
      await active.peer.stopLocalAudio();
    });
  }

  @override
  Future<VoiceMediaConnection> createVoiceMediaConnection(String peerId) async {
    final active = _sessions[peerId];
    final policy = active?.icePolicy ?? PeerIceTransportPolicy.all;
    final config = peerConfigProvider == null
        ? peerConfig.copyWith(iceTransportPolicy: policy)
        : await peerConfigProvider!(policy);
    return DefaultVoiceMediaConnection(
      config: config.copyWith(iceTransportPolicy: policy),
    );
  }

  @override
  Future<CallMediaConnection> createCallMediaConnection(String peerId) async {
    final active = _sessions[peerId];
    final policy = active?.icePolicy ?? PeerIceTransportPolicy.all;
    final config = peerConfigProvider == null
        ? peerConfig.copyWith(iceTransportPolicy: policy)
        : await peerConfigProvider!(policy);
    return DefaultCallMediaConnection(
      config: config.copyWith(iceTransportPolicy: policy),
    );
  }

  @override
  Future<void> unregisterPeer(String peerId) async {
    _incomingOfferGuards.remove(peerId);
    await _offerSubscriptions.remove(peerId)?.cancel();
  }

  _ActiveSession _requireConnectedSession(String peerId) {
    final active = _sessions[peerId];
    if (active == null) {
      throw StateError('No active session for $peerId');
    }
    if (active.snapshot.state != SessionState.connected ||
        active.peer.state != PeerState.connected) {
      throw StateError('Peer $peerId is not connected.');
    }
    return active;
  }

  Future<T> _runConnectedPeerOperation<T>(
    _ActiveSession active,
    String operation,
    Future<T> Function(PeerCore peer) action,
  ) {
    return active.runPeerOperation(() async {
      _ensureCurrentConnectedPeer(active, operation);
      final peer = active.peer;
      final generation = active.peerGeneration;
      final result = await action(peer);
      _ensureCurrentConnectedPeer(
        active,
        operation,
        peer: peer,
        generation: generation,
      );
      return result;
    });
  }

  void _ensureCurrentConnectedPeer(
    _ActiveSession active,
    String operation, {
    PeerCore? peer,
    int? generation,
  }) {
    if (_sessions[active.peerId] != active || !active.shouldReconnect) {
      throw StateError('Peer ${active.peerId} is no longer active.');
    }
    if ((peer != null && !identical(active.peer, peer)) ||
        (generation != null && active.peerGeneration != generation)) {
      throw StateError('Peer connection changed while $operation.');
    }
    if (active.snapshot.state != SessionState.connected ||
        active.peer.state != PeerState.connected) {
      throw StateError('Peer ${active.peerId} is not connected.');
    }
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
      active.peer.onRemoteTrack.listen((PeerRemoteTrack event) {
        _remoteTrackController.add(
          SessionRemoteTrack.fromPeerTrack(active.peerId, event),
        );
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
            if (active.icePolicy == PeerIceTransportPolicy.all &&
                !active.relayFallbackTried) {
              unawaited(_tryRelayFallback(active, 'Direct path failed.'));
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
            unawaited(_handlePeerClosed(active));
            break;
          case PeerState.ready:
          case PeerState.connected:
            break;
        }
      }),
    );
  }

  Future<void> _handlePeerClosed(_ActiveSession active) async {
    if (_sessions[active.peerId] != active || !active.shouldReconnect) {
      return;
    }
    active.stopReconnecting();
    _sessions.remove(active.peerId);
    await _deleteRoomSilently(active);
    await active.dispose();
    _peerDisconnectedController.add(active.peerId);
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
    if (!_offerSubscriptions.containsKey(peerId)) {
      return;
    }
    final decision = await _authorizeIncomingOffer(peerId);
    if (!_offerSubscriptions.containsKey(peerId)) {
      return;
    }
    if (!decision.allowed) {
      _incomingOfferRejectedController.add(
        IncomingOfferRejection(
          peerId: peerId,
          reason: decision.reason ?? 'Incoming offer rejected by local policy.',
          rejectedAt: DateTime.now(),
          offerTimestamp: offer.ts,
        ),
      );
      return;
    }

    final active = await _ensureSession(peerId);
    final alreadyConnected =
        active.snapshot.state == SessionState.connected ||
        active.peer.state == PeerState.connected;
    if (alreadyConnected && !offer.restart) {
      return;
    }
    if (active.lastOfferTs != null && offer.ts <= active.lastOfferTs!) {
      return;
    }
    active.lastOfferTs = offer.ts;
    if (offer.restart) {
      active.cancelPendingReconnect();
      active.cancelHandshakeTimeout();
      active.reconnectInProgress = false;
      active.relayFallbackTried = false;
      active.directAttemptFailure = null;
      active.usedCachedReconnect = false;
      active.retryAttempt = 0;
      active.icePolicy = PeerIceTransportPolicy.all;
    }
    if (active.peer.state != PeerState.ready || offer.restart) {
      await _recreatePeer(
        active,
        policy: offer.restart ? PeerIceTransportPolicy.all : null,
      );
    }
    await _bindPeerCore(active, IceRole.callee);
    active.remoteIceCache.clear();
    _markPhase(
      active,
      SessionPhase.writingAnswer,
      offer.restart
          ? 'Received ICE restart offer. Creating answer.'
          : 'Received offer. Creating answer.',
      state: offer.restart
          ? SessionState.reconnecting
          : SessionState.connecting,
    );
    active.startHandshakeTimeout(
      () => _handleHandshakeTimeout(active.peerId),
      duration: _handshakeTimeoutFor(active),
    );

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

  Future<IncomingOfferDecision> _authorizeIncomingOffer(String peerId) async {
    final guard = _incomingOfferGuards[peerId];
    if (guard == null) {
      return const IncomingOfferDecision.allow();
    }
    try {
      return await guard(peerId);
    } catch (_) {
      return const IncomingOfferDecision.deny(
        'Incoming offer rejected by local policy.',
      );
    }
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
    bool isRestart = false,
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
      isRestart
          ? 'Creating ICE restart offer.'
          : isRetry
          ? 'Creating retry offer.'
          : 'Creating signaling offer.',
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
        restart: isRestart,
      ),
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

  Future<void> _restartForNetworkChange(
    _ActiveSession active, {
    required String reason,
  }) async {
    if (_sessions[active.peerId] != active ||
        !active.shouldReconnect ||
        active.reconnectInProgress) {
      return;
    }
    if (active.snapshot.state == SessionState.failed) {
      return;
    }
    if (active.snapshot.state == SessionState.connected &&
        active.peer.state == PeerState.connected) {
      active.cancelPendingReconnect();
      unawaited(_refreshRoute(active));
      return;
    }

    active.cancelPendingReconnect();
    active.cancelHandshakeTimeout();
    active.reconnectInProgress = true;
    active.relayFallbackTried = false;
    active.directAttemptFailure = null;
    active.usedCachedReconnect = false;
    active.retryAttempt = 0;
    final generation = active.nextReconnectGeneration();

    _markPhase(
      active,
      SessionPhase.reconnecting,
      reason,
      state: SessionState.reconnecting,
    );

    try {
      final recreated = await _recreatePeer(
        active,
        shouldContinue: () => _canContinueNetworkRestart(active, generation),
        restoreRole: _localRoleFor(active.peerId),
        policy: PeerIceTransportPolicy.all,
      );
      if (!recreated || !_canContinueNetworkRestart(active, generation)) {
        return;
      }
      if (_isOfferOwner(active.peerId)) {
        await _startOffer(active, isRetry: true, isRestart: true);
      } else {
        await _waitForOffer(active, isRetry: true);
      }
    } catch (error) {
      if (_sessions[active.peerId] != active ||
          active.reconnectGeneration != generation) {
        return;
      }
      _updateSession(
        active.peerId,
        active.snapshot.copyWith(
          state: SessionState.failed,
          phase: SessionPhase.failed,
          detail: 'Network recovery failed.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          error:
              'Network recovery failed: ${_connectSetupFailureMessage(error)}',
          route: PeerConnectionRoute.unknown(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
    } finally {
      if (_sessions[active.peerId] == active &&
          active.reconnectGeneration == generation) {
        active.reconnectInProgress = false;
      }
    }
  }

  bool _canContinueNetworkRestart(_ActiveSession active, int generation) {
    return _sessions[active.peerId] == active &&
        active.shouldReconnect &&
        active.reconnectGeneration == generation &&
        active.snapshot.state != SessionState.failed;
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

  Future<PeerCore> _newPeer({
    PeerIceTransportPolicy policy = PeerIceTransportPolicy.all,
  }) async {
    final peer = peerFactory();
    final config = peerConfigProvider == null
        ? peerConfig.copyWith(iceTransportPolicy: policy)
        : await peerConfigProvider!(policy);
    await peer.init(config.copyWith(iceTransportPolicy: policy));
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
  }) {
    return active.runPeerOperation(
      () => _recreatePeerLocked(
        active,
        shouldContinue: shouldContinue,
        restoreRole: restoreRole,
        policy: policy,
      ),
    );
  }

  Future<bool> _recreatePeerLocked(
    _ActiveSession active, {
    bool Function()? shouldContinue,
    IceRole? restoreRole,
    PeerIceTransportPolicy? policy,
  }) async {
    if (shouldContinue != null && !shouldContinue()) {
      return false;
    }
    await active.disposePeerBindings();
    active.peerGeneration += 1;
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
    final nextPolicy = policy ?? active.icePolicy;
    active.peer = await _newPeer(policy: nextPolicy);
    active.icePolicy = nextPolicy;
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
      PeerRouteKind.direct =>
        'Direct encrypted peer lane is open${_addressFamilyDetail(route)}.',
      PeerRouteKind.relay =>
        'Encrypted peer lane is relayed through TURN${_addressFamilyDetail(route)}.',
      PeerRouteKind.unknown => 'Detecting route...',
    };
  }

  String _addressFamilyDetail(PeerConnectionRoute route) {
    return switch (route.addressFamily) {
      PeerAddressFamily.ipv4 => ' over IPv4',
      PeerAddressFamily.ipv6 => ' over IPv6',
      PeerAddressFamily.mixed => ' across mixed IP families',
      PeerAddressFamily.unknown => '',
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
    if (await _tryRelayFallback(active, 'Direct path timed out.')) {
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
    return active.icePolicy == PeerIceTransportPolicy.relayOnly
        ? _relayHandshakeTimeout
        : _directHandshakeTimeout;
  }

  Future<bool> _tryRelayFallback(
    _ActiveSession active,
    String directFailure,
  ) async {
    if (_sessions[active.peerId] != active ||
        !active.shouldReconnect ||
        active.icePolicy != PeerIceTransportPolicy.all ||
        active.relayFallbackTried) {
      return false;
    }

    active.relayFallbackTried = true;
    active.directAttemptFailure = directFailure;

    final hasRelay = await _hasRelayFallbackConfig();
    if (!hasRelay) {
      _updateSession(
        active.peerId,
        active.snapshot.copyWith(
          state: SessionState.failed,
          phase: SessionPhase.failed,
          detail: 'Direct path blocked. Relay fallback unavailable.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          error:
              'Direct path blocked. No TURN relay is configured for this build.',
          route: PeerConnectionRoute.unknown(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      return false;
    }

    active.cancelPendingReconnect();
    active.cancelHandshakeTimeout();
    active.retryAttempt = 0;
    _markPhase(
      active,
      SessionPhase.reconnecting,
      'Direct path blocked. Trying TURN relay fallback.',
      state: SessionState.reconnecting,
      error: directFailure,
    );
    final recreated = await _recreatePeer(
      active,
      policy: PeerIceTransportPolicy.relayOnly,
    );
    if (!recreated || _sessions[active.peerId] != active) {
      return false;
    }
    try {
      if (_isOfferOwner(active.peerId)) {
        await _startOffer(active, isRetry: true);
      } else {
        await _waitForOffer(active, isRetry: true);
      }
      return true;
    } catch (error) {
      _updateSession(
        active.peerId,
        active.snapshot.copyWith(
          state: SessionState.failed,
          phase: SessionPhase.failed,
          detail: 'Direct path blocked. Relay fallback failed.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          error:
              'Direct path blocked. Relay fallback failed: ${_connectSetupFailureMessage(error)}',
          route: PeerConnectionRoute.unknown(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
      return false;
    }
  }

  Future<bool> _hasRelayFallbackConfig() async {
    try {
      final config = peerConfigProvider == null
          ? peerConfig.copyWith(
              iceTransportPolicy: PeerIceTransportPolicy.relayOnly,
            )
          : await peerConfigProvider!(PeerIceTransportPolicy.relayOnly);
      return config.hasRelayServer;
    } catch (_) {
      return false;
    }
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
