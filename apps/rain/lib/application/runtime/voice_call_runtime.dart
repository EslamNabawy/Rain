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

final class _CallStartPresenceSnapshot {
  const _CallStartPresenceSnapshot({
    required this.peerOnline,
    required this.diagnostics,
  });

  final bool? peerOnline;
  final Map<String, Object?> diagnostics;
}

extension VoiceCallRuntime on RainRuntimeController {
  static const CallTerminalWritePolicy _voiceTerminalWritePolicy =
      CallTerminalWritePolicy();
  static const String _voiceCallFailedReasonCode = 'failed';
  static const String _voiceCallBusyReasonCode = 'busy';
  static const String _voiceCallRejectedReasonCode = 'rejected';
  static const String _voiceCallSignalingFailedReasonCode = 'signalingFailed';
  static const String _voiceCallNetworkLostReasonCode = 'networkLost';
  static const String _voiceCallExpiredReasonCode = 'expired';
  static const String _voiceCallRingingTimeoutReasonCode = 'ringingTimeout';
  static const String _voiceCallIceTimeoutReasonCode = 'iceTimeout';
  static const String _voiceCallNoRemoteAudioReasonCode = 'noRemoteAudio';
  static const String _voiceCallVideoRendererFailedReasonCode =
      'videoRendererFailed';
  static const String _voiceCallVideoFirstFrameTimeoutReasonCode =
      'videoFirstFrameTimeout';
  static const String _voiceCallMicrophoneDeniedReasonCode = 'microphoneDenied';
  static const String _voiceCallCameraDeniedReasonCode = 'cameraDenied';
  static const String _voiceCallMicrophonePermissionRequired =
      'Microphone permission required.';
  static const String _voiceCallRemoteMicrophonePermissionRequired =
      'Peer microphone permission required.';
  static const String _voiceCallCameraPermissionRequired =
      'Camera permission required.';
  static const String _voiceCallRemoteCameraPermissionRequired =
      'Peer camera permission required.';
  static const String _voiceCallFileTransferRequired =
      'Finish the active file transfer first.';
  static const String _voiceCallRejected = 'Call declined.';
  static const String _voiceCallNetworkLost =
      'Network connection lost. Call ended.';
  static const String _voiceCallSignalingFailed =
      'Call setup failed. Try again.';
  static const String _voiceCallTimedOut = 'Call timed out.';
  static const String _voiceCallMediaFailed =
      'Call media could not connect. Try again.';
  static const String _voiceCallVideoFailed =
      'Video could not connect. Try again.';
  static const String _voiceCallVideoBackgrounded =
      'Video call ended because the app went to background.';
  static const String _voiceCallAudioRouteUnavailable =
      'Audio route unavailable.';
  static const String _voiceCallReconnecting =
      'Peer connection interrupted. Reconnecting...';
  static bool get _legacyControlChannelVoiceSignalingFrozen => true;
  static const Duration _voiceCallExpiry = Duration(minutes: 2);

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
    final decision = RuntimeInteractionGuard.canStartCall(
      peerId: peerId,
      mediaMode: mediaMode,
      voiceCallState: _voiceCallState,
      peerOnline: presence.peerOnline,
      activeTransfer: await _firstActiveTransfer(),
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
    await _assertVoiceCallPeerIsFriend(peerId);

    await _disposeCurrentVoiceCallSession();
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
    } catch (error) {
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

  Future<void> acceptVoiceCall() async {
    final current = _voiceCallState;
    _recordRuntimeEvent(
      category: 'call',
      name: 'accept_requested',
      context: _voiceCallEventContext(current),
    );
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

    try {
      await session.acceptIncoming();
    } catch (error) {
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
    if (_legacyControlChannelVoiceSignalingFrozen) {
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
    return !current.isOutgoing &&
        current.phase == VoiceCallPhase.incomingRinging;
  }

  Future<void> _replaceStaleVoiceCallForRetry(VoiceCallState current) async {
    final peerId = current.peerId;
    if (peerId == null) {
      await _disposeCurrentVoiceCallSession();
      _setVoiceCallState(const VoiceCallState.idle());
      return;
    }

    final session = _voiceCallSession;
    if (session != null && current.callId == session.callId) {
      await session.hangUp(reason: 'Replaced by newer voice call invite.');
    } else if (current.callId != null) {
      await _sendVoiceFrame(
        peerId,
        VoiceCallFrameType.hangup,
        callId: current.callId!,
        reason: 'Replaced by newer voice call invite.',
        bestEffort: true,
      );
    }
    await _disposeCurrentVoiceCallSession();
    _setVoiceCallState(const VoiceCallState.idle());
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
    _requireVoiceSignalingAdapter();

    await _disposeCurrentVoiceCallSession();
    final media = switch (mediaMode) {
      CallMediaMode.audio => await manager.createVoiceMediaConnection(peerId),
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
    _watchFirebaseVoiceCall(
      session: session,
      peerId: peerId,
      isOutgoing: isOutgoing,
    );
    return session;
  }

  void _watchFirebaseVoiceCall({
    required VoiceCallSession session,
    required String peerId,
    required bool isOutgoing,
  }) {
    final voiceAdapter = _requireVoiceSignalingAdapter();
    final remoteRole = isOutgoing ? VoiceCallRole.callee : VoiceCallRole.caller;
    _recordRuntimeEvent(
      category: 'call',
      name: 'firebase_watch_started',
      context: <String, Object?>{
        'peerId': peerId,
        'callId': session.callId,
        'sessionEpoch': session.sessionEpoch,
        'isOutgoing': isOutgoing,
        'remoteRole': remoteRole.name,
      },
    );

    _voiceSignalingSubscriptions.add(
      voiceAdapter
          .watchCall(session.callId)
          .listen(
            (VoiceCallRoom? room) async {
              if (room == null || !_isLiveVoiceCallSession(session)) {
                return;
              }
              _recordRuntimeEvent(
                category: 'call',
                name: 'firebase_room_update',
                context: <String, Object?>{
                  'peerId': peerId,
                  'callId': room.callId,
                  'sessionEpoch': session.sessionEpoch,
                  'status': room.status.name,
                  'reasonCode': room.reasonCode,
                  'endedBy': room.endedBy,
                  'mediaMode': room.mediaMode.name,
                },
              );
              await _handleFirebaseVoiceRoomUpdate(
                session: session,
                room: room,
                peerId: peerId,
                isOutgoing: isOutgoing,
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              _recordVoiceSignalingError(error, stackTrace);
            },
          ),
    );
    _voiceSignalingSubscriptions.add(
      voiceAdapter
          .watchVoiceOffer(session.callId)
          .listen(
            (VoiceSignalingEnvelope envelope) async {
              await _handleFirebaseVoiceEnvelope(
                session: session,
                peerId: peerId,
                envelope: envelope,
                purpose: SignalingCipher.offerPurpose,
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              _recordVoiceSignalingError(error, stackTrace);
            },
          ),
    );
    _voiceSignalingSubscriptions.add(
      voiceAdapter
          .watchVoiceAnswer(session.callId)
          .listen(
            (VoiceSignalingEnvelope envelope) async {
              await _handleFirebaseVoiceEnvelope(
                session: session,
                peerId: peerId,
                envelope: envelope,
                purpose: SignalingCipher.answerPurpose,
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              _recordVoiceSignalingError(error, stackTrace);
            },
          ),
    );
    _voiceSignalingSubscriptions.add(
      voiceAdapter
          .watchIceCandidates(callId: session.callId, role: remoteRole)
          .listen(
            (VoiceCallIceCandidateRecord record) async {
              await _handleFirebaseVoiceEnvelope(
                session: session,
                peerId: peerId,
                envelope: record.envelope,
                purpose: _voiceIcePurpose(remoteRole),
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              _recordVoiceSignalingError(error, stackTrace);
            },
          ),
    );
  }

  Future<void> _handleFirebaseVoiceRoomUpdate({
    required VoiceCallSession session,
    required VoiceCallRoom room,
    required String peerId,
    required bool isOutgoing,
  }) async {
    if (!_isLiveVoiceCallSession(session) || room.callId != session.callId) {
      return;
    }
    if (room.createdAt != session.sessionEpoch) {
      _recordLateVoiceFrame(
        session,
        'ignored room update for stale epoch ${room.createdAt}',
      );
      return;
    }
    final localUsername = _normalizedUsername(selfIdentity.username);
    final remoteMuted = room.muted[peerId];
    if (remoteMuted != null && _voiceCallState.isRemoteMuted != remoteMuted) {
      _setVoiceCallState(
        _voiceCallState.copyWith(
          isRemoteMuted: remoteMuted,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    final remoteCameraMuted = room.cameraMuted[peerId];
    if (remoteCameraMuted != null &&
        _voiceCallState.isRemoteCameraMuted != remoteCameraMuted) {
      _setVoiceCallState(
        _voiceCallState.copyWith(
          isRemoteCameraMuted: remoteCameraMuted,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    switch (room.status) {
      case VoiceCallSignalingStatus.ringing:
      case VoiceCallSignalingStatus.negotiating:
      case VoiceCallSignalingStatus.connected:
        break;
      case VoiceCallSignalingStatus.accepted:
        if (isOutgoing) {
          await session.handleFrame(
            VoiceCallFrame(
              type: VoiceCallFrameType.accept,
              callId: room.callId,
              from: peerId,
              to: localUsername,
              sentAt: room.acceptedAt ?? room.updatedAt,
              seq: 1,
              sessionEpoch: room.createdAt,
            ),
          );
        }
        break;
      case VoiceCallSignalingStatus.ended:
      case VoiceCallSignalingStatus.failed:
      case VoiceCallSignalingStatus.expired:
        await _reconcileTerminalVoiceRoom(
          session: session,
          room: room,
          peerId: peerId,
        );
        break;
    }
  }

  Future<void> _reconcileTerminalVoiceRoom({
    required VoiceCallSession session,
    required VoiceCallRoom room,
    required String peerId,
  }) async {
    if (!room.status.isTerminal || !_isLiveVoiceCallSession(session)) {
      return;
    }
    _latchTerminalVoiceCallSession(session);
    final current = _voiceCallState;
    if (current.callId != room.callId ||
        current.sessionEpoch != room.createdAt ||
        current.phase == VoiceCallPhase.idle ||
        current.phase == VoiceCallPhase.failed) {
      return;
    }
    final localUsername = _normalizedUsername(selfIdentity.username);
    final endedByLocal = room.endedBy == localUsername;
    final detail = _terminalVoiceCallDetailForRoom(room, localUsername);
    final failureReason = _terminalVoiceCallFailureReasonForRoom(room);
    if (endedByLocal && current.phase == VoiceCallPhase.ending) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'voice_terminal_room_local_echo_ignored',
        severity: 'info',
        message: 'Local terminal Firebase room echoed during local hangup.',
        context: <String, Object?>{
          ..._voiceCallEventContext(current),
          'status': room.status.name,
          'endedBy': room.endedBy,
          'reasonCode': room.reasonCode,
        },
      );
      return;
    }
    _recordRuntimeEvent(
      category: 'call',
      name: endedByLocal
          ? 'voice_terminal_room_forced_reconcile'
          : 'voice_remote_terminal_room_reconciled',
      severity: endedByLocal ? 'warning' : 'info',
      message: endedByLocal
          ? 'Terminal Firebase room left the local voice session live.'
          : 'Remote terminal Firebase room ended the local voice session.',
      context: <String, Object?>{
        ..._voiceCallEventContext(current),
        'status': room.status.name,
        'endedBy': room.endedBy,
        'reasonCode': room.reasonCode,
      },
    );
    await _settleVoiceCallAfterTerminalRace(
      session,
      detail: detail,
      failureReason: failureReason,
    );
  }

  String _terminalVoiceCallDetailForRoom(VoiceCallRoom room, String localUser) {
    if (room.status == VoiceCallSignalingStatus.ended &&
        room.endedBy != null &&
        room.endedBy != localUser) {
      return 'Peer ended the call.';
    }
    if (room.status == VoiceCallSignalingStatus.ended) {
      return room.reason ?? 'Call ended.';
    }
    final roomReason = room.reason?.trim();
    if (roomReason != null &&
        roomReason.isNotEmpty &&
        !_isRemoteMediaPermissionCode(room.reasonCode)) {
      return roomReason;
    }
    final syntheticState = _terminalVoiceCallSessionStateForRoom(room);
    return _voiceCallDetailForSessionState(syntheticState) ??
        room.reason ??
        _terminalVoiceCallReason(room.status) ??
        _voiceCallMediaFailed;
  }

  VoiceCallFailureReason? _terminalVoiceCallFailureReasonForRoom(
    VoiceCallRoom room,
  ) {
    if (room.status == VoiceCallSignalingStatus.ended) {
      return null;
    }
    return _voiceCallFailureReasonForSessionState(
          _terminalVoiceCallSessionStateForRoom(room),
        ) ??
        VoiceCallFailureReason.mediaConnectionFailed;
  }

  VoiceCallSessionState _terminalVoiceCallSessionStateForRoom(
    VoiceCallRoom room,
  ) {
    return VoiceCallSessionState(
      phase: VoiceCallSessionPhase.failed,
      updatedAt: room.endedAt ?? room.updatedAt,
      mediaMode: room.mediaMode,
      detail: room.reason ?? _terminalVoiceCallReason(room.status),
      reasonCode:
          room.reasonCode ??
          switch (room.status) {
            VoiceCallSignalingStatus.expired => _voiceCallExpiredReasonCode,
            VoiceCallSignalingStatus.failed => _voiceCallFailedReasonCode,
            _ => null,
          },
    );
  }

  String? _terminalVoiceCallReason(VoiceCallSignalingStatus status) {
    return switch (status) {
      VoiceCallSignalingStatus.expired => _voiceCallTimedOut,
      _ => null,
    };
  }

  String? _voiceCallReasonCodeForFailure(VoiceCallFailureReason? reason) {
    return switch (reason) {
      null => null,
      VoiceCallFailureReason.microphoneDenied ||
      VoiceCallFailureReason.remoteMicrophoneDenied =>
        _voiceCallMicrophoneDeniedReasonCode,
      VoiceCallFailureReason.cameraDenied ||
      VoiceCallFailureReason.remoteCameraDenied =>
        _voiceCallCameraDeniedReasonCode,
      VoiceCallFailureReason.peerBusy ||
      VoiceCallFailureReason.fileTransferActive => _voiceCallBusyReasonCode,
      VoiceCallFailureReason.rejected => _voiceCallRejectedReasonCode,
      VoiceCallFailureReason.networkLost => _voiceCallNetworkLostReasonCode,
      VoiceCallFailureReason.signalingFailed =>
        _voiceCallSignalingFailedReasonCode,
      VoiceCallFailureReason.expired => _voiceCallExpiredReasonCode,
      VoiceCallFailureReason.ringingTimeout =>
        _voiceCallRingingTimeoutReasonCode,
      VoiceCallFailureReason.mediaIceTimeout => _voiceCallIceTimeoutReasonCode,
      VoiceCallFailureReason.mediaNoRemoteAudio =>
        _voiceCallNoRemoteAudioReasonCode,
      VoiceCallFailureReason.videoRendererFailed =>
        _voiceCallVideoRendererFailedReasonCode,
      VoiceCallFailureReason.videoFirstFrameTimeout =>
        _voiceCallVideoFirstFrameTimeoutReasonCode,
      VoiceCallFailureReason.mediaConnectionFailed =>
        _voiceCallFailedReasonCode,
    };
  }

  Future<void> _handleFirebaseVoiceEnvelope({
    required VoiceCallSession session,
    required String peerId,
    required VoiceSignalingEnvelope envelope,
    required String purpose,
  }) async {
    if (!_isLiveVoiceCallSession(session)) {
      return;
    }
    try {
      final frame = await _decryptVoiceFrame(
        callId: session.callId,
        envelope: envelope,
        purpose: purpose,
      );
      _recordRuntimeEvent(
        category: 'call',
        name: 'firebase_frame_received',
        context: <String, Object?>{
          ..._voiceFrameEventContext(peerId, frame),
          'purpose': purpose,
        },
      );
      if (!_isLiveVoiceCallSession(session)) {
        _recordLateVoiceFrame(
          session,
          'late decrypted ${frame.type.name} frame after call moved on',
        );
        return;
      }
      if (frame.callId != session.callId ||
          frame.sessionEpoch != session.sessionEpoch) {
        _recordLateVoiceFrame(
          session,
          'late ${frame.type.name} frame for '
          '${frame.callId}/${frame.sessionEpoch}',
        );
        return;
      }
      if (_normalizedUsername(frame.from) ==
          _normalizedUsername(selfIdentity.username)) {
        return;
      }
      if (_normalizedUsername(frame.from) != _normalizedUsername(peerId)) {
        return;
      }
      await session.handleFrame(frame);
    } catch (error, stackTrace) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'firebase_frame_failed',
        severity: 'error',
        message: error.toString(),
        context: <String, Object?>{
          'peerId': peerId,
          'callId': session.callId,
          'sessionEpoch': session.sessionEpoch,
          'purpose': purpose,
        },
      );
      _recordVoiceSignalingError(error, stackTrace);
      if (!_isLiveVoiceCallSession(session)) {
        _recordLateVoiceFrame(
          session,
          'ignored signaling error after call moved on: $error',
        );
        return;
      }
      await _failVoiceCall(
        error,
        failureReason: VoiceCallFailureReason.mediaConnectionFailed,
        detail: _voiceCallMediaFailed,
      );
    }
  }

  Future<void> _sendVoiceFrameObject(
    String peerId,
    VoiceCallFrame frame,
  ) async {
    final voiceAdapter = _requireVoiceSignalingAdapter();
    final localUsername = _normalizedUsername(selfIdentity.username);
    final now = DateTime.now().millisecondsSinceEpoch;
    _recordRuntimeEvent(
      category: 'call',
      name: 'firebase_frame_send_started',
      context: _voiceFrameEventContext(peerId, frame),
    );
    switch (frame.type) {
      case VoiceCallFrameType.invite:
        final callee = _normalizedUsername(peerId);
        final lockContext = _voiceCallLockDiagnostics(
          peerId: callee,
          callId: frame.callId,
          sessionEpoch: frame.sessionEpoch,
          lockClaimResult: 'started',
        );
        _recordRuntimeEvent(
          category: 'call',
          name: 'voice_lock_claim_started',
          context: <String, Object?>{
            ..._voiceFrameEventContext(peerId, frame),
            ...lockContext,
          },
        );
        try {
          await voiceAdapter.createOutgoingCall(
            callId: frame.callId,
            caller: localUsername,
            callee: callee,
            createdAt: frame.sessionEpoch,
            expiresAt: frame.sessionEpoch + _voiceCallExpiry.inMilliseconds,
            mediaMode: frame.mediaMode,
          );
        } catch (error) {
          final retrySnapshot = _voiceCallSignalingFailureSnapshotForError(
            error,
            peerId: callee,
          );
          final retryDecision = retrySnapshot == null
              ? null
              : CallRetryPolicy.classifySignalingFailure(retrySnapshot);
          final failedLockContext = _voiceCallLockDiagnostics(
            peerId: callee,
            callId: frame.callId,
            sessionEpoch: frame.sessionEpoch,
            retryDecision: retryDecision,
            retrySnapshot: retrySnapshot,
          );
          final eventContext = <String, Object?>{
            ..._voiceFrameEventContext(peerId, frame),
            ...failedLockContext,
            if (retryDecision != null)
              'canRetryImmediately': retryDecision.canRetryImmediately,
          };
          if (retryDecision?.kind == CallRetryDecisionKind.cleanedStaleState) {
            _recordRuntimeEvent(
              category: 'call',
              name: 'voice_lock_reclaim_completed',
              severity: 'warning',
              message: retryDecision?.userMessage,
              context: eventContext,
            );
            _recordRuntimeEvent(
              category: 'call',
              name: 'stale_voice_lock_repaired',
              severity: 'warning',
              message: retryDecision?.userMessage,
              context: eventContext,
            );
            if (failedLockContext['timestampRepair'] == true) {
              _recordRuntimeEvent(
                category: 'call',
                name: 'voice_room_timestamp_repaired',
                severity: 'warning',
                message: retryDecision?.userMessage,
                context: eventContext,
              );
            }
            if (retryDecision?.canRetryImmediately == true) {
              try {
                await voiceAdapter.createOutgoingCall(
                  callId: frame.callId,
                  caller: localUsername,
                  callee: callee,
                  createdAt: frame.sessionEpoch,
                  expiresAt:
                      frame.sessionEpoch + _voiceCallExpiry.inMilliseconds,
                  mediaMode: frame.mediaMode,
                );
                _recordRuntimeEvent(
                  category: 'call',
                  name: 'voice_lock_claim_retried',
                  severity: 'info',
                  message: retryDecision?.userMessage,
                  context: <String, Object?>{
                    ...eventContext,
                    'retryResult': 'claimed',
                  },
                );
                return;
              } catch (retryError, retryStackTrace) {
                _recordRuntimeEvent(
                  category: 'call',
                  name: 'voice_lock_claim_retry_failed',
                  severity: 'warning',
                  message: retryError.toString(),
                  context: <String, Object?>{
                    ...eventContext,
                    'retryResult': 'failed',
                  },
                );
                Error.throwWithStackTrace(retryError, retryStackTrace);
              }
            }
          } else if (retryDecision?.kind ==
              CallRetryDecisionKind.cleanupInProgress) {
            _recordRuntimeEvent(
              category: 'call',
              name: 'voice_lock_reclaim_started',
              severity: 'warning',
              message: retryDecision?.userMessage,
              context: eventContext,
            );
          } else if (retryDecision?.kind == CallRetryDecisionKind.peerOffline) {
            final presenceMessage =
                (retryDecision?.userMessage ?? error.toString()).toLowerCase();
            final presenceEventName =
                presenceMessage.contains('could not confirm') ||
                    presenceMessage.contains('presence unknown')
                ? 'call_start_presence_unknown'
                : 'call_start_blocked_offline';
            _recordRuntimeEvent(
              category: 'call',
              name: presenceEventName,
              severity: 'warning',
              message: retryDecision?.userMessage,
              context: <String, Object?>{
                ...eventContext,
                'presenceSource': 'signaling',
              },
            );
            _recordRuntimeEvent(
              category: 'call',
              name: 'voice_lock_claim_blocked',
              severity: 'warning',
              message: retryDecision?.userMessage ?? error.toString(),
              context: eventContext,
            );
          } else if (retryDecision?.kind == CallRetryDecisionKind.peerBusy) {
            _recordRuntimeEvent(
              category: 'call',
              name: 'voice_real_busy_lock',
              severity: 'warning',
              message: retryDecision?.userMessage,
              context: eventContext,
            );
            _recordRuntimeEvent(
              category: 'call',
              name: 'voice_lock_claim_blocked',
              severity: 'warning',
              message: retryDecision?.userMessage ?? error.toString(),
              context: eventContext,
            );
          } else {
            _recordRuntimeEvent(
              category: 'call',
              name: 'voice_lock_claim_blocked',
              severity: 'warning',
              message: retryDecision?.userMessage ?? error.toString(),
              context: eventContext,
            );
          }
          rethrow;
        }
        break;
      case VoiceCallFrameType.accept:
        await voiceAdapter.acceptCall(
          callId: frame.callId,
          callee: localUsername,
          acceptedAt: now,
        );
        break;
      case VoiceCallFrameType.reject:
      case VoiceCallFrameType.busy:
        await voiceAdapter.endCall(
          callId: frame.callId,
          username: localUsername,
          status: VoiceCallSignalingStatus.failed,
          endedAt: now,
          reasonCode:
              frame.reasonCode ??
              (frame.type == VoiceCallFrameType.busy
                  ? _voiceCallBusyReasonCode
                  : _voiceCallRejectedReasonCode),
          reason: frame.reason,
        );
        break;
      case VoiceCallFrameType.hangup:
        final existingRoom = await voiceAdapter.fetchCall(frame.callId);
        if (existingRoom?.status.isTerminal == true) {
          _recordRuntimeEvent(
            category: 'call',
            name: 'voice_late_hangup_frame_ignored',
            severity: 'info',
            message: 'Late hangup frame ignored after terminal room state.',
            context: <String, Object?>{
              ..._voiceFrameEventContext(peerId, frame),
              'status': existingRoom?.status.name,
              'endedBy': existingRoom?.endedBy,
            },
          );
          break;
        }
        await voiceAdapter.endCall(
          callId: frame.callId,
          username: localUsername,
          status: frame.reasonCode == null
              ? VoiceCallSignalingStatus.ended
              : VoiceCallSignalingStatus.failed,
          endedAt: now,
          reasonCode: frame.reasonCode,
          reason: frame.reason,
        );
        break;
      case VoiceCallFrameType.offer:
        await voiceAdapter.writeVoiceOffer(
          callId: frame.callId,
          caller: localUsername,
          offer: await _encryptVoiceFrame(
            frame,
            purpose: SignalingCipher.offerPurpose,
            maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
          ),
          updatedAt: now,
        );
        break;
      case VoiceCallFrameType.answer:
        await voiceAdapter.writeVoiceAnswer(
          callId: frame.callId,
          callee: localUsername,
          answer: await _encryptVoiceFrame(
            frame,
            purpose: SignalingCipher.answerPurpose,
            maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
          ),
          updatedAt: now,
        );
        break;
      case VoiceCallFrameType.candidate:
        final localRole = _localVoiceCallRole();
        await voiceAdapter.writeIceCandidate(
          callId: frame.callId,
          username: localUsername,
          role: localRole,
          candidate: await _encryptVoiceFrame(
            frame,
            purpose: _voiceIcePurpose(localRole),
            maxCiphertextLength: VoiceSignalingEnvelope.maxIceCiphertextLength,
          ),
          createdAt: now,
        );
        break;
      case VoiceCallFrameType.mute:
        if (frame.muted != null) {
          await voiceAdapter.setMuted(
            callId: frame.callId,
            username: localUsername,
            muted: frame.muted!,
            updatedAt: now,
          );
        }
        if (frame.cameraMuted != null) {
          await voiceAdapter.setCameraMuted(
            callId: frame.callId,
            username: localUsername,
            cameraMuted: frame.cameraMuted!,
            updatedAt: now,
          );
        }
        break;
    }
    _recordRuntimeEvent(
      category: 'call',
      name: 'firebase_frame_send_completed',
      context: _voiceFrameEventContext(peerId, frame),
    );
  }

  void _applyVoiceSessionState(
    VoiceCallSession session,
    VoiceCallSessionState sessionState, {
    required bool isOutgoing,
  }) {
    if (!_isLiveVoiceCallSession(session)) {
      return;
    }
    if (_isTerminalVoiceCallSessionLatched(session) &&
        sessionState.phase != VoiceCallSessionPhase.idle) {
      _recordLateVoiceFrame(
        session,
        'ignored ${sessionState.phase.name} state after terminal room',
      );
      return;
    }
    final mappedPhase = _mapVoiceCallSessionPhase(sessionState.phase);
    if (_voiceCallState.phase == VoiceCallPhase.failed &&
        _voiceCallState.callId == session.callId &&
        _voiceCallState.sessionEpoch == session.sessionEpoch &&
        mappedPhase == VoiceCallPhase.active) {
      _recordLateVoiceFrame(session, 'ignored active state after failure');
      return;
    }
    final previous = _voiceCallState;
    final isSameCall =
        previous.callId == session.callId &&
        previous.sessionEpoch == session.sessionEpoch;
    final now = sessionState.updatedAt;
    final error = sessionState.error;
    final failureReason = _voiceCallFailureReasonForSessionState(sessionState);
    final detail = _voiceCallDetailForSessionState(sessionState);
    final startedAt = mappedPhase == VoiceCallPhase.active
        ? (isSameCall ? previous.startedAt : null) ?? now
        : isSameCall
        ? previous.startedAt
        : null;
    final keepsLocalAudioControls = mappedPhase == VoiceCallPhase.active;
    final mediaReconnecting =
        mappedPhase == VoiceCallPhase.active && sessionState.mediaReconnecting;

    if (mappedPhase == VoiceCallPhase.idle) {
      _setVoiceCallState(const VoiceCallState.idle());
      unawaited(_disposeVoiceCallSession(session));
      return;
    }

    _setVoiceCallState(
      VoiceCallState(
        phase: mappedPhase,
        peerId: session.remotePeerId,
        callId: session.callId,
        sessionEpoch: session.sessionEpoch,
        mediaMode: sessionState.mediaMode,
        isOutgoing: isOutgoing,
        isMuted: isSameCall && previous.isMuted,
        isCameraMuted: isSameCall && previous.isCameraMuted,
        isDeafened:
            isSameCall && keepsLocalAudioControls && previous.isDeafened,
        isRemoteMuted: isSameCall && previous.isRemoteMuted,
        isRemoteCameraMuted: isSameCall && previous.isRemoteCameraMuted,
        hasLocalVideo: isSameCall && previous.hasLocalVideo,
        hasRemoteVideo: isSameCall && previous.hasRemoteVideo,
        videoFirstFrameTimedOut: isSameCall && previous.videoFirstFrameTimedOut,
        mediaReconnecting: mediaReconnecting,
        reconnectingSince: mediaReconnecting
            ? sessionState.reconnectingSince ?? previous.reconnectingSince
            : null,
        outputRoute: isSameCall && keepsLocalAudioControls
            ? previous.outputRoute
            : VoiceCallOutputRoute.systemDefault,
        outputRouteDeviceId: isSameCall && keepsLocalAudioControls
            ? previous.outputRouteDeviceId
            : null,
        outputRouteLabel: isSameCall && keepsLocalAudioControls
            ? previous.outputRouteLabel
            : null,
        outputRouteWarning: isSameCall && keepsLocalAudioControls
            ? previous.outputRouteWarning
            : null,
        startedAt: startedAt,
        updatedAt: now,
        detail: detail,
        error: error,
        failureReason: failureReason,
        audioLevel: VoiceAudioLevel.fromMedia(sessionState.audioLevel),
      ),
    );

    if (mappedPhase == VoiceCallPhase.active) {
      final voiceAdapter = voiceSignalingAdapter;
      if (voiceAdapter != null) {
        unawaited(
          voiceAdapter
              .markConnected(
                callId: session.callId,
                username: _normalizedUsername(selfIdentity.username),
                connectedAt: now,
              )
              .catchError((Object error, StackTrace stackTrace) {
                if (_isVoiceTerminalAlreadyClosedError(error)) {
                  _recordTerminalAlreadyClosed(
                    error,
                    name: 'voice_mark_connected_after_terminal',
                    context: <String, Object?>{
                      ..._voiceCallEventContext(_voiceCallState),
                      'callId': session.callId,
                      'sessionEpoch': session.sessionEpoch,
                    },
                  );
                  unawaited(
                    _settleVoiceCallAfterTerminalRace(
                      session,
                      detail: 'Call ended.',
                    ),
                  );
                  return;
                }
                _recordVoiceSignalingError(error, stackTrace);
              }),
        );
      }
    }

    if (mappedPhase == VoiceCallPhase.failed) {
      unawaited(
        _endVoiceCallInSignaling(
          callId: session.callId,
          status: VoiceCallSignalingStatus.failed,
          reason: detail ?? sessionState.detail ?? _voiceCallMediaFailed,
          reasonCode:
              sessionState.reasonCode ??
              _voiceCallReasonCodeForFailure(failureReason) ??
              _voiceCallFailedReasonCode,
          bestEffort: true,
        ),
      );
      _recordVoiceCallSessionFailure(
        session,
        sessionState,
        isOutgoing: isOutgoing,
      );
      unawaited(_disposeVoiceCallSession(session));
    }
  }

  VoiceCallPhase _mapVoiceCallSessionPhase(VoiceCallSessionPhase phase) {
    return switch (phase) {
      VoiceCallSessionPhase.idle => VoiceCallPhase.idle,
      VoiceCallSessionPhase.preflightingMic ||
      VoiceCallSessionPhase.creatingMedia ||
      VoiceCallSessionPhase.connectingMedia => VoiceCallPhase.connectingMedia,
      VoiceCallSessionPhase.outgoingRinging => VoiceCallPhase.outgoingRinging,
      VoiceCallSessionPhase.incomingRinging => VoiceCallPhase.incomingRinging,
      VoiceCallSessionPhase.active => VoiceCallPhase.active,
      VoiceCallSessionPhase.ending => VoiceCallPhase.ending,
      VoiceCallSessionPhase.failed => VoiceCallPhase.failed,
    };
  }

  VoiceCallFailureReason? _voiceCallFailureReasonForSessionState(
    VoiceCallSessionState state,
  ) {
    final error = state.error;
    if (error != null) {
      final localFailure = _localAudioFailureReason(error);
      if (localFailure != null) {
        return localFailure;
      }
    }
    if (state.reasonCode == _voiceCallMicrophoneDeniedReasonCode) {
      return VoiceCallFailureReason.remoteMicrophoneDenied;
    }
    if (state.reasonCode == _voiceCallCameraDeniedReasonCode) {
      return VoiceCallFailureReason.remoteCameraDenied;
    }
    if (state.reasonCode == _voiceCallBusyReasonCode ||
        state.detail == 'Peer is busy.') {
      return VoiceCallFailureReason.peerBusy;
    }
    if (state.reasonCode == _voiceCallRejectedReasonCode ||
        state.detail == _voiceCallRejected ||
        state.detail == 'Rejected.') {
      return VoiceCallFailureReason.rejected;
    }
    if (state.reasonCode == _voiceCallNetworkLostReasonCode ||
        state.detail == _voiceCallNetworkLost) {
      return VoiceCallFailureReason.networkLost;
    }
    if (state.reasonCode == _voiceCallSignalingFailedReasonCode ||
        state.detail == _voiceCallSignalingFailed) {
      return VoiceCallFailureReason.signalingFailed;
    }
    if (state.reasonCode == _voiceCallExpiredReasonCode ||
        state.detail == _voiceCallTimedOut) {
      return VoiceCallFailureReason.expired;
    }
    if (state.reasonCode == _voiceCallRingingTimeoutReasonCode ||
        state.detail == _voiceCallTimedOut ||
        state.detail == 'Call timed out.' ||
        state.detail == 'Call timed out while ringing.') {
      return VoiceCallFailureReason.ringingTimeout;
    }
    if (state.reasonCode == _voiceCallIceTimeoutReasonCode ||
        state.detail == _voiceCallMediaFailed) {
      return VoiceCallFailureReason.mediaIceTimeout;
    }
    if (state.reasonCode == _voiceCallNoRemoteAudioReasonCode ||
        state.detail == _voiceCallMediaFailed) {
      return VoiceCallFailureReason.mediaNoRemoteAudio;
    }
    if (state.reasonCode == _voiceCallVideoRendererFailedReasonCode) {
      return VoiceCallFailureReason.videoRendererFailed;
    }
    if (state.reasonCode == _voiceCallVideoFirstFrameTimeoutReasonCode ||
        state.detail == _voiceCallVideoFailed) {
      return VoiceCallFailureReason.videoFirstFrameTimeout;
    }
    if (state.reasonCode == _voiceCallFailedReasonCode) {
      return VoiceCallFailureReason.mediaConnectionFailed;
    }
    if (error != null) {
      return _localAudioFailureReason(error);
    }
    return null;
  }

  String? _voiceCallDetailForSessionState(VoiceCallSessionState state) {
    if (state.phase != VoiceCallSessionPhase.failed) {
      return state.detail;
    }
    final error = state.error;
    if (error != null) {
      final localDetail = _localAudioFailureDetail(error);
      if (localDetail != null) {
        return localDetail;
      }
    }
    if (state.reasonCode == _voiceCallMicrophoneDeniedReasonCode) {
      return _voiceCallRemoteMicrophonePermissionRequired;
    }
    if (state.reasonCode == _voiceCallCameraDeniedReasonCode) {
      return _voiceCallRemoteCameraPermissionRequired;
    }
    if (state.reasonCode == _voiceCallBusyReasonCode ||
        state.detail == 'Peer is busy.') {
      return 'Peer is already in a call.';
    }
    if (state.reasonCode == _voiceCallRejectedReasonCode ||
        state.detail == 'Rejected.') {
      return _voiceCallRejected;
    }
    if (state.reasonCode == _voiceCallNetworkLostReasonCode ||
        state.detail == _voiceCallNetworkLost) {
      return _voiceCallNetworkLost;
    }
    if (state.reasonCode == _voiceCallSignalingFailedReasonCode ||
        state.detail == _voiceCallSignalingFailed) {
      return _voiceCallSignalingFailed;
    }
    if (state.reasonCode == _voiceCallExpiredReasonCode ||
        state.detail == _voiceCallTimedOut) {
      return _voiceCallTimedOut;
    }
    if (state.reasonCode == _voiceCallRingingTimeoutReasonCode ||
        state.detail == 'Call timed out.' ||
        state.detail == 'Call timed out while ringing.') {
      return _voiceCallTimedOut;
    }
    if (state.reasonCode == _voiceCallIceTimeoutReasonCode) {
      return _voiceCallMediaFailed;
    }
    if (state.reasonCode == _voiceCallNoRemoteAudioReasonCode) {
      return _voiceCallMediaFailed;
    }
    if (state.reasonCode == _voiceCallVideoRendererFailedReasonCode) {
      return _voiceCallVideoFailed;
    }
    if (state.reasonCode == _voiceCallVideoFirstFrameTimeoutReasonCode) {
      return _voiceCallVideoFailed;
    }
    if (state.reasonCode == _voiceCallFailedReasonCode) {
      return _voiceCallMediaFailed;
    }
    if (error == null) {
      return state.detail;
    }
    return _localAudioFailureDetail(error) ?? _voiceCallErrorMessage(error);
  }

  void _recordVoiceCallSessionFailure(
    VoiceCallSession session,
    VoiceCallSessionState state, {
    required bool isOutgoing,
  }) {
    final error = state.error;
    final localFailure = error == null ? null : _localAudioFailureReason(error);
    if (localFailure == VoiceCallFailureReason.microphoneDenied) {
      return;
    }
    final detail =
        _voiceCallDetailForSessionState(state) ?? _voiceCallMediaFailed;
    final failureCode =
        state.reasonCode ??
        _voiceCallFailureReasonForSessionState(state)?.name ??
        'unknown';
    _recordVoiceCallDiagnostics(
      callId: session.callId,
      sessionEpoch: session.sessionEpoch,
      peerId: session.remotePeerId,
      isOutgoing: isOutgoing,
      mediaMode: state.mediaMode,
      failureCode: failureCode,
      userMessage: detail,
      nativeError:
          error?.toString() ??
          state.mediaDiagnostics?.lastError ??
          state.mediaDiagnostics?.lastDetail ??
          state.detail ??
          'No native error captured.',
      mediaDiagnostics: state.mediaDiagnostics,
      rendererState: state.mediaMode == CallMediaMode.video
          ? _lastVideoCallRendererState
          : null,
      cameraPermissionFailureDetail: _cameraPermissionFailureDetail(
        error,
        state.reasonCode,
      ),
    );
  }

  void _recordVoiceCallRuntimeFailure(
    VoiceCallState state, {
    required String failureCode,
    required String userMessage,
    required String nativeError,
  }) {
    final callId = state.callId;
    final peerId = state.peerId;
    final sessionEpoch = state.sessionEpoch;
    if (callId == null || peerId == null || sessionEpoch == null) {
      return;
    }
    final callDiagnostics = _videoCallMediaConnection?.diagnostics;
    _recordVoiceCallDiagnostics(
      callId: callId,
      sessionEpoch: sessionEpoch,
      peerId: peerId,
      isOutgoing: state.isOutgoing,
      mediaMode: state.mediaMode,
      failureCode: failureCode,
      userMessage: userMessage,
      nativeError: nativeError,
      mediaDiagnostics: callDiagnostics == null
          ? _voiceCallSession?.state.mediaDiagnostics
          : _voiceMediaDiagnosticsForCall(callDiagnostics),
      rendererState: state.isVideo ? _lastVideoCallRendererState : null,
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
    final reason =
        _voiceCallFailureReasonForRetryDecision(retryDecision) ??
        _voiceCallFailureReasonForError(error) ??
        _localAudioFailureReason(error);
    final detail =
        _voiceCallFailureDetailForRetryDecision(retryDecision) ??
        _voiceCallFailureDetailForError(error) ??
        _localAudioFailureDetail(error) ??
        _voiceCallErrorMessage(error);
    _recordVoiceCallDiagnostics(
      callId: callId,
      sessionEpoch: sessionEpoch,
      peerId: peerId,
      isOutgoing: true,
      mediaMode: mediaMode,
      failureCode: reason?.name ?? retryDecision?.kind.name ?? 'unknown',
      userMessage: detail,
      nativeError: error.toString(),
      lockDiagnostics: _voiceCallLockDiagnostics(
        peerId: peerId,
        callId: callId,
        sessionEpoch: sessionEpoch,
        retryDecision: retryDecision,
        retrySnapshot: retrySnapshot,
      ),
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
    errorRecorder?.call(
      VoiceCallDiagnostics(
        callId: callId,
        sessionEpoch: sessionEpoch,
        peerId: peerId,
        role: isOutgoing ? 'caller' : 'callee',
        mediaMode: mediaMode.name,
        failureCode: failureCode,
        userMessage: userMessage,
        sanitizedUiError: userMessage,
        nativeError: nativeError,
        mediaStates: mediaDiagnostics?.mediaStates ?? const <String>[],
        iceStates: mediaDiagnostics?.iceConnectionStates ?? const <String>[],
        connectionStates:
            mediaDiagnostics?.peerConnectionStates ?? const <String>[],
        localCandidateCount: mediaDiagnostics?.localCandidateCount ?? 0,
        remoteCandidateCount: mediaDiagnostics?.remoteCandidateCount ?? 0,
        pendingRemoteCandidateCount:
            mediaDiagnostics?.pendingRemoteCandidateCount ?? 0,
        localAudioTrackCount: mediaDiagnostics?.localAudioTrackCount ?? 0,
        remoteAudioTrackCount: mediaDiagnostics?.remoteAudioTrackCount ?? 0,
        localVideoTrackCount: mediaDiagnostics?.localVideoTrackCount ?? 0,
        remoteVideoTrackCount: mediaDiagnostics?.remoteVideoTrackCount ?? 0,
        remoteStreamCount: mediaDiagnostics?.remoteStreamCount ?? 0,
        firstLocalVideoFrameAt: _isoTimestamp(rendererState?.localFirstFrameAt),
        firstRemoteVideoFrameAt: _isoTimestamp(
          rendererState?.remoteFirstFrameAt,
        ),
        selectedCandidateRoute: _selectedVoiceCallCandidateRoute(peerId),
        cameraPermissionFailureDetail: cameraPermissionFailureDetail,
        lockClaimResult: lockDiagnostics['lockClaimResult']?.toString(),
        lockPath: lockDiagnostics['lockPath']?.toString(),
        pairId: lockDiagnostics['pairId']?.toString(),
        callerUserLock: lockDiagnostics['callerUserLock']?.toString(),
        calleeUserLock: lockDiagnostics['calleeUserLock']?.toString(),
        lockCallId: lockDiagnostics['lockCallId']?.toString(),
        lockExpiresAt: lockDiagnostics['lockExpiresAt'] is num
            ? (lockDiagnostics['lockExpiresAt']! as num).toInt()
            : null,
        lockWasReclaimed: lockDiagnostics['lockWasReclaimed'] is bool
            ? lockDiagnostics['lockWasReclaimed']! as bool
            : null,
        terminalRoomWasCleaned:
            lockDiagnostics['terminalRoomWasCleaned'] is bool
            ? lockDiagnostics['terminalRoomWasCleaned']! as bool
            : null,
        corruptRoomWasRepaired:
            lockDiagnostics['corruptRoomWasRepaired'] is bool
            ? lockDiagnostics['corruptRoomWasRepaired']! as bool
            : null,
        timestampRepair: lockDiagnostics['timestampRepair'] is bool
            ? lockDiagnostics['timestampRepair']! as bool
            : null,
      ),
      StackTrace.current,
      source: 'voice-call-media',
      fatal: false,
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
    _cancelVoiceCallReconnectGrace();
    await _cancelVoiceSignalingSubscriptions();
    final session = _voiceCallSession;
    if (session == null) {
      await _voiceCallSessionSubscription?.cancel();
      _voiceCallSessionSubscription = null;
      return;
    }
    await _disposeVoiceCallSession(session);
  }

  Future<void> _disposeVoiceCallSession(VoiceCallSession session) async {
    if (_voiceCallSession == session) {
      _voiceCallSession = null;
      _cancelVoiceCallReconnectGrace();
      await _cancelVoiceSignalingSubscriptions();
      await _voiceCallSessionSubscription?.cancel();
      _voiceCallSessionSubscription = null;
    }
    try {
      await session.dispose();
    } catch (_) {
      // Voice call cleanup is best effort once the call is terminal.
    } finally {
      await _disposeVideoCallResources();
    }
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
    return switch (mediaMode) {
      CallMediaMode.audio => 'Checking microphone permission.',
      CallMediaMode.video => 'Checking camera and microphone permission.',
    };
  }

  bool _isRemoteMediaPermissionCode(String? reasonCode) {
    return reasonCode == _voiceCallMicrophoneDeniedReasonCode ||
        reasonCode == _voiceCallCameraDeniedReasonCode;
  }

  VoiceCallFailureReason _remoteMediaPermissionFailure(String? reasonCode) {
    return reasonCode == _voiceCallCameraDeniedReasonCode
        ? VoiceCallFailureReason.remoteCameraDenied
        : VoiceCallFailureReason.remoteMicrophoneDenied;
  }

  String _remoteMediaPermissionDetail(String? reasonCode) {
    return reasonCode == _voiceCallCameraDeniedReasonCode
        ? _voiceCallRemoteCameraPermissionRequired
        : _voiceCallRemoteMicrophonePermissionRequired;
  }

  Future<VoiceMediaConnection> _createVideoVoiceMediaConnection(
    SessionManager manager,
    String peerId,
  ) async {
    final media = await manager.createCallMediaConnection(peerId);
    _recordRuntimeEvent(
      category: 'call',
      name: 'video_media_connection_created',
      context: <String, Object?>{'peerId': peerId},
    );
    _lastVideoCallRendererState = null;
    _handledVideoFirstFrameTimeoutCallId = null;
    _lastLoggedVideoRendererSignature = null;
    _videoCallMediaConnection = media;
    final renderers = VideoCallRenderers(
      rendererFactory: videoCallRendererFactory,
      remoteFirstFrameTimeout: videoCallRemoteFirstFrameTimeout,
    );
    _videoCallRenderers = renderers;
    _videoCallRendererSubscription = renderers.onStateChanged.listen(
      _handleVideoRendererState,
      onError: (Object error, StackTrace stackTrace) {
        _recordRuntimeEvent(
          category: 'call',
          name: 'video_renderer_stream_error',
          severity: 'error',
          message: error.toString(),
          context: <String, Object?>{'peerId': peerId},
        );
        _handleVideoRendererFailure(peerId, error, stackTrace);
      },
    );
    return _VideoVoiceMediaConnection(
      media: media,
      renderers: renderers,
      kind: CallMediaKind.video,
      onRemoteTrackError: (Object error, StackTrace stackTrace) {
        errorRecorder?.call(
          error,
          stackTrace,
          source: 'video-call-media',
          fatal: false,
        );
      },
      onRendererError: (Object error, StackTrace stackTrace) {
        _handleVideoRendererFailure(peerId, error, stackTrace);
      },
    );
  }

  void _handleVideoRendererState(VideoCallRendererState rendererState) {
    _lastVideoCallRendererState = rendererState;
    final signature = <Object?>[
      rendererState.hasLocalStream,
      rendererState.hasRemoteStream,
      rendererState.localFirstFrameAt != null,
      rendererState.remoteFirstFrameAt != null,
      rendererState.remoteFirstFrameTimedOut,
    ].join('|');
    if (_lastLoggedVideoRendererSignature != signature) {
      _lastLoggedVideoRendererSignature = signature;
      _recordRuntimeEvent(
        category: 'call',
        name: 'video_renderer_state',
        context: <String, Object?>{
          ..._voiceCallEventContext(_voiceCallState),
          'hasLocalStream': rendererState.hasLocalStream,
          'hasRemoteStream': rendererState.hasRemoteStream,
          'localFirstFrameAt': _isoTimestamp(rendererState.localFirstFrameAt),
          'remoteFirstFrameAt': _isoTimestamp(rendererState.remoteFirstFrameAt),
          'remoteFirstFrameTimedOut': rendererState.remoteFirstFrameTimedOut,
        },
      );
    }
    final current = _voiceCallState;
    if (!current.hasCall || !current.isVideo) {
      return;
    }
    _setVoiceCallState(
      current.copyWith(
        hasLocalVideo: rendererState.hasLocalStream,
        hasRemoteVideo: rendererState.hasRemoteStream,
        videoFirstFrameTimedOut: rendererState.remoteFirstFrameTimedOut,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (rendererState.remoteFirstFrameTimedOut &&
        current.phase == VoiceCallPhase.active &&
        !current.isRemoteCameraMuted &&
        current.callId != null &&
        _handledVideoFirstFrameTimeoutCallId != current.callId) {
      _handledVideoFirstFrameTimeoutCallId = current.callId;
      unawaited(_failVideoCallForFirstFrameTimeout(current));
    }
  }

  Future<void> _failVideoCallForFirstFrameTimeout(
    VoiceCallState timedOutCall,
  ) async {
    final peerId = timedOutCall.peerId;
    final callId = timedOutCall.callId;
    if (peerId == null || callId == null) {
      return;
    }
    if (!_isCurrentVoiceCall(
      peerId,
      callId,
      sessionEpoch: timedOutCall.sessionEpoch,
    )) {
      return;
    }
    _recordVoiceCallRuntimeFailure(
      timedOutCall,
      failureCode: _voiceCallVideoFirstFrameTimeoutReasonCode,
      userMessage: _voiceCallVideoFailed,
      nativeError:
          'Remote video stream was attached but no rendered frame arrived.',
    );
    await _endVoiceCallForPeer(
      peerId,
      notifyPeer: false,
      detail: _voiceCallVideoFailed,
      failureReason: VoiceCallFailureReason.videoFirstFrameTimeout,
      failureDetail: _voiceCallVideoFailed,
    );
  }

  void _handleVideoRendererFailure(
    String peerId,
    Object error,
    StackTrace stackTrace,
  ) {
    _recordRuntimeEvent(
      category: 'call',
      name: 'video_renderer_failed',
      severity: 'error',
      message: error.toString(),
      context: <String, Object?>{'peerId': peerId},
    );
    errorRecorder?.call(
      error,
      stackTrace,
      source: 'video-call-renderer',
      fatal: false,
    );
    final current = _voiceCallState;
    if (!current.hasCall ||
        !current.isVideo ||
        current.phase == VoiceCallPhase.failed ||
        current.phase == VoiceCallPhase.ending ||
        current.peerId == null ||
        current.callId == null ||
        !_isCurrentVoiceCall(
          peerId,
          current.callId!,
          sessionEpoch: current.sessionEpoch,
        )) {
      return;
    }
    _recordVoiceCallRuntimeFailure(
      current,
      failureCode: _voiceCallVideoRendererFailedReasonCode,
      userMessage: _voiceCallVideoFailed,
      nativeError: error.toString(),
    );
    unawaited(
      _endVoiceCallForPeer(
        peerId,
        notifyPeer: false,
        detail: _voiceCallVideoFailed,
        failureReason: VoiceCallFailureReason.videoRendererFailed,
        failureDetail: _voiceCallVideoFailed,
      ),
    );
  }

  void _handleVoiceCallAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    final current = _voiceCallState;
    if (!current.hasCall ||
        !current.isVideo ||
        current.phase == VoiceCallPhase.failed ||
        current.phase == VoiceCallPhase.ending ||
        current.peerId == null ||
        current.callId == null) {
      return;
    }
    _recordRuntimeEvent(
      category: 'call',
      name: 'video_call_backgrounded',
      severity: 'warning',
      context: <String, Object?>{
        ..._voiceCallEventContext(current),
        'lifecycleState': state.name,
      },
    );
    _recordVoiceCallRuntimeFailure(
      current,
      failureCode: _voiceCallFailedReasonCode,
      userMessage: _voiceCallVideoBackgrounded,
      nativeError: _voiceCallVideoBackgrounded,
    );
    unawaited(
      _endVoiceCallForPeer(
        current.peerId!,
        notifyPeer: false,
        detail: _voiceCallVideoBackgrounded,
        failureReason: VoiceCallFailureReason.mediaConnectionFailed,
        failureDetail: _voiceCallVideoBackgrounded,
      ),
    );
  }

  Future<void> _setVideoCallCameraMutedInSignaling(bool muted) async {
    final current = _voiceCallState;
    final callId = current.callId;
    if (callId == null) {
      return;
    }
    try {
      await _requireVoiceSignalingAdapter().setCameraMuted(
        callId: callId,
        username: _normalizedUsername(selfIdentity.username),
        cameraMuted: muted,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (error, stackTrace) {
      _recordVoiceSignalingError(error, stackTrace);
    }
  }

  Future<void> _disposeVideoCallResources() async {
    final renderers = _videoCallRenderers;
    if (renderers != null || _videoCallMediaConnection != null) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'video_resources_dispose_started',
        context: _voiceCallEventContext(_voiceCallState),
      );
    }
    _videoCallRenderers = null;
    _videoCallMediaConnection = null;
    _lastLoggedVideoRendererSignature = null;
    await _videoCallRendererSubscription?.cancel();
    _videoCallRendererSubscription = null;
    if (renderers == null) {
      return;
    }
    _lastVideoCallRendererState = renderers.state;
    try {
      await renderers.dispose();
      _recordRuntimeEvent(
        category: 'call',
        name: 'video_resources_disposed',
        context: _voiceCallEventContext(_voiceCallState),
      );
    } catch (error, stackTrace) {
      _recordRuntimeEvent(
        category: 'call',
        name: 'video_resources_dispose_failed',
        severity: 'warning',
        message: error.toString(),
        context: _voiceCallEventContext(_voiceCallState),
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'video-call-renderer',
        fatal: false,
      );
    }
  }

  VoiceSignalingAdapter _requireVoiceSignalingAdapter() {
    final voiceAdapter = voiceSignalingAdapter;
    if (voiceAdapter == null) {
      throw StateError('Voice calls require Firebase voice signaling.');
    }
    return voiceAdapter;
  }

  void _recordVoiceSignalingError(Object error, StackTrace stackTrace) {
    if (_isVoiceTerminalAlreadyClosedError(error)) {
      _recordTerminalAlreadyClosed(
        error,
        name: 'voice_cleanup_already_completed',
        context: _voiceCallEventContext(_voiceCallState),
      );
      return;
    }
    _recordRuntimeEvent(
      category: 'call',
      name: 'signaling_error',
      severity: 'error',
      message: error.toString(),
      context: _voiceCallEventContext(_voiceCallState),
    );
    errorRecorder?.call(
      error,
      stackTrace,
      source: 'voice-call-signaling',
      fatal: false,
    );
  }

  Future<void> _cancelVoiceSignalingSubscriptions() async {
    final subscriptions = List<StreamSubscription<dynamic>>.of(
      _voiceSignalingSubscriptions,
    );
    _voiceSignalingSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  Future<void> _endVoiceCallInSignaling({
    required String callId,
    required VoiceCallSignalingStatus status,
    String? reason,
    String? reasonCode,
    bool bestEffort = false,
  }) async {
    final cleanupContext = <String, Object?>{
      'callId': callId,
      'status': status.name,
      'reason': reason,
      'reasonCode': reasonCode,
      'bestEffort': bestEffort,
    };
    try {
      _recordRuntimeEvent(
        category: 'call',
        name: 'signaling_end_call_started',
        context: cleanupContext,
      );
      _recordRuntimeEvent(
        category: 'call',
        name: 'voice_terminal_cleanup_started',
        context: cleanupContext,
      );
      await _requireVoiceSignalingAdapter().endCall(
        callId: callId,
        username: _normalizedUsername(selfIdentity.username),
        status: status,
        endedAt: DateTime.now().millisecondsSinceEpoch,
        reason: reason,
        reasonCode: reasonCode,
      );
      _recordRuntimeEvent(
        category: 'call',
        name: 'signaling_end_call_completed',
        context: <String, Object?>{
          'callId': callId,
          'status': status.name,
          'reasonCode': reasonCode,
        },
      );
      _recordRuntimeEvent(
        category: 'call',
        name: 'voice_terminal_cleanup_completed',
        context: cleanupContext,
      );
    } catch (error) {
      if (_isDurableVoiceCallTerminalStateError(error)) {
        _recordRuntimeEvent(
          category: 'call',
          name: 'voice_cleanup_already_completed',
          severity: 'info',
          message: error.toString(),
          context: cleanupContext,
        );
        _recordRuntimeEvent(
          category: 'call',
          name: 'voice_terminal_cleanup_completed',
          context: <String, Object?>{
            ...cleanupContext,
            'cleanupResult': 'alreadyCompleted',
          },
        );
        return;
      }
      _recordRuntimeEvent(
        category: 'call',
        name: 'signaling_end_call_failed',
        severity: bestEffort ? 'warning' : 'error',
        message: error.toString(),
        context: <String, Object?>{
          'callId': callId,
          'status': status.name,
          'reasonCode': reasonCode,
          'bestEffort': bestEffort,
        },
      );
      _recordRuntimeEvent(
        category: 'call',
        name: 'voice_terminal_cleanup_failed',
        severity: bestEffort ? 'warning' : 'error',
        message: error.toString(),
        context: cleanupContext,
      );
      if (!bestEffort) {
        rethrow;
      }
    }
  }

  bool _isDurableVoiceCallTerminalStateError(Object error) {
    final normalized = _normalizedVoiceCallErrorText(error).toLowerCase();
    return normalized.contains('unknown voice call') ||
        normalized.contains('already ended');
  }

  bool _isVoiceTerminalAlreadyClosedError(Object error) {
    return _isVoiceTerminalAlreadyClosedMessage(
      _normalizedVoiceCallErrorText(error),
    );
  }

  bool _isVoiceTerminalAlreadyClosedMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('unknown voice call') ||
        normalized.contains('already ended') ||
        normalized.contains('failed to send hangup');
  }

  void _recordTerminalAlreadyClosed(
    Object error, {
    required String name,
    required Map<String, Object?> context,
  }) {
    _recordRuntimeEvent(
      category: 'call',
      name: name,
      severity: 'info',
      message: error.toString(),
      context: <String, Object?>{
        ...context,
        'cleanupResult': 'alreadyCompleted',
      },
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
      await _disposeVoiceCallSession(session);
      final latest = _voiceCallState;
      if (latest.callId == session.callId ||
          latest.sessionEpoch == session.sessionEpoch ||
          latest.phase == VoiceCallPhase.idle) {
        _setVoiceCallState(failedState);
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
    await _disposeVoiceCallSession(session);
    final latest = _voiceCallState;
    if (latest.callId == session.callId ||
        latest.sessionEpoch == session.sessionEpoch) {
      _setVoiceCallState(const VoiceCallState.idle());
    }
  }

  Future<void> _endVoiceCallForPeer(
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
        try {
          await session.hangUp(reason: detail);
        } catch (error, stackTrace) {
          _recordVoiceSignalingError(error, stackTrace);
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
        await _disposeVoiceCallSession(session);
        _setVoiceCallState(
          _voiceCallStateAfterLocalEnd(
            current,
            detail: detail,
            failureReason: failureReason,
            failureDetail: failureDetail,
          ),
        );
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
    Object? lastError;
    StackTrace? lastStackTrace;
    for (
      var attempt = 1;
      attempt <= _voiceTerminalWritePolicy.maxAttempts;
      attempt += 1
    ) {
      final context = <String, Object?>{
        'callId': callId,
        'status': status.name,
        'reasonCode': reasonCode,
        'attempt': attempt,
        'maxAttempts': _voiceTerminalWritePolicy.maxAttempts,
      };
      _recordRuntimeEvent(
        category: 'call',
        name: 'voice_terminal_write_before_session_hangup',
        context: context,
      );
      try {
        await _endVoiceCallInSignaling(
          callId: callId,
          status: status,
          reason: detail,
          reasonCode: reasonCode,
        );
        _recordRuntimeEvent(
          category: 'call',
          name: 'voice_terminal_write_durable',
          context: context,
        );
        return const _TerminalRoomWriteResult.durable();
      } catch (error, stackTrace) {
        if (_isDurableVoiceCallTerminalStateError(error)) {
          _recordRuntimeEvent(
            category: 'call',
            name: 'voice_terminal_write_durable',
            context: <String, Object?>{
              ...context,
              'cleanupResult': 'alreadyCompleted',
            },
          );
          return const _TerminalRoomWriteResult.durable();
        }
        lastError = error;
        lastStackTrace = stackTrace;
        if (!_voiceTerminalWritePolicy.canRetryAfterAttempt(attempt)) {
          break;
        }
        final delay = _voiceTerminalWritePolicy.retryDelayAfterAttempt(attempt);
        _recordRuntimeEvent(
          category: 'call',
          name: 'voice_terminal_write_retry',
          severity: 'warning',
          message: error.toString(),
          context: <String, Object?>{
            ...context,
            'nextAttempt': attempt + 1,
            'retryDelayMs': delay.inMilliseconds,
          },
        );
        await Future<void>.delayed(delay);
      }
    }
    _recordRuntimeEvent(
      category: 'call',
      name: 'voice_terminal_write_failed',
      severity: 'error',
      message: lastError?.toString(),
      context: <String, Object?>{
        'callId': callId,
        'status': status.name,
        'reasonCode': reasonCode,
        'maxAttempts': _voiceTerminalWritePolicy.maxAttempts,
      },
    );
    if (lastError != null) {
      errorRecorder?.call(
        lastError,
        lastStackTrace,
        source: 'voice-terminal-write',
        fatal: false,
      );
    }
    return _TerminalRoomWriteResult.failed(lastError);
  }

  VoiceCallState _voiceCallStateAfterTerminalWriteFailure(
    VoiceCallState current, {
    Object? error,
  }) {
    return current.copyWith(
      phase: VoiceCallPhase.failed,
      detail: 'Could not notify peer that the call ended. Try again.',
      error: error,
      failureReason: VoiceCallFailureReason.signalingFailed,
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
    );
  }

  bool _isSameLiveVoiceCallStateForSession(
    VoiceCallState latest,
    VoiceCallSession session,
  ) {
    if (_shutDown || _voiceCallSession != session) {
      return false;
    }
    return latest.callId == session.callId &&
        latest.sessionEpoch == session.sessionEpoch &&
        latest.phase != VoiceCallPhase.idle &&
        latest.phase != VoiceCallPhase.failed;
  }

  bool _isSameLiveVoiceCallState(
    VoiceCallState latest,
    VoiceCallState expected,
  ) {
    return latest.callId == expected.callId &&
        latest.sessionEpoch == expected.sessionEpoch &&
        latest.phase != VoiceCallPhase.idle &&
        latest.phase != VoiceCallPhase.failed;
  }

  VoiceCallState _voiceCallStateAfterLocalEnd(
    VoiceCallState current, {
    required String detail,
    VoiceCallFailureReason? failureReason,
    String? failureDetail,
  }) {
    if (failureReason == null) {
      return const VoiceCallState.idle();
    }
    return current.copyWith(
      phase: VoiceCallPhase.failed,
      detail: failureDetail ?? detail,
      failureReason: failureReason,
      isCameraMuted: false,
      isDeafened: false,
      isRemoteCameraMuted: false,
      hasLocalVideo: false,
      hasRemoteVideo: false,
      videoFirstFrameTimedOut: false,
      mediaReconnecting: false,
      outputRoute: VoiceCallOutputRoute.systemDefault,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      clearError: true,
      clearOutputRouteWarning: true,
      clearOutputRouteTarget: true,
      clearReconnectingSince: true,
      audioLevel: const VoiceAudioLevel.unavailable(),
    );
  }

  void _failVoiceCallForPeer(String peerId, String message) {
    final normalizedPeerId = _normalizedUsername(peerId);
    final current = _voiceCallState;
    if (current.peerId != normalizedPeerId ||
        current.phase == VoiceCallPhase.idle ||
        current.phase == VoiceCallPhase.failed ||
        current.phase == VoiceCallPhase.ending) {
      return;
    }
    unawaited(
      _endVoiceCallForPeer(
        normalizedPeerId,
        notifyPeer: false,
        detail: message,
        failureReason: VoiceCallFailureReason.networkLost,
        failureDetail: message,
      ),
    );
  }

  void _markVoiceCallReconnectingForPeer(String peerId) {
    final current = _voiceCallState;
    final normalizedPeerId = _normalizedUsername(peerId);
    if (current.peerId != normalizedPeerId ||
        current.phase == VoiceCallPhase.idle ||
        current.phase == VoiceCallPhase.failed ||
        current.phase == VoiceCallPhase.ending) {
      return;
    }
    _recordRuntimeEvent(
      category: 'call',
      name: 'media_reconnecting_started',
      severity: 'warning',
      context: _voiceCallEventContext(current),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = _voiceCallSession;
    if (session != null && session.callId == current.callId) {
      session.markMediaReconnecting(detail: _voiceCallReconnecting);
    }
    _setVoiceCallState(
      current.copyWith(
        mediaReconnecting: true,
        reconnectingSince: current.reconnectingSince ?? now,
        detail: _voiceCallReconnecting,
        updatedAt: now,
        clearError: true,
      ),
    );
    _armVoiceCallReconnectGrace(current.copyWith(updatedAt: now));
  }

  void _clearVoiceCallReconnectingForPeer(String peerId) {
    final current = _voiceCallState;
    if (current.peerId != _normalizedUsername(peerId) ||
        !current.mediaReconnecting) {
      return;
    }
    _recordRuntimeEvent(
      category: 'call',
      name: 'media_reconnecting_cleared',
      context: _voiceCallEventContext(current),
    );
    final session = _voiceCallSession;
    if (session != null && session.callId == current.callId) {
      session.clearMediaReconnecting();
    }
    _cancelVoiceCallReconnectGrace();
    _setVoiceCallState(
      current.copyWith(
        mediaReconnecting: false,
        detail: 'Voice call connected.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        clearReconnectingSince: true,
        clearError: true,
      ),
    );
  }

  void _armVoiceCallReconnectGrace(VoiceCallState call) {
    final callId = call.callId;
    final peerId = call.peerId;
    if (callId == null ||
        peerId == null ||
        activeCallReconnectGrace <= Duration.zero) {
      return;
    }
    _voiceCallReconnectGraceTimer?.cancel();
    final sessionEpoch = call.sessionEpoch;
    _voiceCallReconnectGraceTimer = Timer(activeCallReconnectGrace, () {
      final current = _voiceCallState;
      if (current.callId != callId ||
          current.peerId != peerId ||
          current.sessionEpoch != sessionEpoch ||
          !current.mediaReconnecting ||
          current.phase != VoiceCallPhase.active) {
        return;
      }
      unawaited(
        _endVoiceCallForPeer(
          peerId,
          notifyPeer: false,
          detail: _voiceCallNetworkLost,
          failureReason: VoiceCallFailureReason.networkLost,
          failureDetail: _voiceCallNetworkLost,
        ),
      );
    });
  }

  void _cancelVoiceCallReconnectGrace() {
    _voiceCallReconnectGraceTimer?.cancel();
    _voiceCallReconnectGraceTimer = null;
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
    await _disposeCurrentVoiceCallSession();
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
  }

  void _assertVoiceCallCanStart() {
    if (brain == null) {
      throw StateError('Peer connection is unavailable right now.');
    }
  }

  Future<void> _assertVoiceCallPeerIsFriend(String peerId) async {
    var friend = await _localMutations.run(
      () => friendStore.loadFriend(peerId),
    );
    if (friend?.state != FriendState.friend) {
      await _syncRelationships(onlyUsername: peerId);
      friend = await _localMutations.run(() => friendStore.loadFriend(peerId));
    }
    if (friend?.state != FriendState.friend) {
      throw StateError('Only accepted friends can call.');
    }
  }

  Future<_CallStartPresenceSnapshot> _fetchVoiceCallPeerPresence(
    String peerId, {
    required CallMediaMode mediaMode,
  }) async {
    final normalizedPeerId = _normalizedUsername(peerId);
    BackendIdentity? identity;
    try {
      identity = await adapter.fetchIdentity(normalizedPeerId);
    } catch (error, stackTrace) {
      final decision = RuntimeInteractionGuard.presenceUnknown(
        peerId: normalizedPeerId,
      );
      _recordRuntimeEvent(
        category: 'call',
        name: 'call_start_presence_unknown',
        severity: 'warning',
        message: decision.userMessage,
        context: <String, Object?>{
          'peerId': normalizedPeerId,
          'mediaMode': mediaMode.name,
          'reasonCode': decision.reasonCode.name,
          'presenceSource': 'backend',
          'error': error.toString(),
        },
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'voice-call-presence',
        fatal: false,
      );
      return _CallStartPresenceSnapshot(
        peerOnline: null,
        diagnostics: <String, Object?>{
          'presenceSource': 'backend',
          'presenceError': error.toString(),
        },
      );
    }

    if (identity == null) {
      final decision = RuntimeInteractionGuard.presenceUnknown(
        peerId: normalizedPeerId,
      );
      _recordRuntimeEvent(
        category: 'call',
        name: 'call_start_presence_unknown',
        severity: 'warning',
        message: decision.userMessage,
        context: <String, Object?>{
          'peerId': normalizedPeerId,
          'mediaMode': mediaMode.name,
          'reasonCode': decision.reasonCode.name,
          'presenceSource': 'backend',
        },
      );
      return const _CallStartPresenceSnapshot(
        peerOnline: null,
        diagnostics: <String, Object?>{'presenceSource': 'backend'},
      );
    }

    final peerOnline = identity.online;
    final now = DateTime.now().millisecondsSinceEpoch;
    final presenceAgeMs = identity.lastHeartbeat <= 0
        ? null
        : now - identity.lastHeartbeat;
    await _localMutations.run(
      () => friendStore.updatePresence(normalizedPeerId, peerOnline),
    );
    if (!peerOnline) {
      final decision = RuntimeInteractionGuard.peerOffline(
        peerId: normalizedPeerId,
      );
      _recordRuntimeEvent(
        category: 'call',
        name: 'call_start_blocked_offline',
        severity: 'warning',
        message: decision.userMessage,
        context: <String, Object?>{
          'peerId': normalizedPeerId,
          'mediaMode': mediaMode.name,
          'reasonCode': decision.reasonCode.name,
          'presenceSource': 'backend',
          'lastHeartbeat': identity.lastHeartbeat,
          'lastSeen': identity.lastSeen,
          'presenceAgeMs': presenceAgeMs,
        },
      );
      return _CallStartPresenceSnapshot(
        peerOnline: false,
        diagnostics: <String, Object?>{
          'presenceSource': 'backend',
          'lastHeartbeat': identity.lastHeartbeat,
          'lastSeen': identity.lastSeen,
          'presenceAgeMs': presenceAgeMs,
        },
      );
    } else {
      _recordRuntimeEvent(
        category: 'call',
        name: 'call_start_presence_confirmed',
        context: <String, Object?>{
          'peerId': normalizedPeerId,
          'mediaMode': mediaMode.name,
          'presenceSource': 'backend',
          'lastHeartbeat': identity.lastHeartbeat,
          'lastSeen': identity.lastSeen,
          'presenceAgeMs': presenceAgeMs,
        },
      );
    }
    return _CallStartPresenceSnapshot(
      peerOnline: true,
      diagnostics: <String, Object?>{
        'presenceSource': 'backend',
        'lastHeartbeat': identity.lastHeartbeat,
        'lastSeen': identity.lastSeen,
        'presenceAgeMs': presenceAgeMs,
      },
    );
  }

  Future<FileTransferRecord?> _firstActiveTransfer() async {
    final transfers = await fileTransferStore.loadActiveTransfers();
    return transfers.isEmpty ? null : transfers.first;
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
    errorRecorder?.call(
      StateError(
        'Ignored late voice signaling for ${session.callId}/'
        '${session.sessionEpoch}: $message',
      ),
      StackTrace.current,
      source: 'voice-call-signaling',
      fatal: false,
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
  }

  String _newVoiceCallId(String peerId) {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '${_normalizedUsername(selfIdentity.username)}:$peerId:$now';
  }

  CallSignalingFailureSnapshot? _voiceCallSignalingFailureSnapshotForError(
    Object error, {
    String? peerId,
  }) {
    final normalized = _normalizedVoiceCallErrorText(error).toLowerCase();
    if (!_isVoiceCallSignalingError(error, normalized) &&
        !CallRetryPolicy.isBusyConflictMessage(normalized) &&
        !CallRetryPolicy.isCleanupConflictMessage(normalized)) {
      return null;
    }
    return CallSignalingFailureSnapshot(
      message: normalized,
      lockWasReclaimed:
          normalized.contains('lock was reclaimed') ||
          normalized.contains('old call state was cleaned'),
      terminalRoomWasCleaned:
          normalized.contains('terminal room cleaned') ||
          normalized.contains('terminal room'),
      corruptRoomWasRepaired:
          normalized.contains('corrupt room repaired') ||
          normalized.contains('corrupt terminal'),
      cleanupInProgress:
          normalized.contains('cleanup in progress') ||
          normalized.contains('cleaning up'),
      peerId: peerId ?? _voiceCallBusyUser(normalized),
    );
  }

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
    final busyUser = _voiceCallBusyUser(message);
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
  ) {
    return switch (decision?.kind) {
      CallRetryDecisionKind.peerBusy => VoiceCallFailureReason.peerBusy,
      CallRetryDecisionKind.peerOffline ||
      CallRetryDecisionKind.cleanedStaleState ||
      CallRetryDecisionKind.cleanupInProgress ||
      CallRetryDecisionKind.signalingFailed =>
        VoiceCallFailureReason.signalingFailed,
      CallRetryDecisionKind.proceed || null => null,
    };
  }

  String? _voiceCallFailureDetailForRetryDecision(CallRetryDecision? decision) {
    return switch (decision?.kind) {
      CallRetryDecisionKind.peerBusy ||
      CallRetryDecisionKind.peerOffline ||
      CallRetryDecisionKind.cleanedStaleState ||
      CallRetryDecisionKind.cleanupInProgress ||
      CallRetryDecisionKind.signalingFailed => decision?.userMessage,
      CallRetryDecisionKind.proceed || null => null,
    };
  }

  VoiceCallFailureReason? _voiceCallFailureReasonForError(Object error) {
    final normalized = _normalizedVoiceCallErrorText(error).toLowerCase();
    if (_isVoiceCallBusyError(normalized)) {
      return VoiceCallFailureReason.peerBusy;
    }
    if (_isVoiceCallRejectedError(normalized)) {
      return VoiceCallFailureReason.rejected;
    }
    if (_isVoiceCallNetworkLostError(normalized)) {
      return VoiceCallFailureReason.networkLost;
    }
    if (_isVoiceCallExpiredError(normalized)) {
      return VoiceCallFailureReason.expired;
    }
    if (_isVoiceCallOfflineError(normalized)) {
      return VoiceCallFailureReason.signalingFailed;
    }
    if (_isVoiceCallSignalingError(error, normalized)) {
      return VoiceCallFailureReason.signalingFailed;
    }
    if (_isVoiceCallVideoRendererError(normalized)) {
      return VoiceCallFailureReason.videoRendererFailed;
    }
    if (_isVoiceCallNativeMediaError(normalized) ||
        normalized.contains('ice timeout') ||
        normalized.contains('no remote audio')) {
      return VoiceCallFailureReason.mediaConnectionFailed;
    }
    return null;
  }

  String? _voiceCallFailureDetailForError(Object error) {
    final normalized = _normalizedVoiceCallErrorText(error).toLowerCase();
    if (_isVoiceCallBusyError(normalized)) {
      final busyUser = _voiceCallBusyUser(normalized);
      if (busyUser != null &&
          busyUser != _normalizedUsername(selfIdentity.username)) {
        return '@$busyUser is already in a call.';
      }
      return 'Peer is already in a call.';
    }
    if (_isVoiceCallRejectedError(normalized)) {
      return _voiceCallRejected;
    }
    if (_isVoiceCallNetworkLostError(normalized)) {
      return _voiceCallNetworkLost;
    }
    if (_isVoiceCallExpiredError(normalized)) {
      return _voiceCallTimedOut;
    }
    if (_isVoiceCallOfflineError(normalized)) {
      final unknownPeer = RuntimeInteractionGuard.presenceUnknownMessage(
        _voiceCallState.peerId ?? '',
      );
      return normalized.contains('could not confirm') ||
              normalized.contains('presence unknown')
          ? unknownPeer
          : RuntimeInteractionGuard.peerOfflineMessage(
              _voiceCallState.peerId ?? '',
            );
    }
    if (_isVoiceCallSignalingError(error, normalized)) {
      return _voiceCallSignalingFailed;
    }
    if (_isVoiceCallVideoRendererError(normalized)) {
      return _voiceCallVideoFailed;
    }
    if (_isVoiceCallNativeMediaError(normalized) ||
        normalized.contains('ice timeout') ||
        normalized.contains('no remote audio')) {
      return _voiceCallMediaFailed;
    }
    return null;
  }

  String _normalizedVoiceCallErrorText(Object error) {
    final raw = error.toString().trim();
    const prefixes = <String>[
      'Exception: ',
      'Bad state: ',
      'StateError: ',
      'VoiceSignalingException: ',
    ];
    var message = raw;
    for (final prefix in prefixes) {
      if (raw.startsWith(prefix)) {
        message = raw.substring(prefix.length).trim();
        break;
      }
    }
    return message;
  }

  String _voiceCallErrorMessage(Object error) {
    final message = _normalizedVoiceCallErrorText(error);
    final typedDetail = _voiceCallFailureDetailForError(error);
    if (typedDetail != null) {
      return typedDetail;
    }
    return message;
  }

  bool _isVoiceCallBusyError(String normalized) {
    return normalized.contains('peer is busy') ||
        normalized == 'busy.' ||
        normalized.contains('active voice call already exists') ||
        normalized.contains('activevoicepairs') ||
        normalized.contains('active voice pair') ||
        normalized.contains('activevoiceusers') ||
        normalized.contains('active voice user');
  }

  bool _isVoiceCallOfflineError(String normalized) {
    return CallRetryPolicy.isOfflineMessage(normalized);
  }

  String? _voiceCallBusyUser(String normalized) {
    const marker = 'active voice call already exists for user ';
    final markerIndex = normalized.indexOf(marker);
    if (markerIndex < 0) {
      return null;
    }
    final tail = normalized.substring(markerIndex + marker.length).trim();
    if (tail.isEmpty) {
      return null;
    }
    return _normalizedUsername(tail.split(RegExp(r'[\s.]')).first);
  }

  bool _isVoiceCallRejectedError(String normalized) {
    return normalized == 'rejected.' ||
        normalized.contains('call declined') ||
        normalized.contains('call rejected');
  }

  bool _isVoiceCallNetworkLostError(String normalized) {
    return normalized.contains('network connection lost') ||
        normalized.contains('network lost') ||
        normalized.contains('internet connection') ||
        normalized.contains('network is unavailable') ||
        normalized.contains('network unavailable');
  }

  bool _isVoiceCallExpiredError(String normalized) {
    return normalized.contains('call timed out') ||
        normalized.contains('voice call expired') ||
        normalized.contains('call room expired') ||
        normalized == 'expired.';
  }

  bool _isVoiceCallSignalingError(Object error, String normalized) {
    return error is VoiceSignalingException ||
        normalized.contains('voice signaling') ||
        normalized.contains('firebase') ||
        normalized.contains('unknown voice call') ||
        normalized.contains('voice call already exists') ||
        normalized.contains('already ended') ||
        normalized.contains('permission-denied') ||
        normalized.contains('database');
  }

  bool _isVoiceCallNativeMediaError(String normalized) {
    return normalized.contains('rtcrtptransceiver') ||
        normalized.contains('setdirection') ||
        normalized.contains('setremotedescription') ||
        normalized.contains('peerconnectionsetremotedescription') ||
        normalized.contains('m-line') ||
        normalized.contains('peer connection changed while');
  }

  bool _isVoiceCallVideoRendererError(String normalized) {
    return normalized.contains('video renderer') ||
        normalized.contains('rtc video renderer') ||
        normalized.contains('rtcvideorenderer');
  }

  VoiceCallFailureReason? _localAudioFailureReason(Object error) {
    if (error is _VideoCallRendererException ||
        _isVoiceCallVideoRendererError(error.toString().toLowerCase())) {
      return VoiceCallFailureReason.videoRendererFailed;
    }
    if (error is CallMediaException) {
      return switch (error.reason) {
        CallMediaFailureReason.cameraDenied ||
        CallMediaFailureReason.cameraUnavailable =>
          VoiceCallFailureReason.cameraDenied,
        CallMediaFailureReason.microphoneDenied =>
          VoiceCallFailureReason.microphoneDenied,
        CallMediaFailureReason.mediaCaptureFailed ||
        CallMediaFailureReason.negotiationFailed => null,
      };
    }
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('camera') &&
        (normalized.contains('permission') ||
            normalized.contains('denied') ||
            normalized.contains('unavailable'))) {
      return VoiceCallFailureReason.cameraDenied;
    }
    final permissionDenied =
        normalized.contains('notallowed') ||
        normalized.contains('not allowed') ||
        normalized.contains('permission denied') ||
        normalized.contains('permission was denied') ||
        normalized.contains('denied permission') ||
        normalized.contains('microphone permission');
    return permissionDenied ? VoiceCallFailureReason.microphoneDenied : null;
  }

  String? _localAudioFailureDetail(Object error) {
    return switch (_localAudioFailureReason(error)) {
      VoiceCallFailureReason.microphoneDenied =>
        _voiceCallMicrophonePermissionRequired,
      VoiceCallFailureReason.cameraDenied => _voiceCallCameraPermissionRequired,
      VoiceCallFailureReason.videoRendererFailed => _voiceCallVideoFailed,
      _ => null,
    };
  }
}

final class _VideoVoiceMediaConnection implements VoiceMediaConnection {
  _VideoVoiceMediaConnection({
    required CallMediaConnection media,
    required VideoCallRenderers renderers,
    required CallMediaKind kind,
    required void Function(Object error, StackTrace stackTrace)
    onRemoteTrackError,
    required void Function(Object error, StackTrace stackTrace) onRendererError,
  }) : _media = media,
       _renderers = renderers,
       _kind = kind,
       _onRemoteTrackError = onRemoteTrackError,
       _onRendererError = onRendererError {
    _remoteTrackSubscription = _media.onRemoteTrack.listen(
      _handleRemoteTrack,
      onError: (Object error, StackTrace stackTrace) {
        _onRemoteTrackError(error, stackTrace);
      },
    );
  }

  final CallMediaConnection _media;
  final VideoCallRenderers _renderers;
  final CallMediaKind _kind;
  final void Function(Object error, StackTrace stackTrace) _onRemoteTrackError;
  final void Function(Object error, StackTrace stackTrace) _onRendererError;
  final StreamController<VoiceRemoteAudioTrack> _remoteAudioController =
      StreamController<VoiceRemoteAudioTrack>.broadcast();
  final StreamController<VoiceMediaAudioLevel> _audioLevelController =
      StreamController<VoiceMediaAudioLevel>.broadcast();

  late final StreamSubscription<CallRemoteMediaTrack> _remoteTrackSubscription;
  bool _disposed = false;

  @override
  Stream<VoiceIceCandidate> get onIceCandidate => _media.onIceCandidate;

  @override
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack =>
      _remoteAudioController.stream;

  @override
  Stream<VoiceMediaAudioLevel> get onAudioLevelChanged =>
      _audioLevelController.stream;

  @override
  Stream<VoiceMediaState> get onStateChanged {
    return _media.onStateChanged.map(_voiceMediaStateForCall);
  }

  @override
  VoiceMediaDiagnostics get diagnostics {
    return _voiceMediaDiagnosticsForCall(_media.diagnostics);
  }

  @override
  Future<void> startLocalAudio() async {
    await _media.startLocalMedia(kind: _kind);
    await _attachLocalVideoStream();
  }

  @override
  Future<VoiceSessionDescription> createOffer() async {
    final offer = await _media.createOffer(kind: _kind);
    await _attachLocalVideoStream();
    return offer;
  }

  @override
  Future<VoiceSessionDescription> acceptOffer(
    VoiceSessionDescription offer,
  ) async {
    final answer = await _media.acceptOffer(offer, kind: _kind);
    await _attachLocalVideoStream();
    return answer;
  }

  @override
  Future<void> applyAnswer(VoiceSessionDescription answer) async {
    await _media.applyAnswer(answer);
  }

  @override
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate) {
    return _media.addRemoteCandidate(candidate);
  }

  @override
  Future<void> setMuted({required bool muted}) {
    return _media.setMicrophoneMuted(muted: muted);
  }

  @override
  Future<void> setDeafened({required bool deafened}) {
    return _media.setDeafened(deafened: deafened);
  }

  @override
  Future<void> setAudioOutputRoute(VoiceMediaOutputRoute route) {
    return _media.setAudioOutputRoute(route);
  }

  @override
  Future<void> selectAudioOutputDevice(String deviceId) {
    return _media.selectAudioOutputDevice(deviceId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _remoteTrackSubscription.cancel();
    await _media.dispose();
    await _remoteAudioController.close();
    await _audioLevelController.close();
  }

  Future<void> _attachLocalVideoStream() async {
    if (_kind != CallMediaKind.video) {
      return;
    }
    try {
      await _renderers.attachLocalStream(_media.localStream);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _VideoCallRendererException(
          'Video renderer failed while attaching local video stream.',
          error,
        ),
        stackTrace,
      );
    }
  }

  void _handleRemoteTrack(CallRemoteMediaTrack event) {
    if (_disposed) {
      return;
    }
    if (event.isAudio) {
      _remoteAudioController.add(
        VoiceRemoteAudioTrack(
          track: event.track,
          streams: event.streams,
          receivedAt: event.receivedAt,
        ),
      );
      return;
    }
    if (!event.isVideo) {
      return;
    }
    final stream = event.streams.isEmpty ? null : event.streams.first;
    unawaited(
      _renderers.attachRemoteStream(stream).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        _onRendererError(
          _VideoCallRendererException(
            'Video renderer failed while attaching remote video stream.',
            error,
          ),
          stackTrace,
        );
      }),
    );
  }
}

final class _VideoCallRendererException implements Exception {
  const _VideoCallRendererException(this.message, this.cause);

  final String message;
  final Object cause;

  @override
  String toString() => '$message $cause';
}

VoiceMediaState _voiceMediaStateForCall(CallMediaState state) {
  return VoiceMediaState(
    phase: _voiceMediaPhaseForCall(state.phase),
    detail: state.detail,
    error: state.error,
    updatedAt: state.updatedAt,
  );
}

VoiceMediaPhase _voiceMediaPhaseForCall(CallMediaPhase phase) {
  return switch (phase) {
    CallMediaPhase.idle => VoiceMediaPhase.idle,
    CallMediaPhase.startingLocalMedia => VoiceMediaPhase.startingLocalAudio,
    CallMediaPhase.localMediaReady => VoiceMediaPhase.localAudioReady,
    CallMediaPhase.creatingOffer => VoiceMediaPhase.creatingOffer,
    CallMediaPhase.applyingOffer => VoiceMediaPhase.applyingOffer,
    CallMediaPhase.applyingAnswer => VoiceMediaPhase.applyingAnswer,
    CallMediaPhase.connecting => VoiceMediaPhase.connecting,
    CallMediaPhase.connected => VoiceMediaPhase.connected,
    CallMediaPhase.failed => VoiceMediaPhase.failed,
    CallMediaPhase.disposed => VoiceMediaPhase.disposed,
  };
}

VoiceMediaDiagnostics _voiceMediaDiagnosticsForCall(
  CallMediaDiagnostics diagnostics,
) {
  return VoiceMediaDiagnostics(
    mediaStates: <String>[
      ...diagnostics.mediaStates,
      'remoteVideoTrackCount:${diagnostics.remoteVideoTrackCount}',
      'hasLocalVideo:${diagnostics.hasLocalVideo}',
      if (diagnostics.lastFailureReason != null)
        'lastFailureReason:${diagnostics.lastFailureReason!.name}',
    ],
    iceConnectionStates: diagnostics.iceConnectionStates,
    peerConnectionStates: diagnostics.peerConnectionStates,
    localCandidateCount: diagnostics.localCandidateCount,
    remoteCandidateCount: diagnostics.remoteCandidateCount,
    pendingRemoteCandidateCount: diagnostics.pendingRemoteCandidateCount,
    localAudioTrackCount: diagnostics.hasLocalAudio ? 1 : 0,
    remoteAudioTrackCount: diagnostics.remoteAudioTrackCount,
    localVideoTrackCount: diagnostics.hasLocalVideo ? 1 : 0,
    remoteVideoTrackCount: diagnostics.remoteVideoTrackCount,
    remoteStreamCount: diagnostics.remoteStreamCount,
    hasLocalAudio: diagnostics.hasLocalAudio,
    hasLocalVideo: diagnostics.hasLocalVideo,
    peerConnectionClosed: diagnostics.peerConnectionClosed,
    disposed: diagnostics.disposed,
    lastDetail: diagnostics.lastDetail,
    lastError: diagnostics.lastError,
    lastFailureReason: diagnostics.lastFailureReason?.name,
  );
}
