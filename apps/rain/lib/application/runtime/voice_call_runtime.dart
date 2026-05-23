part of 'rain_runtime_controller.dart';

enum _IncomingVoiceInviteDisposition { accept, busy, ignore }

extension VoiceCallRuntime on RainRuntimeController {
  static const Duration _voiceCallInviteTimeout = Duration(seconds: 45);
  static const String _voiceCallFailedReasonCode = 'failed';
  static const String _voiceCallMicrophoneDeniedReasonCode = 'microphoneDenied';
  static const String _voiceCallMicrophonePermissionRequired =
      'Microphone permission required.';
  static const String _voiceCallRemoteMicrophonePermissionRequired =
      'Peer microphone permission required.';

  Future<void> startVoiceCall(String username) async {
    final peerId = _normalizedUsername(username);
    _assertVoiceCallCanStart();
    if (await fileTransferStore.hasActiveTransferForPeer(peerId)) {
      throw StateError('Finish the active file transfer before calling.');
    }

    final callId = _newVoiceCallId(peerId);
    _clearVoiceMediaTracking(peerId, callId);
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
      _setVoiceCallState(
        _voiceCallState.copyWith(
          phase: VoiceCallPhase.connectingMedia,
          detail: 'Checking microphone permission.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          clearError: true,
          clearFailureReason: true,
        ),
      );
      await brain!.startLocalAudio(peerId);
      _setVoiceCallState(
        _voiceCallState.copyWith(
          phase: VoiceCallPhase.outgoingRinging,
          detail: 'Ringing @$peerId.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          clearError: true,
          clearFailureReason: true,
        ),
      );
      _armVoiceCallTimeout(callId);
      await _sendVoiceFrame(peerId, VoiceCallFrameType.invite, callId: callId);
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
        reason: 'Finish the active file transfer before calling.',
        bestEffort: true,
      );
      await _failVoiceCall('Finish the active file transfer before calling.');
      return;
    }

    _clearVoiceCallTimer();
    _setVoiceCallState(
      current.copyWith(
        phase: VoiceCallPhase.connectingMedia,
        detail: 'Starting microphone.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        clearError: true,
        clearFailureReason: true,
      ),
    );

    try {
      await brain!.startLocalAudio(current.peerId!);
      await _sendVoiceFrame(
        current.peerId!,
        VoiceCallFrameType.accept,
        callId: current.callId!,
      );
      await _createVoiceMediaOfferIfOwner(current.peerId!, current.callId!);
    } catch (error) {
      final microphoneFailureReason = _localAudioFailureReason(error);
      await _sendVoiceFrame(
        current.peerId!,
        VoiceCallFrameType.reject,
        callId: current.callId!,
        reason:
            _localAudioFailureDetail(error) ?? _voiceCallErrorMessage(error),
        reasonCode:
            microphoneFailureReason == VoiceCallFailureReason.microphoneDenied
            ? _voiceCallMicrophoneDeniedReasonCode
            : null,
        bestEffort: true,
      );
      await _failVoiceCall(
        error,
        failureReason: microphoneFailureReason,
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
    await _sendVoiceFrame(
      current.peerId!,
      VoiceCallFrameType.reject,
      callId: current.callId!,
      reason: 'Rejected.',
      bestEffort: true,
    );
    _clearVoiceCallTimer();
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
    if (!current.isActive || current.peerId == null || current.callId == null) {
      throw StateError('There is no active call to mute.');
    }
    await brain!.setMicrophoneMuted(current.peerId!, muted: muted);
    _setVoiceCallState(
      current.copyWith(
        isMuted: muted,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _sendVoiceFrame(
      current.peerId!,
      VoiceCallFrameType.mute,
      callId: current.callId!,
      muted: muted,
      bestEffort: true,
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

    switch (frame.type) {
      case VoiceCallFrameType.invite:
        await _handleVoiceInvite(normalizedPeerId, frame);
        break;
      case VoiceCallFrameType.accept:
        await _handleVoiceAccept(normalizedPeerId, frame);
        break;
      case VoiceCallFrameType.reject:
      case VoiceCallFrameType.busy:
        await _handleVoiceRejected(normalizedPeerId, frame);
        break;
      case VoiceCallFrameType.offer:
        await _handleVoiceOffer(normalizedPeerId, frame);
        break;
      case VoiceCallFrameType.answer:
        await _handleVoiceAnswer(normalizedPeerId, frame);
        break;
      case VoiceCallFrameType.candidate:
        break;
      case VoiceCallFrameType.hangup:
        await _handleVoiceHangup(normalizedPeerId, frame);
        break;
      case VoiceCallFrameType.mute:
        _handleVoiceMute(normalizedPeerId, frame);
        break;
    }
  }

  Future<void> _handleVoiceInvite(String peerId, VoiceCallFrame frame) async {
    final disposition = await _prepareIncomingVoiceInvite(peerId, frame);
    if (disposition == _IncomingVoiceInviteDisposition.ignore) {
      return;
    }
    if (disposition == _IncomingVoiceInviteDisposition.busy ||
        await fileTransferStore.hasActiveTransferForPeer(peerId)) {
      await _sendVoiceFrame(
        peerId,
        VoiceCallFrameType.busy,
        callId: frame.callId,
        reason: 'Busy.',
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
        reason: 'Only accepted friends can call.',
        bestEffort: true,
      );
      return;
    }
    _clearVoiceMediaTracking(peerId, frame.callId);
    _setVoiceCallState(
      VoiceCallState(
        phase: VoiceCallPhase.incomingRinging,
        peerId: peerId,
        callId: frame.callId,
        isOutgoing: false,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        detail: '@$peerId is calling.',
      ),
    );
    _armVoiceCallTimeout(frame.callId);
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
      _armVoiceCallTimeout(frame.callId);
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
      _setVoiceCallState(const VoiceCallState.idle());
      return;
    }

    _clearVoiceCallTimer();
    if (current.callId != null) {
      await _sendVoiceFrame(
        peerId,
        VoiceCallFrameType.hangup,
        callId: current.callId!,
        reason: 'Replaced by newer voice call invite.',
        bestEffort: true,
      );
      _clearVoiceMediaTracking(peerId, current.callId!);
    }
    try {
      await brain?.stopLocalAudio(peerId);
    } catch (_) {}
    _setVoiceCallState(const VoiceCallState.idle());
  }

  Future<void> _handleVoiceAccept(String peerId, VoiceCallFrame frame) async {
    if (!_isCurrentVoiceCall(peerId, frame.callId) ||
        _voiceCallState.phase != VoiceCallPhase.outgoingRinging) {
      return;
    }
    _clearVoiceCallTimer();
    _setVoiceCallState(
      _voiceCallState.copyWith(
        phase: VoiceCallPhase.connectingMedia,
        detail: 'Starting microphone.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        clearError: true,
        clearFailureReason: true,
      ),
    );
    try {
      await brain!.startLocalAudio(peerId);
      await _createVoiceMediaOfferIfOwner(peerId, frame.callId);
    } catch (error) {
      await _sendVoiceFrame(
        peerId,
        VoiceCallFrameType.hangup,
        callId: frame.callId,
        reason: _voiceCallErrorMessage(error),
        bestEffort: true,
      );
      await _failVoiceCall(
        error,
        failureReason: _localAudioFailureReason(error),
        detail: _localAudioFailureDetail(error),
      );
    }
  }

  Future<void> _handleVoiceRejected(String peerId, VoiceCallFrame frame) async {
    if (!_isCurrentVoiceCall(peerId, frame.callId)) {
      return;
    }
    final message = frame.type == VoiceCallFrameType.busy
        ? 'Peer is busy.'
        : _voiceCallRejectedMessage(frame);
    await _failVoiceCall(
      message,
      failureReason: frame.reasonCode == _voiceCallMicrophoneDeniedReasonCode
          ? VoiceCallFailureReason.remoteMicrophoneDenied
          : null,
      detail: message,
    );
  }

  Future<void> _handleVoiceOffer(String peerId, VoiceCallFrame frame) async {
    if (!_isCurrentVoiceCall(peerId, frame.callId) ||
        frame.sdp == null ||
        frame.sdpType != 'offer' ||
        !_acceptIncomingVoiceMediaFrame(peerId, frame)) {
      return;
    }
    if (!_beginVoiceMediaNegotiation(peerId)) {
      return;
    }
    _clearVoiceCallTimer();
    _setVoiceCallState(
      _voiceCallState.copyWith(
        phase: VoiceCallPhase.connectingMedia,
        detail: 'Answering voice media.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        clearError: true,
        clearFailureReason: true,
      ),
    );
    try {
      await brain!.startLocalAudio(peerId);
      final answer = await brain!.applyMediaOffer(
        peerId,
        RTCSessionDescription(frame.sdp, frame.sdpType),
      );
      if (!_isCurrentVoiceCall(peerId, frame.callId) ||
          _voiceCallState.phase == VoiceCallPhase.failed) {
        return;
      }
      await _sendVoiceFrame(
        peerId,
        VoiceCallFrameType.answer,
        callId: frame.callId,
        sdp: answer.sdp,
        sdpType: answer.type,
        mediaSeq: frame.mediaSeq,
      );
      _activateVoiceCall('Voice call connected.');
    } catch (error, stackTrace) {
      _recordVoiceCallMediaError(
        peerId: peerId,
        callId: frame.callId,
        action: 'apply-media-offer',
        error: error,
        stackTrace: stackTrace,
      );
      await _sendVoiceFailedHangup(peerId, callId: frame.callId, error: error);
      await _failVoiceCall(error);
    } finally {
      _endVoiceMediaNegotiation(peerId);
    }
  }

  Future<void> _handleVoiceAnswer(String peerId, VoiceCallFrame frame) async {
    if (!_isCurrentVoiceCall(peerId, frame.callId) ||
        frame.sdp == null ||
        frame.sdpType != 'answer' ||
        !_acceptExpectedVoiceMediaAnswer(peerId, frame)) {
      return;
    }
    try {
      await brain!.applyMediaAnswer(
        peerId,
        RTCSessionDescription(frame.sdp, frame.sdpType),
      );
      if (!_isCurrentVoiceCall(peerId, frame.callId) ||
          _voiceCallState.phase == VoiceCallPhase.failed) {
        return;
      }
      _activateVoiceCall('Voice call connected.');
    } catch (error, stackTrace) {
      _recordVoiceCallMediaError(
        peerId: peerId,
        callId: frame.callId,
        action: 'apply-media-answer',
        error: error,
        stackTrace: stackTrace,
      );
      await _sendVoiceFailedHangup(peerId, callId: frame.callId, error: error);
      await _failVoiceCall(error);
    } finally {
      _endVoiceMediaNegotiation(peerId);
    }
  }

  Future<void> _handleVoiceHangup(String peerId, VoiceCallFrame frame) async {
    if (!_isCurrentVoiceCall(peerId, frame.callId)) {
      return;
    }
    await _endVoiceCallForPeer(
      peerId,
      notifyPeer: false,
      detail: frame.reason ?? 'Peer ended the call.',
    );
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

  Future<void> _createVoiceMediaOfferIfOwner(
    String peerId,
    String callId,
  ) async {
    final session = brain!.getSession(peerId);
    if (session?.isOfferOwner != true) {
      _setVoiceCallState(
        _voiceCallState.copyWith(
          detail: 'Waiting for voice media offer.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      return;
    }
    _setVoiceCallState(
      _voiceCallState.copyWith(
        phase: VoiceCallPhase.connectingMedia,
        detail: 'Creating voice media offer.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        clearFailureReason: true,
      ),
    );
    if (!_beginVoiceMediaNegotiation(peerId)) {
      return;
    }
    final mediaSeq = _nextVoiceMediaSequence(peerId, callId);
    try {
      final offer = await brain!.createMediaOffer(peerId);
      if (!_isCurrentVoiceCall(peerId, callId) ||
          _voiceCallState.phase == VoiceCallPhase.failed) {
        _endVoiceMediaNegotiation(peerId);
        return;
      }
      await _sendVoiceFrame(
        peerId,
        VoiceCallFrameType.offer,
        callId: callId,
        sdp: offer.sdp,
        sdpType: offer.type,
        mediaSeq: mediaSeq,
      );
    } catch (error, stackTrace) {
      _recordVoiceCallMediaError(
        peerId: peerId,
        callId: callId,
        action: 'create-media-offer',
        error: error,
        stackTrace: stackTrace,
      );
      await _sendVoiceFailedHangup(peerId, callId: callId, error: error);
      await _failVoiceCall(error);
      _endVoiceMediaNegotiation(peerId);
    }
  }

  bool _beginVoiceMediaNegotiation(String peerId) {
    final normalizedPeerId = _normalizedUsername(peerId);
    if (_voiceMediaNegotiatingPeers.contains(normalizedPeerId)) {
      _setVoiceCallState(
        _voiceCallState.copyWith(
          detail: 'Voice media negotiation is already running.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      return false;
    }
    _voiceMediaNegotiatingPeers.add(normalizedPeerId);
    return true;
  }

  void _endVoiceMediaNegotiation(String peerId) {
    _voiceMediaNegotiatingPeers.remove(_normalizedUsername(peerId));
  }

  int _nextVoiceMediaSequence(String peerId, String callId) {
    final key = _voiceMediaKey(peerId, callId);
    final next = (_voiceMediaSentSequences[key] ?? 0) + 1;
    _voiceMediaSentSequences[key] = next;
    return next;
  }

  bool _acceptIncomingVoiceMediaFrame(String peerId, VoiceCallFrame frame) {
    final mediaSeq = frame.mediaSeq;
    if (mediaSeq == null) {
      return false;
    }
    final key = _voiceMediaKey(peerId, frame.callId);
    final previous = _voiceMediaReceivedSequences[key] ?? 0;
    if (mediaSeq <= previous) {
      return false;
    }
    _voiceMediaReceivedSequences[key] = mediaSeq;
    return true;
  }

  bool _acceptExpectedVoiceMediaAnswer(String peerId, VoiceCallFrame frame) {
    final mediaSeq = frame.mediaSeq;
    if (mediaSeq == null) {
      return false;
    }
    final key = _voiceMediaKey(peerId, frame.callId);
    final expected = _voiceMediaSentSequences[key];
    final previous = _voiceMediaReceivedSequences[key] ?? 0;
    if (expected == null || mediaSeq != expected || mediaSeq <= previous) {
      return false;
    }
    _voiceMediaReceivedSequences[key] = mediaSeq;
    return true;
  }

  void _clearVoiceMediaTracking(String peerId, String callId) {
    final key = _voiceMediaKey(peerId, callId);
    _voiceMediaNegotiatingPeers.remove(_normalizedUsername(peerId));
    _voiceMediaSentSequences.remove(key);
    _voiceMediaReceivedSequences.remove(key);
  }

  String _voiceMediaKey(String peerId, String callId) {
    return '${_normalizedUsername(peerId)}::$callId';
  }

  Future<void> _sendVoiceFailedHangup(
    String peerId, {
    required String callId,
    required Object error,
  }) {
    return _sendVoiceFrame(
      peerId,
      VoiceCallFrameType.hangup,
      callId: callId,
      reason: _voiceCallErrorMessage(error),
      reasonCode: _voiceCallFailedReasonCode,
      bestEffort: true,
    );
  }

  void _recordVoiceCallMediaError({
    required String peerId,
    required String callId,
    required String action,
    required Object error,
    required StackTrace stackTrace,
  }) {
    errorRecorder?.call(
      StateError(
        'Voice call media negotiation failed '
        'action=$action peer=$peerId callId=$callId error=$error',
      ),
      stackTrace,
      source: 'voice-call-media',
      fatal: false,
    );
  }

  Future<void> _sendVoiceFrame(
    String peerId,
    VoiceCallFrameType type, {
    required String callId,
    String? reason,
    String? reasonCode,
    bool? muted,
    String? sdp,
    String? sdpType,
    int? mediaSeq,
    bool bestEffort = false,
  }) async {
    try {
      final manager = brain;
      if (manager == null) {
        throw StateError('Peer connection is unavailable right now.');
      }
      manager.sendControl(
        peerId,
        VoiceCallFrame(
          type: type,
          callId: callId,
          from: _normalizedUsername(selfIdentity.username),
          to: peerId,
          sentAt: DateTime.now().millisecondsSinceEpoch,
          reason: reason,
          reasonCode: reasonCode,
          muted: muted,
          sdp: sdp,
          sdpType: sdpType,
          mediaSeq: mediaSeq,
        ).encode(),
      );
    } catch (_) {
      if (!bestEffort) {
        rethrow;
      }
    }
  }

  void _activateVoiceCall(String detail) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _clearVoiceCallTimer();
    _setVoiceCallState(
      _voiceCallState.copyWith(
        phase: VoiceCallPhase.active,
        detail: detail,
        startedAt: _voiceCallState.startedAt ?? now,
        updatedAt: now,
        clearError: true,
        clearFailureReason: true,
      ),
    );
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
    _clearVoiceCallTimer();
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
    await brain?.stopLocalAudio(current.peerId!);
    if (current.callId != null) {
      _clearVoiceMediaTracking(current.peerId!, current.callId!);
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
    _clearVoiceCallTimer();
    final current = _voiceCallState;
    if (current.peerId != null) {
      try {
        await brain?.stopLocalAudio(current.peerId!);
      } catch (_) {}
    }
    if (current.peerId != null && current.callId != null) {
      _clearVoiceMediaTracking(current.peerId!, current.callId!);
    }
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

  void _armVoiceCallTimeout(String callId) {
    _clearVoiceCallTimer();
    _voiceCallTimer = Timer(_voiceCallInviteTimeout, () {
      final current = _voiceCallState;
      if (current.callId != callId || !current.isRinging) {
        return;
      }
      unawaited(_failVoiceCall('Call timed out.'));
    });
  }

  void _clearVoiceCallTimer() {
    _voiceCallTimer?.cancel();
    _voiceCallTimer = null;
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
    if (normalized.contains('rtcrtptransceiver') ||
        normalized.contains('setdirection') ||
        normalized.contains('setremotedescription') ||
        normalized.contains('peerconnectionsetremotedescription') ||
        normalized.contains('m-line') ||
        normalized.contains('peer connection changed while')) {
      return 'Voice call media could not connect. Try again.';
    }
    return message;
  }

  String _voiceCallRejectedMessage(VoiceCallFrame frame) {
    if (frame.reasonCode == _voiceCallMicrophoneDeniedReasonCode) {
      return _voiceCallRemoteMicrophonePermissionRequired;
    }
    return frame.reason ?? 'Call rejected.';
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
