part of 'rain_runtime_controller.dart';

enum _IncomingVoiceInviteDisposition { accept, busy, ignore }

final class _TerminalRoomWriteResult {
  const _TerminalRoomWriteResult._({required this.durable, this.error});

  const _TerminalRoomWriteResult.durable() : this._(durable: true);

  const _TerminalRoomWriteResult.failed(Object? error)
    : this._(durable: false, error: error);

  final bool durable;
  final Object? error;
}

extension VoiceCallRuntime on RainRuntimeController {
  static const CallTerminalWritePolicy _voiceTerminalWritePolicy =
      CallTerminalWritePolicy();
  static const String _voiceCallFailedReasonCode =
      CallErrorClassifier.failedReasonCode;
  static const String _voiceCallBusyReasonCode =
      CallErrorClassifier.busyReasonCode;
  static const String _voiceCallRejectedReasonCode =
      CallErrorClassifier.rejectedReasonCode;
  static const String _voiceCallVideoRendererFailedReasonCode =
      CallErrorClassifier.videoRendererFailedReasonCode;
  static const String _voiceCallCameraDeniedReasonCode =
      CallErrorClassifier.cameraDeniedReasonCode;
  static const String _voiceCallRemoteCameraPermissionRequired =
      CallErrorClassifier.remoteCameraPermissionRequired;
  static const String _voiceCallFileTransferRequired =
      CallErrorClassifier.fileTransferRequired;
  static const String _voiceCallNetworkLost =
      CallErrorClassifier.networkLostMessage;
  static const String _voiceCallSignalingFailed =
      CallErrorClassifier.signalingFailedMessage;
  static const String _voiceCallMediaFailed =
      CallErrorClassifier.mediaFailedMessage;
  static const String _voiceCallRelayUnavailable =
      CallErrorClassifier.relayUnavailableMessage;
  static const String _voiceCallVideoFailed =
      CallErrorClassifier.videoFailedMessage;
  static const String _voiceCallVideoBackgrounded =
      CallErrorClassifier.videoBackgroundedMessage;
  static const String _voiceCallAudioRouteUnavailable =
      CallErrorClassifier.audioRouteUnavailableMessage;
  static const String _voiceCallReconnecting =
      CallErrorClassifier.reconnectingMessage;
  static const Duration _voiceCallExpiry = Duration(minutes: 2);
  static const Duration _voiceCallTransientCreateRetryDelay = Duration(
    milliseconds: 300,
  );
  static const Duration _voiceCallCleanupStepTimeout = Duration(seconds: 2);

  Future<void> startVoiceCall(String username) async {
    await _startCall(username, mediaMode: CallMediaMode.audio);
  }

  Future<void> startVideoCall(String username) async {
    await _startCall(username, mediaMode: CallMediaMode.video);
  }

  Future<void> _startCall(
    String username, {
    required CallMediaMode mediaMode,
  }) async {
    final peerId = _normalizedUsername(username);
    _recordRuntimeEvent(
      category: 'call',
      name: 'start_requested',
      context: <String, Object?>{'peerId': peerId, 'mediaMode': mediaMode.name},
    );
    _assertVoiceCallCanStart();
    final presence = await _fetchVoiceCallPeerPresence(
      peerId,
      mediaMode: mediaMode,
    );
    await _assertVoiceCallPeerIsFriend(peerId);
    final activeTransfer = await _firstActiveTransfer();
    await _clearExpiredVoiceCallStartBlock();

    final decision = RuntimeInteractionGuard.canStartCall(
      peerId: peerId,
      mediaMode: mediaMode,
      voiceCallState: _voiceCallStartPreflightState(),
      peerOnline: presence.peerOnline,
      activeTransfer: activeTransfer,
      manualDisconnectedPeers: _manualDisconnectedPeers,
      diagnostics: presence.diagnostics,
    );
    if (!decision.allowed) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'start_blocked',
        severity: 'warning',
        message: decision.userMessage,
        context: <String, Object?>{
          'peerId': peerId,
          'mediaMode': mediaMode.name,
          'reasonCode': decision.decision.name,
          'blockingPeerId': decision.blockingPeerId,
          ...decision.diagnostics,
        },
      );
    }
    decision.throwIfDenied();
    _requireVoiceSignalingAdapter();
    final callId = _newVoiceCallId(peerId);
    final sessionEpoch = DateTime.now().millisecondsSinceEpoch;
    _recordRuntimeEvent(
      category: 'call',
      name: 'created',
      context: <String, Object?>{
        'peerId': peerId,
        'callId': callId,
        'sessionEpoch': sessionEpoch,
        'mediaMode': mediaMode.name,
        'isOutgoing': true,
      },
    );
    _setVoiceCallState(
      VoiceCallState(
        phase: VoiceCallPhase.connectingMedia,
        peerId: peerId,
        callId: callId,
        sessionEpoch: sessionEpoch,
        mediaMode: mediaMode,
        isOutgoing: true,
        updatedAt: sessionEpoch,
        detail: _voiceCallPreflightDetail(mediaMode),
      ),
    );

    try {
      final session = await _createVoiceCallSession(
        peerId: peerId,
        callId: callId,
        sessionEpoch: sessionEpoch,
        isOutgoing: true,
        mediaMode: mediaMode,
      );
      await session.startOutgoing();
      await _watchFirebaseVoiceCall(
        session: session,
        peerId: peerId,
        isOutgoing: true,
      );
    } catch (error) {
      if (error is TurnUnavailableException) {
        _recordRuntimeEvent(
          category: 'call',
          name: 'turn_unavailable_call_blocked',
          severity: 'error',
          message: _voiceCallRelayUnavailable,
          context: <String, Object?>{
            'peerId': peerId,
            'callId': callId,
            'sessionEpoch': sessionEpoch,
            'mediaMode': mediaMode.name,
            'readiness': error.readiness.readiness.name,
            'hasRelayServer': error.readiness.hasRelayServer,
            if (error.readiness.error != null)
              'readinessError': error.readiness.error.toString(),
          },
        );
      }
      final retrySnapshot = _voiceCallSignalingFailureSnapshotForError(
        error,
        peerId: peerId,
      );
      final retryDecision = retrySnapshot == null
          ? null
          : CallRetryPolicy.classifySignalingFailure(retrySnapshot);
      _recordRuntimeEvent(
        category: 'call',
        name: 'start_failed',
        severity: 'error',
        message: retryDecision?.userMessage ?? error.toString(),
        context: <String, Object?>{
          'peerId': peerId,
          'callId': callId,
          'sessionEpoch': sessionEpoch,
          'mediaMode': mediaMode.name,
          if (retryDecision != null)
            'retryDecisionKind': retryDecision.kind.name,
          if (retryDecision != null)
            'canRetryImmediately': retryDecision.canRetryImmediately,
        },
      );
      _recordVoiceCallStartFailureDiagnostics(
        error: error,
        peerId: peerId,
        callId: callId,
        sessionEpoch: sessionEpoch,
        mediaMode: mediaMode,
        retryDecision: retryDecision,
        retrySnapshot: retrySnapshot,
      );
      await _failVoiceCall(
        error,
        failureReason:
            _voiceCallFailureReasonForRetryDecision(retryDecision) ??
            _voiceCallFailureReasonForError(error) ??
            _localAudioFailureReason(error),
        detail:
            _voiceCallFailureDetailForRetryDecision(retryDecision) ??
            _voiceCallFailureDetailForError(error) ??
            _localAudioFailureDetail(error),
      );
      rethrow;
    }
  }

  Future<void> _clearExpiredVoiceCallStartBlock() async {
    final current = _voiceCallState;
    if (!await _isExpiredVoiceCallStartBlock(current)) {
      return;
    }
    _recordRuntimeEvent(
      category: 'call',
      name: 'expired_call_state_cleared_before_start',
      severity: 'warning',
      message: 'Expired local call state was cleared before starting a call.',
      context: _voiceCallEventContext(current),
    );
    await _disposeCurrentVoiceCallSession();
    if (_voiceCallState.callId == current.callId &&
        _voiceCallState.sessionEpoch == current.sessionEpoch) {
      _setVoiceCallState(const VoiceCallState.idle());
    }
  }

  VoiceCallState _voiceCallStartPreflightState() {
    return VoiceCallStateCoordinator.instance.startPreflightState(
      _voiceCallState,
      expiry: _voiceCallExpiry,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<bool> _isExpiredVoiceCallStartBlock(VoiceCallState state) async {
    if (!_canClearExpiredVoiceCallStartBlock(state.phase)) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final callId = state.callId;
    final voiceAdapter = voiceSignalingAdapter;
    if (callId != null && voiceAdapter != null) {
      try {
        final room = await voiceAdapter.fetchCall(callId);
        if (room == null || room.status.isTerminal) {
          return true;
        }
        if (room.createdAt != state.sessionEpoch) {
          return true;
        }
        return room.expiresAt <= now;
      } catch (_) {
        return false;
      }
    }
    final sessionEpoch = state.sessionEpoch;
    return sessionEpoch != null &&
        now >= sessionEpoch + _voiceCallExpiry.inMilliseconds;
  }

  bool _canClearExpiredVoiceCallStartBlock(VoiceCallPhase phase) {
    return VoiceCallStateCoordinator.instance.canClearExpiredStartBlock(phase);
  }

  Future<void> acceptVoiceCall() async {
    final current = _voiceCallState;
    _recordRuntimeEvent(
      category: 'call',
      name: 'accept_requested',
      context: _voiceCallEventContext(current),
    );
    if (current.callId != null && _acceptingVoiceCallId == current.callId) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'accept_duplicate_ignored',
        severity: 'info',
        message: 'Duplicate incoming call accept ignored.',
        context: _voiceCallEventContext(current),
      );
      return;
    }
    if (current.phase != VoiceCallPhase.incomingRinging ||
        current.peerId == null ||
        current.callId == null) {
      throw StateError('There is no incoming call to accept.');
    }
    final acceptDecision = RuntimeInteractionGuard.canAcceptCall(
      peerId: current.peerId!,
      callId: current.callId!,
      voiceCallState: current,
      activeTransfer: await _firstActiveTransfer(),
    );
    if (!acceptDecision.allowed &&
        acceptDecision.reasonCode ==
            RuntimeInteractionReasonCode.activeFileTransfer) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'accept_blocked',
        severity: 'warning',
        message: acceptDecision.userMessage,
        context: <String, Object?>{
          ..._voiceCallEventContext(current),
          'reasonCode': acceptDecision.reasonCode.name,
          'blockingPeerId': acceptDecision.blockingPeerId,
          'transferId': acceptDecision.transferId,
        },
      );
      await _sendVoiceFrame(
        current.peerId!,
        VoiceCallFrameType.busy,
        callId: current.callId!,
        sessionEpoch: _voiceCallSession?.sessionEpoch,
        reason: _voiceCallFileTransferRequired,
        reasonCode: _voiceCallBusyReasonCode,
        bestEffort: true,
      );
      await _failVoiceCall(
        acceptDecision.userMessage ?? _voiceCallFileTransferRequired,
        failureReason: VoiceCallFailureReason.fileTransferActive,
        detail: acceptDecision.userMessage ?? _voiceCallFileTransferRequired,
      );
      return;
    }
    if (!acceptDecision.allowed) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'accept_blocked',
        severity: 'warning',
        message: acceptDecision.userMessage,
        context: <String, Object?>{
          ..._voiceCallEventContext(current),
          'reasonCode': acceptDecision.reasonCode.name,
          'blockingPeerId': acceptDecision.blockingPeerId,
          'transferId': acceptDecision.transferId,
        },
      );
    }
    acceptDecision.throwIfDenied();

    final session = _voiceCallSession;
    if (session == null || session.callId != current.callId) {
      await _failVoiceCall('Voice call session is unavailable.');
      throw StateError('Voice call session is unavailable.');
    }

    _acceptingVoiceCallId = current.callId!;
    try {
      await session.acceptIncoming();
      _acceptingVoiceCallId = null;
    } catch (error) {
      if (_acceptingVoiceCallId == current.callId) {
        _acceptingVoiceCallId = null;
      }
      _recordRuntimeEvent(
        category: 'call',
        name: 'accept_failed',
        severity: 'error',
        message: error.toString(),
        context: _voiceCallEventContext(current),
      );
      await _failVoiceCall(
        error,
        failureReason:
            _voiceCallFailureReasonForError(error) ??
            _localAudioFailureReason(error),
        detail:
            _voiceCallFailureDetailForError(error) ??
            _localAudioFailureDetail(error),
      );
      rethrow;
    }
  }

  Future<void> rejectVoiceCall() async {
    final current = _voiceCallState;
    _recordRuntimeEvent(
      category: 'call',
      name: 'reject_requested',
      context: _voiceCallEventContext(current),
    );
    if (current.phase != VoiceCallPhase.incomingRinging ||
        current.peerId == null ||
        current.callId == null) {
      return;
    }
    final session = _voiceCallSession;
    if (session != null && session.callId == current.callId) {
      await session.rejectIncoming(reason: 'Rejected.');
      return;
    }
    await _sendVoiceFrame(
      current.peerId!,
      VoiceCallFrameType.reject,
      callId: current.callId!,
      reason: 'Rejected.',
      reasonCode: _voiceCallRejectedReasonCode,
      bestEffort: true,
    );
    _setVoiceCallState(const VoiceCallState.idle());
  }

  Future<void> hangUpVoiceCall() async {
    final current = _voiceCallState;
    _recordRuntimeEvent(
      category: 'call',
      name: 'hangup_requested',
      context: _voiceCallEventContext(current),
    );
    if (!current.hasCall || current.peerId == null || current.callId == null) {
      return;
    }
    await _endVoiceCallForPeer(
      current.peerId!,
      notifyPeer: true,
      detail: 'Call ended.',
    );
  }

  Future<void> dismissFailedVoiceCall() async {
    final current = _voiceCallState;
    _recordRuntimeEvent(
      category: 'call',
      name: 'failed_call_dismiss_requested',
      context: _voiceCallEventContext(current),
    );
    if (current.phase != VoiceCallPhase.failed) {
      return;
    }
    await _disposeCurrentVoiceCallSession();
    final latest = _voiceCallState;
    if (latest.callId == current.callId &&
        latest.sessionEpoch == current.sessionEpoch &&
        latest.phase == VoiceCallPhase.failed) {
      _setVoiceCallState(const VoiceCallState.idle());
    }
  }

  Future<void> setVoiceCallMuted(bool muted) async {
    final current = _voiceCallState;
    _recordRuntimeEvent(
      category: 'call',
      name: 'mute_requested',
      context: <String, Object?>{
        ..._voiceCallEventContext(current),
        'muted': muted,
      },
    );
    final session = _voiceCallSession;
    if (!current.isActive ||
        current.peerId == null ||
        current.callId == null ||
        session == null) {
      throw StateError('There is no active call to mute.');
    }
    await session.setMuted(muted: muted);
    if (!_isCurrentVoiceCall(
      current.peerId!,
      current.callId!,
      sessionEpoch: current.sessionEpoch,
    )) {
      return;
    }
    _setVoiceCallState(
      _voiceCallState.copyWith(
        isMuted: muted,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> setVoiceCallDeafened(bool deafened) async {
    final current = _voiceCallState;
    _recordRuntimeEvent(
      category: 'call',
      name: 'deafen_requested',
      context: <String, Object?>{
        ..._voiceCallEventContext(current),
        'deafened': deafened,
      },
    );
    final session = _voiceCallSession;
    if (!current.isActive ||
        current.peerId == null ||
        current.callId == null ||
        session == null) {
      throw StateError('There is no active call to deafen.');
    }
    await session.setDeafened(deafened: deafened);
    if (!_isCurrentVoiceCall(
      current.peerId!,
      current.callId!,
      sessionEpoch: current.sessionEpoch,
    )) {
      return;
    }
    _setVoiceCallState(
      _voiceCallState.copyWith(
        isDeafened: deafened,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> setVoiceCallOutputRoute(VoiceCallOutputRoute route) async {
    await setVoiceCallOutputTarget(switch (route) {
      VoiceCallOutputRoute.systemDefault =>
        const CallAudioOutputTarget.systemDefault(),
      VoiceCallOutputRoute.speaker =>
        const CallAudioOutputTarget.androidSpeakerphone(),
      VoiceCallOutputRoute.bluetooth => const CallAudioOutputTarget.bluetooth(),
    }, label: null);
  }

  Future<void> setVoiceCallOutputTarget(
    CallAudioOutputTarget target, {
    required String? label,
  }) async {
    final current = _voiceCallState;
    _recordRuntimeEvent(
      category: 'call',
      name: 'output_route_requested',
      context: <String, Object?>{
        ..._voiceCallEventContext(current),
        'route': target.route.name,
        'target': target.kind.name,
        if (target.deviceId != null) 'deviceId': target.deviceId,
      },
    );
    final session = _voiceCallSession;
    if (!current.isActive ||
        current.peerId == null ||
        current.callId == null ||
        session == null) {
      throw StateError('There is no active call to route audio.');
    }
    try {
      if (target.isDeviceBacked) {
        await session.selectAudioOutputDevice(target.deviceId!);
      } else {
        await session.setAudioOutputRoute(_voiceMediaOutputRoute(target.route));
      }
      if (!_isCurrentVoiceCall(
        current.peerId!,
        current.callId!,
        sessionEpoch: current.sessionEpoch,
      )) {
        return;
      }
      _setVoiceCallState(
        _voiceCallState.copyWith(
          outputRoute: target.route,
          outputRouteDeviceId: target.isDeviceBacked ? target.deviceId : null,
          outputRouteLabel: label,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          clearOutputRouteWarning: true,
          clearOutputRouteTarget: !target.isDeviceBacked,
        ),
      );
    } catch (error, stackTrace) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'output_route_failed',
        severity: 'warning',
        message: error.toString(),
        context: <String, Object?>{
          ..._voiceCallEventContext(current),
          'route': target.route.name,
          'target': target.kind.name,
          if (target.deviceId != null) 'deviceId': target.deviceId,
        },
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'voice-call-audio-route',
        fatal: false,
      );
      if (!_isCurrentVoiceCall(
        current.peerId!,
        current.callId!,
        sessionEpoch: current.sessionEpoch,
      )) {
        return;
      }
      _setVoiceCallState(
        _voiceCallState.copyWith(
          outputRouteWarning: _voiceCallAudioRouteUnavailable,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  Future<void> setVideoCallCameraMuted(bool muted) async {
    final current = _voiceCallState;
    _recordRuntimeEvent(
      category: 'call',
      name: 'camera_mute_requested',
      context: <String, Object?>{
        ..._voiceCallEventContext(current),
        'cameraMuted': muted,
      },
    );
    final session = _voiceCallSession;
    final media = _videoCallMediaConnection;
    if (!current.isActive ||
        !current.isVideo ||
        current.peerId == null ||
        current.callId == null ||
        session == null ||
        media == null) {
      throw StateError('There is no active video call to mute camera.');
    }
    await media.setCameraMuted(muted: muted);
    await session.setCameraMuted(muted: muted);
    if (!_isCurrentVoiceCall(
      current.peerId!,
      current.callId!,
      sessionEpoch: current.sessionEpoch,
    )) {
      return;
    }
    _setVoiceCallState(
      _voiceCallState.copyWith(
        isCameraMuted: muted,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    unawaited(_setVideoCallCameraMutedInSignaling(muted));
  }

  Future<void> switchVideoCallCamera() async {
    final current = _voiceCallState;
    _recordRuntimeEvent(
      category: 'call',
      name: 'camera_switch_requested',
      context: _voiceCallEventContext(current),
    );
    final media = _videoCallMediaConnection;
    if (!current.isActive ||
        !current.isVideo ||
        current.peerId == null ||
        current.callId == null ||
        media == null) {
      throw StateError('There is no active video call to switch camera.');
    }
    await media.switchCamera();
  }

  bool voiceCallBlocksFileTransfer(String peerId) {
    return _voiceCallState.blocksFileTransfersFor(_normalizedUsername(peerId));
  }

  Future<void> _handleIncomingVoiceCallEntry(VoiceCallInboxEntry entry) async {
    _recordRuntimeEvent(
      category: 'call',
      name: 'incoming_inbox_entry',
      context: <String, Object?>{
        'peerId': _normalizedUsername(entry.from),
        'callId': entry.callId,
        'status': entry.status.name,
        'createdAt': entry.createdAt,
        'expiresAt': entry.expiresAt,
      },
    );
    if (entry.status != VoiceCallSignalingStatus.ringing) {
      return;
    }
    final peerId = _normalizedUsername(entry.from);
    final localUsername = _normalizedUsername(selfIdentity.username);
    if (_normalizedUsername(entry.to) != localUsername ||
        peerId == localUsername) {
      return;
    }
    final voiceAdapter = _requireVoiceSignalingAdapter();
    final room = await voiceAdapter.fetchCall(entry.callId);
    if (room == null ||
        room.status != VoiceCallSignalingStatus.ringing ||
        room.createdAt != entry.createdAt ||
        room.expiresAt != entry.expiresAt ||
        room.pairId != entry.pairId ||
        _normalizedUsername(room.caller) != peerId ||
        _normalizedUsername(room.callee) != localUsername) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'incoming_inbox_entry_ignored',
        context: <String, Object?>{
          'peerId': peerId,
          'callId': entry.callId,
          'reason': room == null ? 'missingRoom' : 'roomMismatch',
          'roomStatus': room?.status.name,
        },
      );
      return;
    }

    final invite = VoiceCallFrame(
      type: VoiceCallFrameType.invite,
      callId: room.callId,
      from: room.caller,
      to: room.callee,
      sentAt: room.createdAt,
      seq: 1,
      sessionEpoch: room.createdAt,
      mediaMode: room.mediaMode,
    );
    await _handleFirebaseVoiceInvite(peerId, invite, room: room);
  }

  Future<void> _handleVoiceCallFrame(
    String peerId,
    VoiceCallFrame frame,
  ) async {
    _recordRuntimeEvent(
      category: 'call',
      name: 'control_frame_received',
      context: _voiceFrameEventContext(peerId, frame),
    );
    // Legacy control-channel voice signaling is permanently frozen.
    errorRecorder?.call(
      StateError(
        'Ignored legacy control-channel voice frame: '
        '${frame.type.name} ${frame.callId}',
      ),
      StackTrace.current,
      source: 'voice-call-legacy-control',
      fatal: false,
    );
    return;
  }

  // ignore: unused_element
  Future<void> _handleVoiceInviteLegacy(
    String peerId,
    VoiceCallFrame frame,
  ) async {
    final normalizedPeerId = _normalizedUsername(peerId);
    if (_normalizedUsername(frame.from) != normalizedPeerId ||
        _normalizedUsername(frame.to) !=
            _normalizedUsername(selfIdentity.username)) {
      return;
    }

    if (frame.type == VoiceCallFrameType.invite) {
      await _handleVoiceInvite(normalizedPeerId, frame);
      return;
    }

    if (!_isCurrentVoiceCall(
      normalizedPeerId,
      frame.callId,
      sessionEpoch: frame.sessionEpoch,
    )) {
      return;
    }

    final session = _voiceCallSession;
    if (session == null) {
      return;
    }

    switch (frame.type) {
      case VoiceCallFrameType.invite:
        break;
      case VoiceCallFrameType.reject:
      case VoiceCallFrameType.busy:
        await session.handleFrame(frame);
        if (_isRemoteMediaPermissionCode(frame.reasonCode)) {
          _setVoiceCallState(
            _voiceCallState.copyWith(
              phase: VoiceCallPhase.failed,
              detail: _remoteMediaPermissionDetail(frame.reasonCode),
              failureReason: _remoteMediaPermissionFailure(frame.reasonCode),
              updatedAt: DateTime.now().millisecondsSinceEpoch,
              audioLevel: const VoiceAudioLevel.unavailable(),
            ),
          );
        }
        break;
      case VoiceCallFrameType.mute:
        await session.handleFrame(frame);
        _handleVoiceMute(normalizedPeerId, frame);
        break;
      case VoiceCallFrameType.accept:
      case VoiceCallFrameType.offer:
      case VoiceCallFrameType.answer:
      case VoiceCallFrameType.candidate:
      case VoiceCallFrameType.hangup:
        await session.handleFrame(frame);
        break;
    }
  }

  Future<void> _handleFirebaseVoiceInvite(
    String peerId,
    VoiceCallFrame frame, {
    required VoiceCallRoom room,
  }) async {
    _recordRuntimeEvent(
      category: 'call',
      name: 'incoming_invite_received',
      context: <String, Object?>{
        ..._voiceFrameEventContext(peerId, frame),
        'roomStatus': room.status.name,
      },
    );
    final localUsername = _normalizedUsername(selfIdentity.username);
    if (room.status != VoiceCallSignalingStatus.ringing ||
        frame.callId != room.callId ||
        frame.sessionEpoch != room.createdAt ||
        _normalizedUsername(room.caller) != _normalizedUsername(peerId) ||
        _normalizedUsername(room.callee) != localUsername ||
        _normalizedUsername(frame.from) != _normalizedUsername(room.caller) ||
        _normalizedUsername(frame.to) != localUsername) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'incoming_invite_ignored',
        context: <String, Object?>{
          ..._voiceFrameEventContext(peerId, frame),
          'reason': 'roomMismatch',
          'roomStatus': room.status.name,
        },
      );
      return;
    }

    final disposition = await _prepareIncomingVoiceInvite(peerId, frame);
    _recordRuntimeEvent(
      category: 'call',
      name: 'incoming_invite_disposition',
      context: <String, Object?>{
        ..._voiceFrameEventContext(peerId, frame),
        'disposition': disposition.name,
      },
    );
    if (disposition == _IncomingVoiceInviteDisposition.ignore) {
      await _voiceCallSession?.handleFrame(frame);
      return;
    }
    if (disposition == _IncomingVoiceInviteDisposition.busy ||
        await _firstActiveTransfer() != null) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'incoming_invite_busy',
        severity: 'warning',
        context: _voiceFrameEventContext(peerId, frame),
      );
      await _endVoiceCallInSignaling(
        callId: frame.callId,
        status: VoiceCallSignalingStatus.failed,
        reason: 'Busy.',
        reasonCode: _voiceCallBusyReasonCode,
        bestEffort: true,
      );
      return;
    }
    final friend = await _localMutations.run(
      () => friendStore.loadFriend(peerId),
    );
    if (friend?.state != FriendState.friend) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'incoming_invite_rejected_friend_state',
        severity: 'warning',
        context: <String, Object?>{
          ..._voiceFrameEventContext(peerId, frame),
          'friendState': friend?.state.name,
        },
      );
      await _endVoiceCallInSignaling(
        callId: frame.callId,
        status: VoiceCallSignalingStatus.failed,
        reason: 'Only accepted friends can call.',
        reasonCode: _voiceCallFailedReasonCode,
        bestEffort: true,
      );
      return;
    }

    final session = await _createVoiceCallSession(
      peerId: peerId,
      callId: frame.callId,
      sessionEpoch: room.createdAt,
      isOutgoing: false,
      mediaMode: frame.mediaMode,
    );
    await session.handleFrame(frame);
  }

  Future<void> _handleVoiceInvite(String peerId, VoiceCallFrame frame) async {
    _recordRuntimeEvent(
      category: 'call',
      name: 'legacy_invite_received',
      context: _voiceFrameEventContext(peerId, frame),
    );
    final disposition = await _prepareIncomingVoiceInvite(peerId, frame);
    _recordRuntimeEvent(
      category: 'call',
      name: 'legacy_invite_disposition',
      context: <String, Object?>{
        ..._voiceFrameEventContext(peerId, frame),
        'disposition': disposition.name,
      },
    );
    if (disposition == _IncomingVoiceInviteDisposition.ignore) {
      await _voiceCallSession?.handleFrame(frame);
      return;
    }
    if (disposition == _IncomingVoiceInviteDisposition.busy ||
        await _firstActiveTransfer() != null) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'legacy_invite_busy',
        severity: 'warning',
        context: _voiceFrameEventContext(peerId, frame),
      );
      await _sendVoiceFrame(
        peerId,
        VoiceCallFrameType.busy,
        callId: frame.callId,
        sessionEpoch: frame.sessionEpoch,
        reason: 'Busy.',
        reasonCode: _voiceCallBusyReasonCode,
        bestEffort: true,
      );
      return;
    }
    final friend = await _localMutations.run(
      () => friendStore.loadFriend(peerId),
    );
    if (friend?.state != FriendState.friend) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'legacy_invite_rejected_friend_state',
        severity: 'warning',
        context: <String, Object?>{
          ..._voiceFrameEventContext(peerId, frame),
          'friendState': friend?.state.name,
        },
      );
      await _sendVoiceFrame(
        peerId,
        VoiceCallFrameType.reject,
        callId: frame.callId,
        sessionEpoch: frame.sessionEpoch,
        reason: 'Only accepted friends can call.',
        bestEffort: true,
      );
      return;
    }

    final session = await _createVoiceCallSession(
      peerId: peerId,
      callId: frame.callId,
      sessionEpoch: frame.sessionEpoch,
      isOutgoing: false,
      mediaMode: frame.mediaMode,
    );
    await session.handleFrame(frame);
  }

  Future<_IncomingVoiceInviteDisposition> _prepareIncomingVoiceInvite(
    String peerId,
    VoiceCallFrame frame,
  ) async {
    if (_shutDown || !_started) {
      return _IncomingVoiceInviteDisposition.busy;
    }

    final current = _voiceCallState;
    final normalizedPeerId = _normalizedUsername(peerId);

    if (!current.hasCall) {
      return _IncomingVoiceInviteDisposition.accept;
    }

    if (current.callId == frame.callId) {
      return _IncomingVoiceInviteDisposition.ignore;
    }

    if (current.phase == VoiceCallPhase.failed) {
      await _disposeCurrentVoiceCallSession();
      _setVoiceCallState(const VoiceCallState.idle());
      return _IncomingVoiceInviteDisposition.accept;
    }

    if (current.peerId != normalizedPeerId) {
      return _IncomingVoiceInviteDisposition.busy;
    }

    if (!_canReplaceVoiceCallWithRetry(current)) {
      return _IncomingVoiceInviteDisposition.busy;
    }

    await _replaceStaleVoiceCallForRetry(current);
    return _IncomingVoiceInviteDisposition.accept;
  }

  bool _canReplaceVoiceCallWithRetry(VoiceCallState current) {
    return VoiceCallPreflightCoordinator.instance.canReplaceVoiceCallWithRetry(
      current,
    );
  }

  Future<void> _replaceStaleVoiceCallForRetry(VoiceCallState current) async {
    await VoiceCallPreflightCoordinator.instance.replaceStaleVoiceCallForRetry(
      current,
      currentSession: _voiceCallSession,
      runBoundedCleanupStep: _runBoundedVoiceCleanupStep,
      sendHangupFrame:
          ({
            required String peerId,
            required String callId,
            required String reason,
          }) {
            return _sendVoiceFrame(
              peerId,
              VoiceCallFrameType.hangup,
              callId: callId,
              reason: reason,
              bestEffort: true,
            );
          },
      disposeCurrentVoiceCallSession: _disposeCurrentVoiceCallSession,
      setVoiceCallState: _setVoiceCallState,
    );
  }

  void _handleVoiceMute(String peerId, VoiceCallFrame frame) {
    if (!_isCurrentVoiceCall(
          peerId,
          frame.callId,
          sessionEpoch: frame.sessionEpoch,
        ) ||
        frame.muted == null && frame.cameraMuted == null) {
      return;
    }
    _setVoiceCallState(
      _voiceCallState.copyWith(
        isRemoteMuted: frame.muted ?? _voiceCallState.isRemoteMuted,
        isRemoteCameraMuted:
            frame.cameraMuted ?? _voiceCallState.isRemoteCameraMuted,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<VoiceCallSession> _createVoiceCallSession({
    required String peerId,
    required String callId,
    required int sessionEpoch,
    required bool isOutgoing,
    required CallMediaMode mediaMode,
  }) async {
    final manager = brain;
    if (manager == null) {
      throw StateError('Peer connection is unavailable right now.');
    }
    final voiceAdapter = _requireVoiceSignalingAdapter();

    await _disposeCurrentVoiceCallSession();
    final media = switch (mediaMode) {
      CallMediaMode.audio => await _createAudioVoiceMediaConnection(
        manager,
        peerId,
      ),
      CallMediaMode.video => await _createVideoVoiceMediaConnection(
        manager,
        peerId,
      ),
    };
    _recordRuntimeEvent(
      category: 'call',
      name: 'session_created',
      context: <String, Object?>{
        'peerId': peerId,
        'callId': callId,
        'sessionEpoch': sessionEpoch,
        'isOutgoing': isOutgoing,
        'mediaMode': mediaMode.name,
      },
    );
    final localRole = isOutgoing ? VoiceCallRole.caller : VoiceCallRole.callee;
    _voiceLocalIceCandidateCount = 0;
    _voiceIceCandidateBatcher = IceCandidateBatcher<VoiceSignalingEnvelope>(
      maxBatchSize: maxIceCandidateBatchSize,
      flushWindow: iceCandidateBatchWindow,
      onFlush: (List<VoiceSignalingEnvelope> candidates) {
        return _flushVoiceIceCandidateBatch(
          voiceAdapter: voiceAdapter,
          peerId: peerId,
          callId: callId,
          sessionEpoch: sessionEpoch,
          role: localRole,
          candidates: candidates,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        _recordVoiceIceCandidateWriteFailed(
          error,
          stackTrace,
          peerId: peerId,
          callId: callId,
          sessionEpoch: sessionEpoch,
          role: localRole,
          batchSize: 0,
        );
      },
    );
    final session = VoiceCallSession(
      localPeerId: selfIdentity.username,
      remotePeerId: peerId,
      callId: callId,
      sessionEpoch: sessionEpoch,
      media: media,
      sendFrame: (VoiceCallFrame frame) => _sendVoiceFrameObject(peerId, frame),
      isOfferOwner: isOutgoing,
      mediaMode: mediaMode,
      logger: (String message) {
        final alreadyTerminal = _isVoiceTerminalAlreadyClosedMessage(message);
        _recordRuntimeEvent(
          category: 'call',
          name: 'signaling_event_ignored',
          severity: alreadyTerminal ? 'info' : 'warning',
          message: message,
          context: <String, Object?>{
            'peerId': peerId,
            'callId': callId,
            'sessionEpoch': sessionEpoch,
            'mediaMode': mediaMode.name,
            'alreadyTerminal': alreadyTerminal,
          },
        );
        if (alreadyTerminal) {
          return;
        }
        errorRecorder?.call(
          StateError('Voice call signaling ignored: $message'),
          StackTrace.current,
          source: 'voice-call-signaling',
          fatal: false,
        );
      },
    );
    _voiceCallSession = session;
    _voiceCallSessionSubscription = session.onStateChanged.listen((
      VoiceCallSessionState state,
    ) {
      _applyVoiceSessionState(session, state, isOutgoing: isOutgoing);
    });
    if (!isOutgoing) {
      await _watchFirebaseVoiceCall(
        session: session,
        peerId: peerId,
        isOutgoing: false,
      );
    }
    return session;
  }

  Future<void> _watchFirebaseVoiceCall({
    required VoiceCallSession session,
    required String peerId,
    required bool isOutgoing,
  }) async {
    await VoiceCallSignalingCleanupCoordinator.instance.watchFirebaseVoiceCall(
      session: session,
      peerId: peerId,
      isOutgoing: isOutgoing,
      requireVoiceSignalingAdapter: _requireVoiceSignalingAdapter,
      adapter: adapter,
      selfUsername: selfIdentity.username,
      subscriptions: _voiceSignalingSubscriptions,
      isLiveVoiceCallSession: _isLiveVoiceCallSession,
      recordRuntimeEvent: _recordRuntimeEvent,
      handleFirebaseVoiceRoomUpdate: _handleFirebaseVoiceRoomUpdate,
      handleFirebaseVoiceEnvelope: _handleFirebaseVoiceEnvelope,
      handleVoiceSignalingStreamError: _handleVoiceSignalingStreamError,
      voiceIcePurpose: _voiceIcePurpose,
    );
  }

  void _handleVoiceSignalingStreamError(
    VoiceCallSession session,
    String peerId,
    Object error,
    StackTrace stackTrace,
  ) {
    VoiceCallSignalingCleanupCoordinator.instance
        .handleVoiceSignalingStreamError(
          session,
          peerId,
          error,
          stackTrace,
          recordVoiceSignalingError: _recordVoiceSignalingError,
          isLiveVoiceCallSession: _isLiveVoiceCallSession,
          isTerminalSessionLatched: _isTerminalVoiceCallSessionLatched,
          currentState: _voiceCallState,
          endVoiceCallForPeer: _endVoiceCallForPeer,
          signalingFailedMessage: _voiceCallSignalingFailed,
        );
  }

  Future<void> _handleFirebaseVoiceRoomUpdate({
    required VoiceCallSession session,
    required VoiceCallRoom room,
    required String peerId,
    required bool isOutgoing,
  }) async {
    await VoiceCallSignalingCleanupCoordinator.instance
        .handleFirebaseVoiceRoomUpdate(
          session: session,
          room: room,
          peerId: peerId,
          isOutgoing: isOutgoing,
          isLiveVoiceCallSession: _isLiveVoiceCallSession,
          recordLateVoiceFrame: _recordLateVoiceFrame,
          recordRoomStatusTransition: _recordVoiceRoomStatusTransition,
          localUsername: selfIdentity.username,
          normalizeUsername: _normalizedUsername,
          currentState: () => _voiceCallState,
          setVoiceCallState: _setVoiceCallState,
          reconcileTerminalVoiceRoom: _reconcileTerminalVoiceRoom,
        );
  }

  Future<void> _reconcileTerminalVoiceRoom({
    required VoiceCallSession session,
    required VoiceCallRoom room,
    required String peerId,
  }) async {
    await VoiceCallSignalingCleanupCoordinator.instance
        .reconcileTerminalVoiceRoom(
          session: session,
          room: room,
          peerId: peerId,
          isLiveVoiceCallSession: _isLiveVoiceCallSession,
          latchTerminalSession: _latchTerminalVoiceCallSession,
          isTerminalSessionLatched: _isTerminalVoiceCallSessionLatched,
          currentState: _voiceCallState,
          localUsername: selfIdentity.username,
          normalizeUsername: _normalizedUsername,
          terminalRoomDetail: _terminalVoiceCallDetailForRoom,
          terminalRoomFailureReason: _terminalVoiceCallFailureReasonForRoom,
          recordRuntimeEvent: _recordRuntimeEvent,
          eventContext: _voiceCallEventContext,
          reasonCodeForFailure: _voiceCallReasonCodeForFailure,
          failedReasonCode: _voiceCallFailedReasonCode,
          recordRuntimeFailure: _recordVoiceCallRuntimeFailure,
          settleVoiceCallAfterTerminalRace: _settleVoiceCallAfterTerminalRace,
        );
  }

  String _terminalVoiceCallDetailForRoom(VoiceCallRoom room, String localUser) {
    return VoiceCallRoomCoordinator.instance.terminalRoomDetail(
      room,
      localUser,
      detailForSessionState: _voiceCallDetailForSessionState,
    );
  }

  VoiceCallFailureReason? _terminalVoiceCallFailureReasonForRoom(
    VoiceCallRoom room,
  ) {
    return VoiceCallRoomCoordinator.instance.terminalRoomFailureReason(
      room,
      failureReasonForSessionState: _voiceCallFailureReasonForSessionState,
    );
  }
  // _terminalVoiceCallSessionStateForRoom removed — now in VoiceCallRoomCoordinator.

  // _terminalVoiceCallReason removed — now in VoiceCallRoomCoordinator._terminalReasonForStatus.

  String? _voiceCallReasonCodeForFailure(VoiceCallFailureReason? reason) {
    return VoiceCallRoomCoordinator.instance.reasonCodeForFailure(reason);
  }

  Future<void> _handleFirebaseVoiceEnvelope({
    required VoiceCallSession session,
    required String peerId,
    required VoiceSignalingEnvelope envelope,
    required String purpose,
  }) async {
    await VoiceCallSignalingCleanupCoordinator.instance
        .handleFirebaseVoiceEnvelope(
          session: session,
          peerId: peerId,
          envelope: envelope,
          purpose: purpose,
          isLiveVoiceCallSession: _isLiveVoiceCallSession,
          decryptVoiceFrame: _decryptVoiceFrame,
          recordRuntimeEvent: _recordRuntimeEvent,
          frameEventContext: _voiceFrameEventContext,
          recordLateVoiceFrame: _recordLateVoiceFrame,
          normalizeUsername: _normalizedUsername,
          localUsername: selfIdentity.username,
          recordVoiceSignalingError: _recordVoiceSignalingError,
          failVoiceCall: _failVoiceCall,
          mediaFailedMessage: _voiceCallMediaFailed,
        );
  }

  Future<void> _sendVoiceFrameObject(
    String peerId,
    VoiceCallFrame frame,
  ) async {
    await VoiceCallSignalingCleanupCoordinator.instance.sendVoiceFrameObject(
      peerId,
      frame,
      requireVoiceSignalingAdapter: _requireVoiceSignalingAdapter,
      localUsername: selfIdentity.username,
      normalizeUsername: _normalizedUsername,
      voiceCallExpiry: _voiceCallExpiry,
      transientCreateRetryDelay: _voiceCallTransientCreateRetryDelay,
      busyReasonCode: _voiceCallBusyReasonCode,
      rejectedReasonCode: _voiceCallRejectedReasonCode,
      recordRuntimeEvent: _recordRuntimeEvent,
      frameEventContext: _voiceFrameEventContext,
      shouldSkipTerminalSensitiveVoiceFrame:
          _shouldSkipTerminalSensitiveVoiceFrame,
      voiceCallLockDiagnostics: _voiceCallLockDiagnostics,
      signalingFailureSnapshotForError:
          _voiceCallSignalingFailureSnapshotForError,
      shouldRetryTransientCreateFailure:
          _shouldRetryTransientVoiceCreateFailure,
      recordRoomStatusTransition: _recordVoiceRoomStatusTransition,
      encryptVoiceFrame: _encryptVoiceFrame,
      queueVoiceIceCandidate: _queueVoiceIceCandidate,
    );
  }

  Future<bool> _shouldSkipTerminalSensitiveVoiceFrame({
    required VoiceSignalingAdapter voiceAdapter,
    required String peerId,
    required VoiceCallFrame frame,
  }) async {
    return VoiceCallSignalingCleanupCoordinator.instance
        .shouldSkipTerminalSensitiveVoiceFrame(
          voiceAdapter: voiceAdapter,
          peerId: peerId,
          frame: frame,
          currentSession: _voiceCallSession,
          isTerminalSessionLatched: _isTerminalVoiceCallSessionLatched,
          recordLateVoiceFrame: _recordLateVoiceFrame,
          requiresTerminalVoiceRoomPreflight:
              _requiresTerminalVoiceRoomPreflight,
          recordRuntimeEvent: _recordRuntimeEvent,
          frameEventContext: _voiceFrameEventContext,
          reconcileTerminalVoiceRoom: _reconcileTerminalVoiceRoom,
        );
  }

  bool _requiresTerminalVoiceRoomPreflight(VoiceCallFrameType type) {
    return VoiceCallSignalingCleanupCoordinator.instance
        .requiresTerminalVoiceRoomPreflight(type);
  }

  Future<void> _queueVoiceIceCandidate({
    required VoiceSignalingAdapter voiceAdapter,
    required String peerId,
    required VoiceCallFrame frame,
  }) async {
    await VoiceCallSignalingCleanupCoordinator.instance.queueVoiceIceCandidate(
      voiceAdapter: voiceAdapter,
      peerId: peerId,
      frame: frame,
      localRole: _localVoiceCallRole(),
      localIceCandidateCount: _voiceLocalIceCandidateCount,
      maxIceCandidatesPerRole: maxIceCandidatesPerRole,
      setLocalIceCandidateCount: (count) {
        _voiceLocalIceCandidateCount = count;
      },
      recordIceCandidateBudgetExceeded: _recordIceCandidateBudgetExceeded,
      encryptVoiceFrame: _encryptVoiceFrame,
      voiceIcePurpose: _voiceIcePurpose,
      recordVoiceIceCandidateWriteFailed: _recordVoiceIceCandidateWriteFailed,
      batcher: _voiceIceCandidateBatcher,
      flushVoiceIceCandidateBatch: _flushVoiceIceCandidateBatch,
    );
  }

  Future<void> _flushVoiceIceCandidateBatch({
    required VoiceSignalingAdapter voiceAdapter,
    required String peerId,
    required String callId,
    required int sessionEpoch,
    required VoiceCallRole role,
    required List<VoiceSignalingEnvelope> candidates,
  }) async {
    await VoiceCallSignalingCleanupCoordinator.instance
        .flushVoiceIceCandidateBatch(
          voiceAdapter: voiceAdapter,
          peerId: peerId,
          callId: callId,
          sessionEpoch: sessionEpoch,
          role: role,
          candidates: candidates,
          username: _normalizedUsername(selfIdentity.username),
          recordRuntimeEvent: _recordRuntimeEvent,
          recordIceCandidateBudgetExceeded: _recordIceCandidateBudgetExceeded,
          recordVoiceIceCandidateWriteFailed:
              _recordVoiceIceCandidateWriteFailed,
        );
  }

  void _recordIceCandidateBudgetExceeded({
    required String peerId,
    required String callId,
    required int sessionEpoch,
    required VoiceCallRole role,
    required int requestedCount,
    required int droppedCount,
    Object? error,
  }) {
    VoiceCallSignalingCleanupCoordinator.instance
        .recordIceCandidateBudgetExceeded(
          peerId: peerId,
          callId: callId,
          sessionEpoch: sessionEpoch,
          role: role,
          requestedCount: requestedCount,
          droppedCount: droppedCount,
          maxIceCandidatesPerRole: maxIceCandidatesPerRole,
          recordRuntimeEvent: _recordRuntimeEvent,
          error: error,
        );
  }

  void _recordVoiceIceCandidateWriteFailed(
    Object error,
    StackTrace stackTrace, {
    required String peerId,
    required String callId,
    required int sessionEpoch,
    required VoiceCallRole role,
    required int batchSize,
  }) {
    VoiceCallSignalingCleanupCoordinator.instance
        .recordVoiceIceCandidateWriteFailed(
          error,
          stackTrace,
          peerId: peerId,
          callId: callId,
          sessionEpoch: sessionEpoch,
          role: role,
          batchSize: batchSize,
          recordRuntimeEvent: _recordRuntimeEvent,
          errorRecorder: errorRecorder,
        );
  }

  void _applyVoiceSessionState(
    VoiceCallSession session,
    VoiceCallSessionState sessionState, {
    required bool isOutgoing,
  }) {
    VoiceCallSessionStateCoordinator.instance.applyVoiceSessionState(
      session,
      sessionState,
      isOutgoing: isOutgoing,
      isLiveVoiceCallSession: _isLiveVoiceCallSession,
      isTerminalSessionLatched: _isTerminalVoiceCallSessionLatched,
      currentState: () => _voiceCallState,
      recordLateVoiceFrame: _recordLateVoiceFrame,
      localMediaFailureReason: _localAudioFailureReason,
      localMediaFailureDetail: _localAudioFailureDetail,
      voiceCallErrorMessage: _voiceCallErrorMessage,
      setVoiceCallState: _setVoiceCallState,
      disposeVoiceCallSession: _disposeVoiceCallSession,
      voiceSignalingAdapter: voiceSignalingAdapter,
      localUsername: selfIdentity.username,
      normalizeUsername: _normalizedUsername,
      recordRoomStatusTransition: _recordVoiceRoomStatusTransition,
      isVoiceTerminalAlreadyClosedError: _isVoiceTerminalAlreadyClosedError,
      recordTerminalAlreadyClosed: _recordTerminalAlreadyClosed,
      eventContext: _voiceCallEventContext,
      settleVoiceCallAfterTerminalRace: _settleVoiceCallAfterTerminalRace,
      recordVoiceSignalingError: _recordVoiceSignalingError,
      finalizeFailedVoiceCallSession: _finalizeFailedVoiceCallSession,
    );
  }

  Future<void> _finalizeFailedVoiceCallSession(
    VoiceCallSession session,
    VoiceCallSessionState sessionState, {
    required bool isOutgoing,
    required String? detail,
    required VoiceCallFailureReason? failureReason,
  }) async {
    await VoiceCallSessionStateCoordinator.instance
        .finalizeFailedVoiceCallSession(
          session,
          sessionState,
          isOutgoing: isOutgoing,
          detail: detail,
          failureReason: failureReason,
          mediaFailedMessage: _voiceCallMediaFailed,
          failedReasonCode: _voiceCallFailedReasonCode,
          reasonCodeForFailure: _voiceCallReasonCodeForFailure,
          writeTerminalRoomBeforeSessionHangup:
              ({
                required callId,
                required status,
                required detail,
                reasonCode,
              }) async {
                final terminalWrite =
                    await _writeTerminalRoomBeforeSessionHangup(
                      callId: callId,
                      status: status,
                      detail: detail,
                      reasonCode: reasonCode,
                    );
                return (
                  durable: terminalWrite.durable,
                  error: terminalWrite.error,
                );
              },
          recordVoiceCallSessionFailure: _recordVoiceCallSessionFailure,
          recordRuntimeEvent: _recordRuntimeEvent,
          disposeVoiceCallSession: _disposeVoiceCallSession,
        );
  }

  VoiceCallFailureReason? _voiceCallFailureReasonForSessionState(
    VoiceCallSessionState state,
  ) {
    return VoiceCallStateCoordinator.instance.failureReasonForSessionState(
      state,
      localMediaFailureReason: _localAudioFailureReason,
    );
  }

  String? _voiceCallDetailForSessionState(VoiceCallSessionState state) {
    return VoiceCallStateCoordinator.instance.detailForSessionState(
      state,
      localMediaFailureDetail: _localAudioFailureDetail,
      errorMessage: _voiceCallErrorMessage,
    );
  }

  void _recordVoiceCallSessionFailure(
    VoiceCallSession session,
    VoiceCallSessionState state, {
    required bool isOutgoing,
  }) {
    VoiceCallSessionStateCoordinator.instance.recordVoiceCallSessionFailure(
      session,
      state,
      isOutgoing: isOutgoing,
      localMediaFailureReason: _localAudioFailureReason,
      localMediaFailureDetail: _localAudioFailureDetail,
      voiceCallErrorMessage: _voiceCallErrorMessage,
      mediaFailedMessage: _voiceCallMediaFailed,
      lastVideoCallRendererState: _lastVideoCallRendererState,
      cameraPermissionFailureDetail: _cameraPermissionFailureDetail,
      recordVoiceCallDiagnostics: _recordVoiceCallDiagnostics,
    );
  }

  void _recordVoiceCallRuntimeFailure(
    VoiceCallState state, {
    required String failureCode,
    required String userMessage,
    required String nativeError,
  }) {
    VoiceCallSessionStateCoordinator.instance.recordVoiceCallRuntimeFailure(
      state,
      failureCode: failureCode,
      userMessage: userMessage,
      nativeError: nativeError,
      callMediaDiagnostics: _videoCallMediaConnection?.diagnostics,
      sessionMediaDiagnostics: _voiceCallSession?.state.mediaDiagnostics,
      lastVideoCallRendererState: _lastVideoCallRendererState,
      recordVoiceCallDiagnostics: _recordVoiceCallDiagnostics,
    );
  }

  void _recordVoiceCallStartFailureDiagnostics({
    required Object error,
    required String peerId,
    required String callId,
    required int sessionEpoch,
    required CallMediaMode mediaMode,
    CallRetryDecision? retryDecision,
    CallSignalingFailureSnapshot? retrySnapshot,
  }) {
    VoiceCallSessionStateCoordinator.instance
        .recordVoiceCallStartFailureDiagnostics(
          error: error,
          peerId: peerId,
          callId: callId,
          sessionEpoch: sessionEpoch,
          mediaMode: mediaMode,
          failureReasonForRetryDecision:
              _voiceCallFailureReasonForRetryDecision,
          failureDetailForRetryDecision:
              _voiceCallFailureDetailForRetryDecision,
          failureReasonForError: _voiceCallFailureReasonForError,
          failureDetailForError: _voiceCallFailureDetailForError,
          localMediaFailureReason: _localAudioFailureReason,
          localMediaFailureDetail: _localAudioFailureDetail,
          voiceCallErrorMessage: _voiceCallErrorMessage,
          voiceCallLockDiagnostics: _voiceCallLockDiagnostics,
          recordVoiceCallDiagnostics: _recordVoiceCallDiagnostics,
          retryDecision: retryDecision,
          retrySnapshot: retrySnapshot,
        );
  }

  void _recordVoiceCallDiagnostics({
    required String callId,
    required int sessionEpoch,
    required String peerId,
    required bool isOutgoing,
    required CallMediaMode mediaMode,
    required String failureCode,
    required String userMessage,
    required String nativeError,
    VoiceMediaDiagnostics? mediaDiagnostics,
    VideoCallRendererState? rendererState,
    String? cameraPermissionFailureDetail,
    Map<String, Object?> lockDiagnostics = const <String, Object?>{},
  }) {
    VoiceCallSessionStateCoordinator.instance.recordVoiceCallDiagnostics(
      callId: callId,
      sessionEpoch: sessionEpoch,
      peerId: peerId,
      isOutgoing: isOutgoing,
      mediaMode: mediaMode,
      failureCode: failureCode,
      userMessage: userMessage,
      nativeError: nativeError,
      localUsername: selfIdentity.username,
      normalizeUsername: _normalizedUsername,
      errorRecorder: errorRecorder,
      roomStatusTimeline: _voiceRoomStatusTimeline,
      iceCandidateWriteCount: _voiceLocalIceCandidateCount,
      failureTaxonomy: _voiceFailureTaxonomy,
      isoTimestamp: _isoTimestamp,
      selectedCandidateRoute: _selectedVoiceCallCandidateRoute,
      mediaDiagnostics: mediaDiagnostics,
      rendererState: rendererState,
      cameraPermissionFailureDetail: cameraPermissionFailureDetail,
      lockDiagnostics: lockDiagnostics,
    );
  }

  String? _isoTimestamp(DateTime? value) {
    return value?.toUtc().toIso8601String();
  }

  String? _cameraPermissionFailureDetail(Object? error, String? reasonCode) {
    if (reasonCode == _voiceCallCameraDeniedReasonCode) {
      return error?.toString() ?? _voiceCallRemoteCameraPermissionRequired;
    }
    if (error != null &&
        _localAudioFailureReason(error) ==
            VoiceCallFailureReason.cameraDenied) {
      return error.toString();
    }
    return null;
  }

  String? _selectedVoiceCallCandidateRoute(String peerId) {
    final route = brain?.getSession(_normalizedUsername(peerId))?.route;
    if (route == null || route.kind.name == 'unknown') {
      return null;
    }
    final localType = route.localCandidateType?.trim();
    final remoteType = route.remoteCandidateType?.trim();
    final protocol = route.protocol?.trim();
    final relayProtocol = route.relayProtocol?.trim();
    final pairId = route.selectedCandidatePairId?.trim();
    final parts = <String>[
      route.kind.name,
      if (localType != null &&
          localType.isNotEmpty &&
          remoteType != null &&
          remoteType.isNotEmpty)
        '$localType->$remoteType',
      if (protocol != null && protocol.isNotEmpty) protocol,
      if (relayProtocol != null && relayProtocol.isNotEmpty)
        'relay:$relayProtocol',
      if (pairId != null && pairId.isNotEmpty) 'pair:$pairId',
    ];
    return parts.join(' ');
  }

  Future<void> _disposeCurrentVoiceCallSession() async {
    await VoiceCallSignalingCleanupCoordinator.instance
        .disposeCurrentVoiceCallSession(
          cancelReconnectGrace: _cancelVoiceCallReconnectGrace,
          disposeVoiceIceCandidateBatcher: _disposeVoiceIceCandidateBatcher,
          cancelVoiceSignalingSubscriptions: _cancelVoiceSignalingSubscriptions,
          currentSession: _voiceCallSession,
          sessionSubscription: _voiceCallSessionSubscription,
          setSessionSubscription: (subscription) {
            _voiceCallSessionSubscription = subscription;
          },
          runBoundedCleanupStep: _runBoundedVoiceCleanupStep,
          disposeVoiceCallSession: _disposeVoiceCallSession,
        );
  }

  Future<void> _disposeVoiceCallSession(VoiceCallSession session) async {
    await VoiceCallSignalingCleanupCoordinator.instance.disposeVoiceCallSession(
      session,
      currentSession: _voiceCallSession,
      setCurrentSession: (session) => _voiceCallSession = session,
      cancelReconnectGrace: _cancelVoiceCallReconnectGrace,
      disposeVoiceIceCandidateBatcher: _disposeVoiceIceCandidateBatcher,
      cancelVoiceSignalingSubscriptions: _cancelVoiceSignalingSubscriptions,
      sessionSubscription: _voiceCallSessionSubscription,
      setSessionSubscription: (subscription) {
        _voiceCallSessionSubscription = subscription;
      },
      disposeVideoCallResources: _disposeVideoCallResources,
      removeTerminalSessionKey: (callId, sessionEpoch) {
        _terminalVoiceCallSessionKeys.remove(
          _voiceCallSessionKey(callId, sessionEpoch),
        );
      },
      removeRoomStatusTimeline: _voiceRoomStatusTimelineByCall.remove,
      runBoundedCleanupStep: _runBoundedVoiceCleanupStep,
    );
  }

  Future<bool> _runBoundedVoiceCleanupStep(
    String step,
    Future<void> Function() cleanup, {
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    return VoiceCallSignalingCleanupCoordinator.instance
        .runBoundedVoiceCleanupStep(
          step,
          cleanup,
          cleanupStepTimeout: _voiceCallCleanupStepTimeout,
          recordRuntimeEvent: _recordRuntimeEvent,
          errorRecorder: errorRecorder,
          context: context,
        );
  }

  Future<void> _disposeVoiceIceCandidateBatcher() async {
    await VoiceCallSignalingCleanupCoordinator.instance
        .disposeVoiceIceCandidateBatcher(
          batcher: _voiceIceCandidateBatcher,
          setBatcher: (batcher) => _voiceIceCandidateBatcher = batcher,
          setLocalIceCandidateCount: (count) {
            _voiceLocalIceCandidateCount = count;
          },
          cleanupStepTimeout: _voiceCallCleanupStepTimeout,
          currentState: _voiceCallState,
          eventContext: _voiceCallEventContext,
          recordRuntimeEvent: _recordRuntimeEvent,
          recordVoiceIceCandidateWriteFailed:
              _recordVoiceIceCandidateWriteFailed,
          localVoiceCallRole: _localVoiceCallRole(),
        );
  }

  Future<void> _sendVoiceFrame(
    String peerId,
    VoiceCallFrameType type, {
    required String callId,
    int? sessionEpoch,
    String? reason,
    String? reasonCode,
    bool? muted,
    bool? cameraMuted,
    CallMediaMode mediaMode = CallMediaMode.audio,
    bool bestEffort = false,
  }) async {
    try {
      await _sendVoiceFrameObject(
        peerId,
        VoiceCallFrame(
          type: type,
          callId: callId,
          from: _normalizedUsername(selfIdentity.username),
          to: peerId,
          sentAt: DateTime.now().millisecondsSinceEpoch,
          seq: 1,
          sessionEpoch: sessionEpoch ?? _voiceCallSession?.sessionEpoch ?? 1,
          reason: reason,
          reasonCode: reasonCode,
          muted: muted,
          cameraMuted: cameraMuted,
          mediaMode: mediaMode,
        ),
      );
    } catch (_) {
      if (!bestEffort) {
        rethrow;
      }
    }
  }

  Future<VoiceSignalingEnvelope> _encryptVoiceFrame(
    VoiceCallFrame frame, {
    required String purpose,
    required int maxCiphertextLength,
  }) async {
    final encrypted = await voiceSignalingCipher.encryptPayload(
      roomId: frame.callId,
      purpose: purpose,
      timestamp: frame.sentAt,
      sender: frame.from,
      receiver: frame.to,
      payload: frame.toJson(),
    );
    return VoiceSignalingEnvelope.fromJson(
      Map<Object?, Object?>.from(encrypted),
      maxCiphertextLength: maxCiphertextLength,
    );
  }

  Future<VoiceCallFrame> _decryptVoiceFrame({
    required String callId,
    required VoiceSignalingEnvelope envelope,
    required String purpose,
  }) async {
    final decrypted = await voiceSignalingCipher.decryptPayload(
      roomId: callId,
      purpose: purpose,
      payload: envelope.toJson(
        maxCiphertextLength:
            purpose == SignalingCipher.offerPurpose ||
                purpose == SignalingCipher.answerPurpose
            ? VoiceSignalingEnvelope.maxSdpCiphertextLength
            : VoiceSignalingEnvelope.maxIceCiphertextLength,
      ),
    );
    return VoiceCallFrame.fromJson(Map<String, Object?>.from(decrypted));
  }

  VoiceCallRole _localVoiceCallRole() {
    return _voiceCallState.isOutgoing
        ? VoiceCallRole.caller
        : VoiceCallRole.callee;
  }

  String _voiceIcePurpose(VoiceCallRole role) {
    return switch (role) {
      VoiceCallRole.caller => SignalingCipher.callerIcePurpose,
      VoiceCallRole.callee => SignalingCipher.calleeIcePurpose,
    };
  }

  VoiceMediaOutputRoute _voiceMediaOutputRoute(VoiceCallOutputRoute route) {
    return switch (route) {
      VoiceCallOutputRoute.systemDefault => VoiceMediaOutputRoute.systemDefault,
      VoiceCallOutputRoute.speaker => VoiceMediaOutputRoute.speaker,
      VoiceCallOutputRoute.bluetooth => VoiceMediaOutputRoute.bluetooth,
    };
  }

  String _voiceCallPreflightDetail(CallMediaMode mediaMode) {
    return VoiceCallStateCoordinator.instance.preflightDetail(mediaMode);
  }

  bool _isRemoteMediaPermissionCode(String? reasonCode) {
    return VoiceCallStateCoordinator.instance.isRemoteMediaPermissionCode(
      reasonCode,
    );
  }

  VoiceCallFailureReason _remoteMediaPermissionFailure(String? reasonCode) {
    return VoiceCallStateCoordinator.instance.remoteMediaPermissionFailure(
      reasonCode,
    );
  }

  String _remoteMediaPermissionDetail(String? reasonCode) {
    return VoiceCallStateCoordinator.instance.remoteMediaPermissionDetail(
      reasonCode,
    );
  }

  Future<VoiceMediaConnection> _createVideoVoiceMediaConnection(
    SessionManager manager,
    String peerId,
  ) async {
    return VoiceCallMediaCoordinator.instance.createVideoVoiceMediaConnection(
      manager,
      peerId,
      rendererFactory: videoCallRendererFactory,
      remoteFirstFrameTimeout: videoCallRemoteFirstFrameTimeout,
      recordRuntimeEvent: _recordRuntimeEvent,
      setLastRendererState: (state) => _lastVideoCallRendererState = state,
      setHandledFirstFrameTimeoutCallId: (callId) {
        _handledVideoFirstFrameTimeoutCallId = callId;
      },
      setLastLoggedRendererSignature: (signature) {
        _lastLoggedVideoRendererSignature = signature;
      },
      setVideoCallMediaConnection: (media) => _videoCallMediaConnection = media,
      setVideoCallRenderers: (renderers) => _videoCallRenderers = renderers,
      setVideoCallRendererSubscription: (subscription) {
        _videoCallRendererSubscription = subscription;
      },
      handleRendererState: _handleVideoRendererState,
      handleRendererFailure: _handleVideoRendererFailure,
      errorRecorder: errorRecorder,
    );
  }

  Future<VoiceMediaConnection> _createAudioVoiceMediaConnection(
    SessionManager manager,
    String peerId,
  ) async {
    return VoiceCallMediaCoordinator.instance.createAudioVoiceMediaConnection(
      manager,
      peerId,
      recordRuntimeEvent: _recordRuntimeEvent,
      errorRecorder: errorRecorder,
    );
  }

  void _handleVideoRendererState(VideoCallRendererState rendererState) {
    VoiceCallMediaCoordinator.instance.handleVideoRendererState(
      rendererState,
      currentState: _voiceCallState,
      lastLoggedRendererSignature: _lastLoggedVideoRendererSignature,
      handledFirstFrameTimeoutCallId: _handledVideoFirstFrameTimeoutCallId,
      setLastRendererState: (state) => _lastVideoCallRendererState = state,
      setLastLoggedRendererSignature: (signature) {
        _lastLoggedVideoRendererSignature = signature;
      },
      setHandledFirstFrameTimeoutCallId: (callId) {
        _handledVideoFirstFrameTimeoutCallId = callId;
      },
      recordRuntimeEvent: _recordRuntimeEvent,
      eventContext: _voiceCallEventContext,
      isoTimestamp: _isoTimestamp,
      setVoiceCallState: _setVoiceCallState,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _handleVideoRendererFailure(
    String peerId,
    Object error,
    StackTrace stackTrace,
  ) {
    VoiceCallMediaCoordinator.instance.handleVideoRendererFailure(
      peerId,
      error,
      stackTrace,
      normalizeUsername: _normalizedUsername,
      currentState: _voiceCallState,
      recordRuntimeEvent: _recordRuntimeEvent,
      eventContext: _voiceCallEventContext,
      errorRecorder: errorRecorder,
      recordRuntimeFailure: _recordVoiceCallRuntimeFailure,
      endVoiceCallForPeer: _endVoiceCallForPeer,
      rendererFailedReasonCode: _voiceCallVideoRendererFailedReasonCode,
      videoFailedMessage: _voiceCallVideoFailed,
    );
  }

  void _handleVoiceCallAppLifecycleState(AppLifecycleState state) {
    VoiceCallMediaCoordinator.instance.handleVoiceCallAppLifecycleState(
      state,
      videoCallMediaConnection: _videoCallMediaConnection,
      currentState: _voiceCallState,
      recordRuntimeEvent: _recordRuntimeEvent,
      eventContext: _voiceCallEventContext,
      recordRuntimeFailure: _recordVoiceCallRuntimeFailure,
      endVoiceCallForPeer: _endVoiceCallForPeer,
      failedReasonCode: _voiceCallFailedReasonCode,
      videoBackgroundedMessage: _voiceCallVideoBackgrounded,
    );
  }

  Future<void> _setVideoCallCameraMutedInSignaling(bool muted) async {
    await VoiceCallMediaCoordinator.instance.setVideoCallCameraMutedInSignaling(
      muted,
      currentState: _voiceCallState,
      requireVoiceSignalingAdapter: _requireVoiceSignalingAdapter,
      username: _normalizedUsername(selfIdentity.username),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      recordVoiceSignalingError: _recordVoiceSignalingError,
    );
  }

  Future<void> _disposeVideoCallResources() async {
    await VoiceCallMediaCoordinator.instance.disposeVideoCallResources(
      renderers: _videoCallRenderers,
      mediaConnection: _videoCallMediaConnection,
      rendererSubscription: _videoCallRendererSubscription,
      setVideoCallRenderers: (renderers) => _videoCallRenderers = renderers,
      setVideoCallMediaConnection: (media) => _videoCallMediaConnection = media,
      setVideoCallRendererSubscription: (subscription) {
        _videoCallRendererSubscription = subscription;
      },
      setLastLoggedRendererSignature: (signature) {
        _lastLoggedVideoRendererSignature = signature;
      },
      setLastRendererState: (state) => _lastVideoCallRendererState = state,
      runBoundedCleanupStep: _runBoundedVoiceCleanupStep,
      recordRuntimeEvent: _recordRuntimeEvent,
      eventContext: _voiceCallEventContext,
      currentState: _voiceCallState,
    );
  }

  VoiceSignalingAdapter _requireVoiceSignalingAdapter() {
    final voiceAdapter = voiceSignalingAdapter;
    if (voiceAdapter == null) {
      throw StateError('Voice calls require Firebase voice signaling.');
    }
    return voiceAdapter;
  }

  Future<void> _cleanupStaleVoiceCallArtifacts(String reason) async {
    await VoiceCallSignalingCleanupCoordinator.instance
        .cleanupStaleVoiceCallArtifacts(
          reason,
          voiceSignalingAdapter: voiceSignalingAdapter,
          runtimeShutDown: _shutDown,
          username: selfIdentity.username,
          recordRuntimeEvent: _recordRuntimeEvent,
          errorRecorder: errorRecorder,
        );
  }

  void _recordVoiceSignalingError(Object error, StackTrace stackTrace) {
    VoiceCallSignalingCleanupCoordinator.instance.recordVoiceSignalingError(
      error,
      stackTrace,
      isVoiceTerminalAlreadyClosedError: _isVoiceTerminalAlreadyClosedError,
      recordTerminalAlreadyClosed: _recordTerminalAlreadyClosed,
      context: _voiceCallEventContext(_voiceCallState),
      recordRuntimeEvent: _recordRuntimeEvent,
      errorRecorder: errorRecorder,
    );
  }

  Future<void> _cancelVoiceSignalingSubscriptions() async {
    await VoiceCallSignalingCleanupCoordinator.instance
        .cancelVoiceSignalingSubscriptions(
          subscriptions: _voiceSignalingSubscriptions,
          runBoundedCleanupStep: _runBoundedVoiceCleanupStep,
        );
  }

  Future<void> _endVoiceCallInSignaling({
    required String callId,
    required VoiceCallSignalingStatus status,
    String? reason,
    String? reasonCode,
    bool bestEffort = false,
  }) async {
    await VoiceCallSignalingCleanupCoordinator.instance.endVoiceCallInSignaling(
      callId: callId,
      status: status,
      requireVoiceSignalingAdapter: _requireVoiceSignalingAdapter,
      username: _normalizedUsername(selfIdentity.username),
      recordRoomStatusTransition: _recordVoiceRoomStatusTransition,
      isDurableTerminalStateError: _isDurableVoiceCallTerminalStateError,
      recordRuntimeEvent: _recordRuntimeEvent,
      reason: reason,
      reasonCode: reasonCode,
      bestEffort: bestEffort,
    );
  }

  void _recordVoiceRoomStatusTransition(
    String callId,
    VoiceCallSignalingStatus status,
  ) {
    VoiceCallSignalingCleanupCoordinator.instance
        .recordVoiceRoomStatusTransition(
          _voiceRoomStatusTimelineByCall,
          _voiceRoomSignalingStatusByCall,
          callId,
          status,
        );
  }

  List<String> _voiceRoomStatusTimeline(String callId) {
    return VoiceCallSignalingCleanupCoordinator.instance
        .voiceRoomStatusTimeline(_voiceRoomStatusTimelineByCall, callId);
  }

  bool _isDurableVoiceCallTerminalStateError(Object error) {
    return VoiceCallSignalingCleanupCoordinator.instance
        .isDurableVoiceCallTerminalStateError(
          error,
          normalizeErrorText: _normalizedVoiceCallErrorText,
        );
  }

  bool _isVoiceTerminalAlreadyClosedError(Object error) {
    return VoiceCallSignalingCleanupCoordinator.instance
        .isVoiceTerminalAlreadyClosedError(
          error,
          normalizeErrorText: _normalizedVoiceCallErrorText,
        );
  }

  bool _isVoiceTerminalAlreadyClosedMessage(String message) {
    return VoiceCallSignalingCleanupCoordinator.instance
        .isVoiceTerminalAlreadyClosedMessage(message);
  }

  void _recordTerminalAlreadyClosed(
    Object error, {
    required String name,
    required Map<String, Object?> context,
  }) {
    VoiceCallSignalingCleanupCoordinator.instance.recordTerminalAlreadyClosed(
      error,
      name: name,
      context: context,
      recordRuntimeEvent: _recordRuntimeEvent,
    );
  }

  Future<void> _settleVoiceCallAfterTerminalRace(
    VoiceCallSession session, {
    required String detail,
    VoiceCallFailureReason? failureReason,
  }) async {
    if (!_isLiveVoiceCallSession(session)) {
      return;
    }
    final current = _voiceCallState;
    if (current.callId != session.callId ||
        current.sessionEpoch != session.sessionEpoch ||
        current.phase == VoiceCallPhase.idle ||
        current.phase == VoiceCallPhase.failed) {
      return;
    }
    if (failureReason != null) {
      final failedState = _voiceCallStateAfterLocalEnd(
        current,
        detail: detail,
        failureReason: failureReason,
        failureDetail: detail,
      );
      _setVoiceCallState(failedState);
      await _disposeVoiceCallSession(session);
      return;
    }
    _setVoiceCallState(
      current.copyWith(
        phase: VoiceCallPhase.ending,
        detail: detail,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        audioLevel: const VoiceAudioLevel.unavailable(),
      ),
    );
    _setVoiceCallState(const VoiceCallState.idle());
    await _disposeVoiceCallSession(session);
  }

  Future<void> _endVoiceCallForPeer(
    String peerId, {
    required bool notifyPeer,
    required String detail,
    VoiceCallFailureReason? failureReason,
    String? failureDetail,
  }) async {
    final normalizedPeerId = _normalizedUsername(peerId);
    // Guard against concurrent end calls (e.g., multiple signaling streams
    // failing at once). Only the first caller proceeds.
    if (_endingCallPeerId != null) {
      return;
    }
    _endingCallPeerId = normalizedPeerId;
    try {
      await _endVoiceCallForPeerImpl(
        normalizedPeerId,
        notifyPeer: notifyPeer,
        detail: detail,
        failureReason: failureReason,
        failureDetail: failureDetail,
      );
    } finally {
      if (_endingCallPeerId == normalizedPeerId) {
        _endingCallPeerId = null;
      }
    }
  }

  Future<void> _endVoiceCallForPeerImpl(
    String peerId, {
    required bool notifyPeer,
    required String detail,
    VoiceCallFailureReason? failureReason,
    String? failureDetail,
  }) async {
    final current = _voiceCallState;
    _recordRuntimeEvent(
      category: 'call',
      name: 'end_for_peer_requested',
      message: detail,
      context: <String, Object?>{
        ..._voiceCallEventContext(current),
        'peerId': _normalizedUsername(peerId),
        'notifyPeer': notifyPeer,
        'failureReason': failureReason?.name,
        'failureDetail': failureDetail,
      },
    );
    if (current.peerId != _normalizedUsername(peerId)) {
      return;
    }
    final session = _voiceCallSession;
    if (session != null && current.callId == session.callId) {
      _setVoiceCallState(
        current.copyWith(
          phase: VoiceCallPhase.ending,
          detail: detail,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          audioLevel: const VoiceAudioLevel.unavailable(),
        ),
      );
      // Immediately publish "ended" so the UI shows the ended screen
      // without waiting for the Firebase terminal write.
      _setVoiceCallState(
        current.copyWith(
          phase: VoiceCallPhase.ended,
          detail: detail,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          audioLevel: const VoiceAudioLevel.unavailable(),
        ),
      );
      _latchTerminalVoiceCallSession(session);
      if (notifyPeer) {
        final terminalWrite = await _writeTerminalRoomBeforeSessionHangup(
          callId: session.callId,
          status: failureReason == null
              ? VoiceCallSignalingStatus.ended
              : VoiceCallSignalingStatus.failed,
          detail: detail,
          reasonCode: _voiceCallReasonCodeForFailure(failureReason),
        );
        var latest = _voiceCallState;
        if (!_isSameLiveVoiceCallStateForSession(latest, session)) {
          return;
        }
        if (!terminalWrite.durable) {
          _setVoiceCallState(
            _voiceCallStateAfterTerminalWriteFailure(
              latest,
              error: terminalWrite.error,
            ),
          );
          await _disposeVoiceCallSession(session);
          return;
        }
        latest = _voiceCallState;
        if (!_isSameLiveVoiceCallStateForSession(latest, session)) {
          return;
        }
        _setVoiceCallState(
          _voiceCallStateAfterLocalEnd(
            latest,
            detail: detail,
            failureReason: failureReason,
            failureDetail: failureDetail,
          ),
        );
        await _runBoundedVoiceCleanupStep(
          'voice_call_session_hangup',
          () => session.hangUp(reason: detail),
          context: <String, Object?>{
            'peerId': session.remotePeerId,
            'callId': session.callId,
            'sessionEpoch': session.sessionEpoch,
          },
        );
        await _disposeVoiceCallSession(session);
      } else {
        await _endVoiceCallInSignaling(
          callId: session.callId,
          status: failureReason == null
              ? VoiceCallSignalingStatus.ended
              : VoiceCallSignalingStatus.failed,
          reason: detail,
          reasonCode: _voiceCallReasonCodeForFailure(failureReason),
          bestEffort: true,
        );
        _setVoiceCallState(
          _voiceCallStateAfterLocalEnd(
            current,
            detail: detail,
            failureReason: failureReason,
            failureDetail: failureDetail,
          ),
        );
        await _disposeVoiceCallSession(session);
      }
      return;
    }

    _setVoiceCallState(
      current.copyWith(
        phase: VoiceCallPhase.ending,
        detail: detail,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        audioLevel: const VoiceAudioLevel.unavailable(),
      ),
    );
    // Immediately publish "ended" for UI responsiveness.
    _setVoiceCallState(
      current.copyWith(
        phase: VoiceCallPhase.ended,
        detail: detail,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        audioLevel: const VoiceAudioLevel.unavailable(),
      ),
    );
    var latest = current;
    if (notifyPeer && current.callId != null) {
      final terminalWrite = await _writeTerminalRoomBeforeSessionHangup(
        callId: current.callId!,
        status: failureReason == null
            ? VoiceCallSignalingStatus.ended
            : VoiceCallSignalingStatus.failed,
        detail: detail,
        reasonCode: _voiceCallReasonCodeForFailure(failureReason),
      );
      latest = _voiceCallState;
      if (!_isSameLiveVoiceCallState(latest, current)) {
        return;
      }
      if (!terminalWrite.durable) {
        _setVoiceCallState(
          _voiceCallStateAfterTerminalWriteFailure(
            latest,
            error: terminalWrite.error,
          ),
        );
        return;
      }
    } else if (current.callId != null) {
      await _endVoiceCallInSignaling(
        callId: current.callId!,
        status: failureReason == null
            ? VoiceCallSignalingStatus.ended
            : VoiceCallSignalingStatus.failed,
        reason: detail,
        reasonCode: _voiceCallReasonCodeForFailure(failureReason),
        bestEffort: true,
      );
    }
    _setVoiceCallState(
      _voiceCallStateAfterLocalEnd(
        latest,
        detail: detail,
        failureReason: failureReason,
        failureDetail: failureDetail,
      ),
    );
  }

  Future<_TerminalRoomWriteResult> _writeTerminalRoomBeforeSessionHangup({
    required String callId,
    required VoiceCallSignalingStatus status,
    required String detail,
    String? reasonCode,
  }) async {
    final result = await VoiceCallSignalingCleanupCoordinator.instance
        .writeTerminalRoomBeforeSessionHangup(
          callId: callId,
          status: status,
          detail: detail,
          reasonCode: reasonCode,
          terminalWritePolicy: _voiceTerminalWritePolicy,
          endVoiceCallInSignaling: _endVoiceCallInSignaling,
          isDurableTerminalStateError: _isDurableVoiceCallTerminalStateError,
          recordRuntimeEvent: _recordRuntimeEvent,
          errorRecorder: errorRecorder,
        );
    return result.durable
        ? const _TerminalRoomWriteResult.durable()
        : _TerminalRoomWriteResult.failed(result.error);
  }

  VoiceCallState _voiceCallStateAfterTerminalWriteFailure(
    VoiceCallState current, {
    Object? error,
  }) {
    return VoiceCallStateCoordinator.instance.stateAfterTerminalWriteFailure(
      current,
      error: error,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  bool _isSameLiveVoiceCallStateForSession(
    VoiceCallState latest,
    VoiceCallSession session,
  ) {
    return VoiceCallStateCoordinator.instance.isSameLiveSessionState(
      latest,
      runtimeShutDown: _shutDown,
      ownsRuntimeSession: _voiceCallSession == session,
      callId: session.callId,
      sessionEpoch: session.sessionEpoch,
    );
  }

  bool _isSameLiveVoiceCallState(
    VoiceCallState latest,
    VoiceCallState expected,
  ) {
    return VoiceCallStateCoordinator.instance.isSameLiveState(latest, expected);
  }

  VoiceCallState _voiceCallStateAfterLocalEnd(
    VoiceCallState current, {
    required String detail,
    VoiceCallFailureReason? failureReason,
    String? failureDetail,
  }) {
    return VoiceCallStateCoordinator.instance.stateAfterLocalEnd(
      current,
      detail: detail,
      failureReason: failureReason,
      failureDetail: failureDetail,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _failVoiceCallForPeer(String peerId, String message) {
    VoiceCallReconnectCoordinator.instance.failVoiceCallForPeer(
      peerId,
      message,
      normalizeUsername: _normalizedUsername,
      currentState: _voiceCallState,
      failPeer: (normalizedPeerId, failureMessage) {
        return _endVoiceCallForPeer(
          normalizedPeerId,
          notifyPeer: false,
          detail: failureMessage,
          failureReason: VoiceCallFailureReason.networkLost,
          failureDetail: failureMessage,
        );
      },
    );
  }

  void _markVoiceCallReconnectingForPeer(String peerId) {
    VoiceCallReconnectCoordinator.instance.markVoiceCallReconnectingForPeer(
      peerId,
      normalizeUsername: _normalizedUsername,
      currentState: _voiceCallState,
      currentSession: _voiceCallSession,
      recordRuntimeEvent: _recordRuntimeEvent,
      eventContext: _voiceCallEventContext,
      setVoiceCallState: _setVoiceCallState,
      armReconnectGrace: _armVoiceCallReconnectGrace,
      reconnectingDetail: _voiceCallReconnecting,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _clearVoiceCallReconnectingForPeer(String peerId) {
    VoiceCallReconnectCoordinator.instance.clearVoiceCallReconnectingForPeer(
      peerId,
      normalizeUsername: _normalizedUsername,
      currentState: _voiceCallState,
      currentSession: _voiceCallSession,
      recordRuntimeEvent: _recordRuntimeEvent,
      eventContext: _voiceCallEventContext,
      setVoiceCallState: _setVoiceCallState,
      cancelReconnectGrace: _cancelVoiceCallReconnectGrace,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _armVoiceCallReconnectGrace(VoiceCallState call) {
    VoiceCallReconnectCoordinator.instance.armVoiceCallReconnectGrace(
      call,
      gracePeriod: activeCallReconnectGrace,
      reconnectGraceTimer: _voiceCallReconnectGraceTimer,
      setReconnectGraceTimer: (timer) => _voiceCallReconnectGraceTimer = timer,
      currentState: () => _voiceCallState,
      failPeer: (peerId, failureMessage) {
        return _endVoiceCallForPeer(
          peerId,
          notifyPeer: false,
          detail: failureMessage,
          failureReason: VoiceCallFailureReason.networkLost,
          failureDetail: failureMessage,
        );
      },
      networkLostMessage: _voiceCallNetworkLost,
    );
  }

  void _cancelVoiceCallReconnectGrace() {
    VoiceCallReconnectCoordinator.instance.cancelVoiceCallReconnectGrace(
      reconnectGraceTimer: _voiceCallReconnectGraceTimer,
      setReconnectGraceTimer: (timer) => _voiceCallReconnectGraceTimer = timer,
    );
  }

  void _assertVoiceCallCanStart() {
    VoiceCallPreflightCoordinator.instance.assertVoiceCallCanStart(
      peerConnectionAvailable: brain != null,
    );
  }

  Future<void> _assertVoiceCallPeerIsFriend(String peerId) async {
    await VoiceCallPreflightCoordinator.instance.assertVoiceCallPeerIsFriend(
      peerId,
      isAcceptedFriend: (username) async {
        final friend = await _localMutations.run(
          () => friendStore.loadFriend(username),
        );
        return friend?.state == FriendState.friend;
      },
      syncRelationships: (username) =>
          _syncRelationships(onlyUsername: username),
    );
  }

  Future<VoiceCallStartPresenceSnapshot> _fetchVoiceCallPeerPresence(
    String peerId, {
    required CallMediaMode mediaMode,
  }) {
    return VoiceCallPreflightCoordinator.instance.fetchVoiceCallPeerPresence(
      peerId,
      mediaMode: mediaMode,
      normalizeUsername: _normalizedUsername,
      fetchPresence: (username, {required String action}) async {
        final presence = await _fetchPeerPresenceSnapshot(
          username,
          action: action,
        );
        if (presence == null) {
          return null;
        }
        return VoiceCallPeerPresence(
          online: presence.online,
          diagnostics: presence.toDiagnostics(),
        );
      },
      recordRuntimeEvent: _recordRuntimeEvent,
      errorRecorder: errorRecorder == null
          ? null
          : (error, stackTrace, {required String source, required bool fatal}) {
              errorRecorder?.call(
                error,
                stackTrace,
                source: source,
                fatal: fatal,
              );
            },
    );
  }

  Future<FileTransferRecord?> _firstActiveTransfer() async {
    final transfers = await fileTransferStore.loadActiveTransfers();
    return transfers.isEmpty ? null : transfers.first;
  }

  Future<void> _failVoiceCall(
    Object error, {
    VoiceCallFailureReason? failureReason,
    String? detail,
  }) async {
    final current = _voiceCallState;
    final effectiveFailureReason =
        failureReason ?? _voiceCallFailureReasonForError(error);
    final effectiveDetail =
        detail ??
        _voiceCallFailureDetailForError(error) ??
        _voiceCallErrorMessage(error);
    _recordRuntimeEvent(
      category: 'call',
      name: 'failed',
      severity: 'error',
      message: effectiveDetail,
      context: <String, Object?>{
        ..._voiceCallEventContext(current),
        'nativeError': error.toString(),
        'failureReason': effectiveFailureReason?.name,
      },
    );
    if (current.callId != null) {
      await _endVoiceCallInSignaling(
        callId: current.callId!,
        status: VoiceCallSignalingStatus.failed,
        reason: effectiveDetail,
        reasonCode:
            _voiceCallReasonCodeForFailure(effectiveFailureReason) ??
            _voiceCallFailedReasonCode,
        bestEffort: true,
      );
    }
    _setVoiceCallState(
      current.copyWith(
        phase: VoiceCallPhase.failed,
        detail: effectiveDetail,
        error: error,
        failureReason: effectiveFailureReason,
        isCameraMuted: false,
        isDeafened: false,
        isRemoteCameraMuted: false,
        hasLocalVideo: false,
        hasRemoteVideo: false,
        videoFirstFrameTimedOut: false,
        mediaReconnecting: false,
        outputRoute: VoiceCallOutputRoute.systemDefault,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        clearOutputRouteWarning: true,
        clearOutputRouteTarget: true,
        clearReconnectingSince: true,
        audioLevel: const VoiceAudioLevel.unavailable(),
      ),
    );
    await _disposeCurrentVoiceCallSession();
  }

  bool _isLiveVoiceCallSession(VoiceCallSession session) {
    if (_shutDown || _voiceCallSession != session) {
      return false;
    }
    final currentCallId = _voiceCallState.callId;
    final currentEpoch = _voiceCallState.sessionEpoch;
    final currentCanBePreviousTerminal =
        _voiceCallState.phase == VoiceCallPhase.failed;
    if (currentCallId != null &&
        currentCallId != session.callId &&
        !currentCanBePreviousTerminal) {
      return false;
    }
    if (currentEpoch != null &&
        currentEpoch != session.sessionEpoch &&
        !currentCanBePreviousTerminal) {
      return false;
    }
    return true;
  }

  void _latchTerminalVoiceCallSession(VoiceCallSession session) {
    _terminalVoiceCallSessionKeys.add(
      _voiceCallSessionKey(session.callId, session.sessionEpoch),
    );
  }

  bool _isTerminalVoiceCallSessionLatched(VoiceCallSession session) {
    return _terminalVoiceCallSessionKeys.contains(
      _voiceCallSessionKey(session.callId, session.sessionEpoch),
    );
  }

  String _voiceCallSessionKey(String callId, int sessionEpoch) {
    return '$callId@$sessionEpoch';
  }

  bool _isCurrentVoiceCall(String peerId, String callId, {int? sessionEpoch}) {
    return _voiceCallState.peerId == _normalizedUsername(peerId) &&
        _voiceCallState.callId == callId &&
        (sessionEpoch == null || _voiceCallState.sessionEpoch == sessionEpoch);
  }

  void _recordLateVoiceFrame(VoiceCallSession session, String message) {
    _recordRuntimeEvent(
      category: 'call',
      name: 'late_frame_ignored',
      severity: 'warning',
      message: message,
      context: <String, Object?>{
        'peerId': session.remotePeerId,
        'callId': session.callId,
        'sessionEpoch': session.sessionEpoch,
        'mediaMode': session.mediaMode.name,
      },
    );
  }

  Map<String, Object?> _voiceCallEventContext(VoiceCallState state) {
    return <String, Object?>{
      'peerId': state.peerId,
      'callId': state.callId,
      'sessionEpoch': state.sessionEpoch,
      'phase': state.phase.name,
      'mediaMode': state.mediaMode.name,
      'isOutgoing': state.isOutgoing,
      'isMuted': state.isMuted,
      'isRemoteMuted': state.isRemoteMuted,
      'isCameraMuted': state.isCameraMuted,
      'isRemoteCameraMuted': state.isRemoteCameraMuted,
      'isDeafened': state.isDeafened,
      'hasLocalVideo': state.hasLocalVideo,
      'hasRemoteVideo': state.hasRemoteVideo,
      'videoFirstFrameTimedOut': state.videoFirstFrameTimedOut,
      'mediaReconnecting': state.mediaReconnecting,
      'failureReason': state.failureReason?.name,
      if (state.failureReason != null)
        'failureTaxonomy': _voiceFailureTaxonomy(
          failureCode: state.failureReason!.name,
          userMessage: state.detail ?? '',
          nativeError: state.error?.toString() ?? '',
        ),
      'detail': state.detail,
      'error': state.error?.toString(),
      'startedAt': state.startedAt,
      'updatedAt': state.updatedAt,
      'selectedCandidateRoute': state.peerId == null
          ? null
          : _selectedVoiceCallCandidateRoute(state.peerId!),
    };
  }

  Map<String, Object?> _voiceFrameEventContext(
    String peerId,
    VoiceCallFrame frame,
  ) {
    return <String, Object?>{
      'peerId': _normalizedUsername(peerId),
      'callId': frame.callId,
      'sessionEpoch': frame.sessionEpoch,
      'frameType': frame.type.name,
      'seq': frame.seq,
      'from': _normalizedUsername(frame.from),
      'to': _normalizedUsername(frame.to),
      'mediaMode': frame.mediaMode.name,
      'reasonCode': frame.reasonCode,
      'reason': frame.reason,
      'hasSdp': frame.sdp != null,
      'sdpType': frame.sdpType,
      'hasCandidate': frame.candidate != null,
      'muted': frame.muted,
      'cameraMuted': frame.cameraMuted,
    };
  }

  void _setVoiceCallState(VoiceCallState state) {
    if (!state.mediaReconnecting ||
        state.phase == VoiceCallPhase.idle ||
        state.phase == VoiceCallPhase.failed ||
        state.phase == VoiceCallPhase.ending) {
      _cancelVoiceCallReconnectGrace();
    }
    _recordVoiceCallStateIfChanged(state);
    _voiceCallState = state;
    if (!_voiceCallStateController.isClosed) {
      _voiceCallStateController.add(state);
    }
  }

  void _recordVoiceCallStateIfChanged(VoiceCallState state) {
    final signature = <Object?>[
      state.peerId,
      state.callId,
      state.sessionEpoch,
      state.phase,
      state.mediaMode,
      state.isOutgoing,
      state.isMuted,
      state.isRemoteMuted,
      state.isCameraMuted,
      state.isRemoteCameraMuted,
      state.isDeafened,
      state.hasLocalVideo,
      state.hasRemoteVideo,
      state.videoFirstFrameTimedOut,
      state.mediaReconnecting,
      state.failureReason,
      state.detail,
      state.error?.toString(),
    ].join('|');
    if (_lastLoggedVoiceCallStateSignature == signature) {
      return;
    }
    _lastLoggedVoiceCallStateSignature = signature;
    final severity = switch (state.phase) {
      VoiceCallPhase.failed => 'error',
      VoiceCallPhase.ending => 'warning',
      _ => 'info',
    };
    _recordRuntimeEvent(
      category: 'call',
      name: 'state_changed',
      severity: severity,
      message: state.detail,
      context: _voiceCallEventContext(state),
    );
    _recordPeerUiStateSplitIfNeeded(state);
  }

  void _recordPeerUiStateSplitIfNeeded(VoiceCallState state) {
    VoiceCallSessionStateCoordinator.instance.recordPeerUiStateSplitIfNeeded(
      state,
      getSession: (peerId) => brain?.getSession(peerId),
      lastLoggedSignature: _lastLoggedPeerUiSplitSignature,
      setLastLoggedSignature: (signature) {
        _lastLoggedPeerUiSplitSignature = signature;
      },
      recordRuntimeEvent: _recordRuntimeEvent,
    );
  }

  String _newVoiceCallId(String peerId) {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '${_normalizedUsername(selfIdentity.username)}:$peerId:$now';
  }

  // ---------------------------------------------------------------------------
  // Error classification — delegated to VoiceCallErrorCoordinator
  // ---------------------------------------------------------------------------

  CallSignalingFailureSnapshot? _voiceCallSignalingFailureSnapshotForError(
    Object error, {
    String? peerId,
  }) => VoiceCallErrorCoordinator.instance.signalingFailureSnapshotForError(
    error,
    peerId: peerId,
  );

  bool _shouldRetryTransientVoiceCreateFailure(
    Object error,
    CallRetryDecision? decision,
  ) => VoiceCallErrorCoordinator.instance.shouldRetryTransientCreateFailure(
    error,
    decision,
  );

  Map<String, Object?> _voiceCallLockDiagnostics({
    required String peerId,
    required String callId,
    required int sessionEpoch,
    String? lockClaimResult,
    CallRetryDecision? retryDecision,
    CallSignalingFailureSnapshot? retrySnapshot,
  }) {
    final caller = _normalizedUsername(selfIdentity.username);
    final callee = _normalizedUsername(peerId);
    final pairId = voiceCallPairId(caller, callee);
    final message = retrySnapshot?.message ?? '';
    final busyUser = VoiceCallErrorCoordinator.instance.busyUser(message);
    final lockPath = busyUser == null
        ? 'activeVoicePairs/$pairId'
        : 'activeVoiceUsers/$busyUser';
    final timestampRepair =
        message.contains('timestamp') ||
        message.contains('timestamps are invalid');
    return <String, Object?>{
      'lockClaimResult': lockClaimResult ?? retryDecision?.kind.name,
      'lockPath': lockPath,
      'pairId': pairId,
      'callerUserLock': caller,
      'calleeUserLock': callee,
      'lockCallId': null,
      'lockExpiresAt': sessionEpoch + _voiceCallExpiry.inMilliseconds,
      'lockWasReclaimed': retrySnapshot?.lockWasReclaimed ?? false,
      'terminalRoomWasCleaned': retrySnapshot?.terminalRoomWasCleaned ?? false,
      'corruptRoomWasRepaired': retrySnapshot?.corruptRoomWasRepaired ?? false,
      'timestampRepair': timestampRepair,
    };
  }

  VoiceCallFailureReason? _voiceCallFailureReasonForRetryDecision(
    CallRetryDecision? decision,
  ) => VoiceCallErrorCoordinator.instance.failureReasonForRetryDecision(
    decision,
  );

  String? _voiceCallFailureDetailForRetryDecision(
    CallRetryDecision? decision,
  ) => VoiceCallErrorCoordinator.instance.failureDetailForRetryDecision(
    decision,
  );

  String _voiceFailureTaxonomy({
    required String failureCode,
    required String userMessage,
    required String nativeError,
  }) => VoiceCallErrorCoordinator.instance.failureTaxonomy(
    failureCode: failureCode,
    userMessage: userMessage,
    nativeError: nativeError,
  );

  VoiceCallFailureReason? _voiceCallFailureReasonForError(Object error) =>
      VoiceCallErrorCoordinator.instance.failureReasonForError(error);

  String? _voiceCallFailureDetailForError(Object error) =>
      VoiceCallErrorCoordinator.instance.failureDetailForError(
        error,
        currentPeerId: _voiceCallState.peerId,
        selfUsername: selfIdentity.username,
      );

  String _normalizedVoiceCallErrorText(Object error) =>
      VoiceCallErrorCoordinator.instance.normalizeErrorText(error);

  String _voiceCallErrorMessage(Object error) =>
      VoiceCallErrorCoordinator.instance.errorMessage(
        error,
        currentPeerId: _voiceCallState.peerId,
        selfUsername: selfIdentity.username,
      );

  VoiceCallFailureReason? _localAudioFailureReason(Object error) =>
      VoiceCallErrorCoordinator.instance.localMediaFailureReason(error);

  String? _localAudioFailureDetail(Object error) =>
      VoiceCallErrorCoordinator.instance.localMediaFailureDetail(error);
}
