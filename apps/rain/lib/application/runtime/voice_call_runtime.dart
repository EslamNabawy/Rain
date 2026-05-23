part of 'rain_runtime_controller.dart';

enum _IncomingVoiceInviteDisposition { accept, busy, ignore }

extension VoiceCallRuntime on RainRuntimeController {
  static const String _voiceCallFailedReasonCode = 'failed';
  static const String _voiceCallBusyReasonCode = 'busy';
  static const String _voiceCallRingingTimeoutReasonCode = 'ringingTimeout';
  static const String _voiceCallIceTimeoutReasonCode = 'iceTimeout';
  static const String _voiceCallNoRemoteAudioReasonCode = 'noRemoteAudio';
  static const String _voiceCallMicrophoneDeniedReasonCode = 'microphoneDenied';
  static const String _voiceCallMicrophonePermissionRequired =
      'Microphone permission required.';
  static const String _voiceCallRemoteMicrophonePermissionRequired =
      'Peer microphone permission required.';
  static const String _voiceCallFileTransferRequired =
      'Finish the active file transfer first.';
  static const String _voiceCallRingingTimedOut =
      'Call timed out while ringing.';
  static const String _voiceCallMediaIceTimeout =
      'Call media could not connect: ICE timeout.';
  static const String _voiceCallNoRemoteAudio =
      'Call media connected but no remote audio arrived.';
  static const String _voiceCallMediaFailed =
      'Call media could not connect. Try again.';

  Future<void> startVoiceCall(String username) async {
    final peerId = _normalizedUsername(username);
    _assertVoiceCallCanStart();
    if (await fileTransferStore.hasActiveTransferForPeer(peerId)) {
      throw StateError(_voiceCallFileTransferRequired);
    }

    await _disposeCurrentVoiceCallSession();
    final callId = _newVoiceCallId(peerId);
    _setVoiceCallState(
      VoiceCallState(
        phase: VoiceCallPhase.connectingPeer,
        peerId: peerId,
        callId: callId,
        isOutgoing: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        detail: 'Connecting peer before ringing.',
      ),
    );

    try {
      await connectPeer(
        peerId,
        interactive: true,
        waitForConnected: true,
        allowStalePresence: true,
        bypassRetryBackoff: true,
      );
      final session = await _createVoiceCallSession(
        peerId: peerId,
        callId: callId,
        sessionEpoch: _newVoiceCallSessionEpoch(),
        isOutgoing: true,
      );
      await session.startOutgoing();
    } catch (error) {
      await _failVoiceCall(
        error,
        failureReason: _localAudioFailureReason(error),
        detail: _localAudioFailureDetail(error),
      );
      rethrow;
    }
  }

  Future<void> acceptVoiceCall() async {
    final current = _voiceCallState;
    if (current.phase != VoiceCallPhase.incomingRinging ||
        current.peerId == null ||
        current.callId == null) {
      throw StateError('There is no incoming call to accept.');
    }
    if (await fileTransferStore.hasActiveTransferForPeer(current.peerId!)) {
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
        _voiceCallFileTransferRequired,
        failureReason: VoiceCallFailureReason.fileTransferActive,
        detail: _voiceCallFileTransferRequired,
      );
      return;
    }

    final session = _voiceCallSession;
    if (session == null || session.callId != current.callId) {
      await _failVoiceCall('Voice call session is unavailable.');
      throw StateError('Voice call session is unavailable.');
    }

    try {
      await session.acceptIncoming();
    } catch (error) {
      await _failVoiceCall(
        error,
        failureReason: _localAudioFailureReason(error),
        detail: _localAudioFailureDetail(error),
      );
      rethrow;
    }
  }

  Future<void> rejectVoiceCall() async {
    final current = _voiceCallState;
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
      bestEffort: true,
    );
    _setVoiceCallState(const VoiceCallState.idle());
  }

  Future<void> hangUpVoiceCall() async {
    final current = _voiceCallState;
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
    final session = _voiceCallSession;
    if (!current.isActive ||
        current.peerId == null ||
        current.callId == null ||
        session == null) {
      throw StateError('There is no active call to mute.');
    }
    await session.setMuted(muted: muted);
    _setVoiceCallState(
      current.copyWith(
        isMuted: muted,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  bool voiceCallBlocksFileTransfer(String peerId) {
    return _voiceCallState.blocksFileTransfersFor(_normalizedUsername(peerId));
  }

  Future<void> _handleVoiceCallFrame(
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

    if (!_isCurrentVoiceCall(normalizedPeerId, frame.callId)) {
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
        if (frame.reasonCode == _voiceCallMicrophoneDeniedReasonCode) {
          _setVoiceCallState(
            _voiceCallState.copyWith(
              phase: VoiceCallPhase.failed,
              detail: _voiceCallRemoteMicrophonePermissionRequired,
              failureReason: VoiceCallFailureReason.remoteMicrophoneDenied,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
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

  Future<void> _handleVoiceInvite(String peerId, VoiceCallFrame frame) async {
    final disposition = await _prepareIncomingVoiceInvite(peerId, frame);
    if (disposition == _IncomingVoiceInviteDisposition.ignore) {
      await _voiceCallSession?.handleFrame(frame);
      return;
    }
    if (disposition == _IncomingVoiceInviteDisposition.busy ||
        await fileTransferStore.hasActiveTransferForPeer(peerId)) {
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
    if (!current.hasCall || current.phase == VoiceCallPhase.failed) {
      return _IncomingVoiceInviteDisposition.accept;
    }

    final normalizedPeerId = _normalizedUsername(peerId);
    if (current.peerId != normalizedPeerId) {
      return _IncomingVoiceInviteDisposition.busy;
    }

    if (current.callId == frame.callId) {
      return _IncomingVoiceInviteDisposition.ignore;
    }

    if (!_canReplaceVoiceCallWithRetry(current)) {
      return _IncomingVoiceInviteDisposition.busy;
    }

    await _replaceStaleVoiceCallForRetry(current);
    return _IncomingVoiceInviteDisposition.accept;
  }

  bool _canReplaceVoiceCallWithRetry(VoiceCallState current) {
    return switch (current.phase) {
      VoiceCallPhase.idle || VoiceCallPhase.failed => true,
      VoiceCallPhase.connectingPeer ||
      VoiceCallPhase.outgoingRinging ||
      VoiceCallPhase.incomingRinging ||
      VoiceCallPhase.connectingMedia => true,
      VoiceCallPhase.active || VoiceCallPhase.ending => false,
    };
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
    if (!_isCurrentVoiceCall(peerId, frame.callId) || frame.muted == null) {
      return;
    }
    _setVoiceCallState(
      _voiceCallState.copyWith(
        isRemoteMuted: frame.muted,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<VoiceCallSession> _createVoiceCallSession({
    required String peerId,
    required String callId,
    required int sessionEpoch,
    required bool isOutgoing,
  }) async {
    final manager = brain;
    if (manager == null) {
      throw StateError('Peer connection is unavailable right now.');
    }

    await _disposeCurrentVoiceCallSession();
    final media = await manager.createVoiceMediaConnection(peerId);
    final session = VoiceCallSession(
      localPeerId: selfIdentity.username,
      remotePeerId: peerId,
      callId: callId,
      sessionEpoch: sessionEpoch,
      media: media,
      sendFrame: (VoiceCallFrame frame) => _sendVoiceFrameObject(peerId, frame),
      logger: (String message) {
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
    return session;
  }

  Future<void> _sendVoiceFrameObject(
    String peerId,
    VoiceCallFrame frame,
  ) async {
    final manager = brain;
    if (manager == null) {
      throw StateError('Peer connection is unavailable right now.');
    }
    manager.sendControl(peerId, frame.encode());
  }

  void _applyVoiceSessionState(
    VoiceCallSession session,
    VoiceCallSessionState sessionState, {
    required bool isOutgoing,
  }) {
    if (_voiceCallSession != session) {
      return;
    }
    final mappedPhase = _mapVoiceCallSessionPhase(sessionState.phase);
    final now = sessionState.updatedAt;
    final error = sessionState.error;
    final failureReason = _voiceCallFailureReasonForSessionState(sessionState);
    final detail = _voiceCallDetailForSessionState(sessionState);
    final startedAt = mappedPhase == VoiceCallPhase.active
        ? _voiceCallState.startedAt ?? now
        : _voiceCallState.startedAt;

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
        isOutgoing: isOutgoing,
        isMuted: _voiceCallState.isMuted,
        isRemoteMuted: _voiceCallState.isRemoteMuted,
        startedAt: startedAt,
        updatedAt: now,
        detail: detail,
        error: error,
        failureReason: failureReason,
      ),
    );

    if (mappedPhase == VoiceCallPhase.failed) {
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
    if (state.reasonCode == _voiceCallMicrophoneDeniedReasonCode) {
      return VoiceCallFailureReason.remoteMicrophoneDenied;
    }
    if (state.reasonCode == _voiceCallBusyReasonCode ||
        state.detail == 'Peer is busy.') {
      return VoiceCallFailureReason.peerBusy;
    }
    if (state.reasonCode == _voiceCallRingingTimeoutReasonCode ||
        state.detail == _voiceCallRingingTimedOut ||
        state.detail == 'Call timed out.') {
      return VoiceCallFailureReason.ringingTimeout;
    }
    if (state.reasonCode == _voiceCallIceTimeoutReasonCode ||
        state.detail == _voiceCallMediaIceTimeout) {
      return VoiceCallFailureReason.mediaIceTimeout;
    }
    if (state.reasonCode == _voiceCallNoRemoteAudioReasonCode ||
        state.detail == _voiceCallNoRemoteAudio) {
      return VoiceCallFailureReason.mediaNoRemoteAudio;
    }
    if (state.reasonCode == _voiceCallFailedReasonCode) {
      return VoiceCallFailureReason.mediaConnectionFailed;
    }
    final error = state.error;
    if (error != null) {
      return _localAudioFailureReason(error);
    }
    return null;
  }

  String? _voiceCallDetailForSessionState(VoiceCallSessionState state) {
    if (state.phase != VoiceCallSessionPhase.failed) {
      return state.detail;
    }
    if (state.reasonCode == _voiceCallMicrophoneDeniedReasonCode) {
      return _voiceCallRemoteMicrophonePermissionRequired;
    }
    if (state.reasonCode == _voiceCallBusyReasonCode ||
        state.detail == 'Peer is busy.') {
      return 'Peer is busy.';
    }
    if (state.reasonCode == _voiceCallRingingTimeoutReasonCode ||
        state.detail == 'Call timed out.') {
      return _voiceCallRingingTimedOut;
    }
    if (state.reasonCode == _voiceCallIceTimeoutReasonCode) {
      return _voiceCallMediaIceTimeout;
    }
    if (state.reasonCode == _voiceCallNoRemoteAudioReasonCode) {
      return _voiceCallNoRemoteAudio;
    }
    if (state.reasonCode == _voiceCallFailedReasonCode) {
      return _voiceCallMediaFailed;
    }
    final error = state.error;
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
    if (error != null && _localAudioFailureReason(error) != null) {
      return;
    }
    final detail =
        _voiceCallDetailForSessionState(state) ?? _voiceCallMediaFailed;
    final failureCode =
        state.reasonCode ??
        _voiceCallFailureReasonForSessionState(state)?.name ??
        'unknown';
    errorRecorder?.call(
      VoiceCallDiagnostics(
        callId: session.callId,
        peerId: session.remotePeerId,
        role: isOutgoing ? 'caller' : 'callee',
        failureCode: failureCode,
        userMessage: detail,
        nativeError:
            error?.toString() ??
            state.mediaDiagnostics?.lastError ??
            state.mediaDiagnostics?.lastDetail ??
            state.detail ??
            'No native error captured.',
        mediaStates: state.mediaDiagnostics?.mediaStates ?? const <String>[],
        iceStates:
            state.mediaDiagnostics?.iceConnectionStates ?? const <String>[],
        connectionStates:
            state.mediaDiagnostics?.peerConnectionStates ?? const <String>[],
        localCandidateCount: state.mediaDiagnostics?.localCandidateCount ?? 0,
        remoteCandidateCount: state.mediaDiagnostics?.remoteCandidateCount ?? 0,
        pendingRemoteCandidateCount:
            state.mediaDiagnostics?.pendingRemoteCandidateCount ?? 0,
      ),
      StackTrace.current,
      source: 'voice-call-media',
      fatal: false,
    );
  }

  Future<void> _disposeCurrentVoiceCallSession() async {
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
      await _voiceCallSessionSubscription?.cancel();
      _voiceCallSessionSubscription = null;
    }
    try {
      await session.dispose();
    } catch (_) {
      // Voice call cleanup is best effort once the call is terminal.
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
        ),
      );
    } catch (_) {
      if (!bestEffort) {
        rethrow;
      }
    }
  }

  Future<void> _endVoiceCallForPeer(
    String peerId, {
    required bool notifyPeer,
    required String detail,
  }) async {
    final current = _voiceCallState;
    if (current.peerId != _normalizedUsername(peerId)) {
      return;
    }
    final session = _voiceCallSession;
    if (session != null && current.callId == session.callId) {
      if (notifyPeer) {
        await session.hangUp(reason: detail);
      } else {
        _setVoiceCallState(
          current.copyWith(
            phase: VoiceCallPhase.ending,
            detail: detail,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        await _disposeVoiceCallSession(session);
        _setVoiceCallState(const VoiceCallState.idle());
      }
      return;
    }

    _setVoiceCallState(
      current.copyWith(
        phase: VoiceCallPhase.ending,
        detail: detail,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (notifyPeer && current.callId != null) {
      await _sendVoiceFrame(
        current.peerId!,
        VoiceCallFrameType.hangup,
        callId: current.callId!,
        reason: detail,
        bestEffort: true,
      );
    }
    _setVoiceCallState(const VoiceCallState.idle());
  }

  void _failVoiceCallForPeer(String peerId, String message) {
    if (_voiceCallState.peerId != _normalizedUsername(peerId)) {
      return;
    }
    unawaited(_failVoiceCall(message));
  }

  void _markVoiceCallReconnectingForPeer(String peerId) {
    final current = _voiceCallState;
    if (current.peerId != _normalizedUsername(peerId) ||
        current.phase == VoiceCallPhase.idle ||
        current.phase == VoiceCallPhase.failed ||
        current.phase == VoiceCallPhase.ending) {
      return;
    }
    _setVoiceCallState(
      current.copyWith(
        detail: 'Peer connection interrupted. Reconnecting...',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        clearError: true,
      ),
    );
  }

  Future<void> _failVoiceCall(
    Object error, {
    VoiceCallFailureReason? failureReason,
    String? detail,
  }) async {
    final current = _voiceCallState;
    await _disposeCurrentVoiceCallSession();
    _setVoiceCallState(
      current.copyWith(
        phase: VoiceCallPhase.failed,
        detail: detail ?? _voiceCallErrorMessage(error),
        error: error,
        failureReason: failureReason,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void _assertVoiceCallCanStart() {
    if (brain == null) {
      throw StateError('Peer connection is unavailable right now.');
    }
    if (_voiceCallState.hasCall &&
        _voiceCallState.phase != VoiceCallPhase.failed) {
      throw StateError('Finish the active call before starting another.');
    }
  }

  bool _isCurrentVoiceCall(String peerId, String callId) {
    return _voiceCallState.peerId == _normalizedUsername(peerId) &&
        _voiceCallState.callId == callId;
  }

  void _setVoiceCallState(VoiceCallState state) {
    _voiceCallState = state;
    if (!_voiceCallStateController.isClosed) {
      _voiceCallStateController.add(state);
    }
  }

  String _newVoiceCallId(String peerId) {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '${_normalizedUsername(selfIdentity.username)}:$peerId:$now';
  }

  int _newVoiceCallSessionEpoch() {
    return DateTime.now().microsecondsSinceEpoch;
  }

  String _voiceCallErrorMessage(Object error) {
    final raw = error.toString().trim();
    const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
    var message = raw;
    for (final prefix in prefixes) {
      if (raw.startsWith(prefix)) {
        message = raw.substring(prefix.length).trim();
        break;
      }
    }
    final normalized = message.toLowerCase();
    if (normalized.contains('ice timeout')) {
      return _voiceCallMediaIceTimeout;
    }
    if (normalized.contains('no remote audio')) {
      return _voiceCallNoRemoteAudio;
    }
    if (normalized.contains('rtcrtptransceiver') ||
        normalized.contains('setdirection') ||
        normalized.contains('setremotedescription') ||
        normalized.contains('peerconnectionsetremotedescription') ||
        normalized.contains('m-line') ||
        normalized.contains('peer connection changed while')) {
      return _voiceCallMediaFailed;
    }
    return message;
  }

  VoiceCallFailureReason? _localAudioFailureReason(Object error) {
    final normalized = error.toString().toLowerCase();
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
    return _localAudioFailureReason(error) ==
            VoiceCallFailureReason.microphoneDenied
        ? _voiceCallMicrophonePermissionRequired
        : null;
  }
}
