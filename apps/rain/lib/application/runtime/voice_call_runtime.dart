part of 'rain_runtime_controller.dart';

extension VoiceCallRuntime on RainRuntimeController {
  static const Duration _voiceCallInviteTimeout = Duration(seconds: 45);

  Future<void> startVoiceCall(String username) async {
    final peerId = _normalizedUsername(username);
    _assertVoiceCallCanStart();
    if (await fileTransferStore.hasActiveTransferForPeer(peerId)) {
      throw StateError('Finish the active file transfer before calling.');
    }

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
      _setVoiceCallState(
        _voiceCallState.copyWith(
          phase: VoiceCallPhase.outgoingRinging,
          detail: 'Ringing @$peerId.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          clearError: true,
        ),
      );
      _armVoiceCallTimeout(callId);
      _sendVoiceFrame(peerId, VoiceCallFrameType.invite, callId: callId);
    } catch (error) {
      await _failVoiceCall(error);
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
      await _sendVoiceFrame(
        current.peerId!,
        VoiceCallFrameType.reject,
        callId: current.callId!,
        reason: _voiceCallErrorMessage(error),
        bestEffort: true,
      );
      await _failVoiceCall(error);
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
      case VoiceCallFrameType.hangup:
        await _handleVoiceHangup(normalizedPeerId, frame);
        break;
      case VoiceCallFrameType.mute:
        _handleVoiceMute(normalizedPeerId, frame);
        break;
    }
  }

  Future<void> _handleVoiceInvite(String peerId, VoiceCallFrame frame) async {
    if (!_voiceCallCanReceiveInvite(peerId) ||
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
      await _failVoiceCall(error);
    }
  }

  Future<void> _handleVoiceRejected(String peerId, VoiceCallFrame frame) async {
    if (!_isCurrentVoiceCall(peerId, frame.callId)) {
      return;
    }
    final message = frame.type == VoiceCallFrameType.busy
        ? 'Peer is busy.'
        : frame.reason ?? 'Call rejected.';
    await _failVoiceCall(message);
  }

  Future<void> _handleVoiceOffer(String peerId, VoiceCallFrame frame) async {
    if (!_isCurrentVoiceCall(peerId, frame.callId) ||
        frame.sdp == null ||
        frame.sdpType != 'offer') {
      return;
    }
    _clearVoiceCallTimer();
    _setVoiceCallState(
      _voiceCallState.copyWith(
        phase: VoiceCallPhase.connectingMedia,
        detail: 'Answering voice media.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        clearError: true,
      ),
    );
    try {
      await brain!.startLocalAudio(peerId);
      final answer = await brain!.applyMediaOffer(
        peerId,
        RTCSessionDescription(frame.sdp, frame.sdpType),
      );
      await _sendVoiceFrame(
        peerId,
        VoiceCallFrameType.answer,
        callId: frame.callId,
        sdp: answer.sdp,
        sdpType: answer.type,
      );
      _activateVoiceCall('Voice call connected.');
    } catch (error) {
      await _sendVoiceFrame(
        peerId,
        VoiceCallFrameType.hangup,
        callId: frame.callId,
        reason: _voiceCallErrorMessage(error),
        bestEffort: true,
      );
      await _failVoiceCall(error);
    }
  }

  Future<void> _handleVoiceAnswer(String peerId, VoiceCallFrame frame) async {
    if (!_isCurrentVoiceCall(peerId, frame.callId) ||
        frame.sdp == null ||
        frame.sdpType != 'answer') {
      return;
    }
    try {
      await brain!.applyMediaAnswer(
        peerId,
        RTCSessionDescription(frame.sdp, frame.sdpType),
      );
      _activateVoiceCall('Voice call connected.');
    } catch (error) {
      await _failVoiceCall(error);
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
      ),
    );
    final offer = await brain!.createMediaOffer(peerId);
    await _sendVoiceFrame(
      peerId,
      VoiceCallFrameType.offer,
      callId: callId,
      sdp: offer.sdp,
      sdpType: offer.type,
    );
  }

  Future<void> _sendVoiceFrame(
    String peerId,
    VoiceCallFrameType type, {
    required String callId,
    String? reason,
    bool? muted,
    String? sdp,
    String? sdpType,
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
          muted: muted,
          sdp: sdp,
          sdpType: sdpType,
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
    _setVoiceCallState(const VoiceCallState.idle());
  }

  void _failVoiceCallForPeer(String peerId, String message) {
    if (_voiceCallState.peerId != _normalizedUsername(peerId)) {
      return;
    }
    unawaited(_failVoiceCall(message));
  }

  Future<void> _failVoiceCall(Object error) async {
    _clearVoiceCallTimer();
    final current = _voiceCallState;
    if (current.peerId != null) {
      try {
        await brain?.stopLocalAudio(current.peerId!);
      } catch (_) {}
    }
    _setVoiceCallState(
      current.copyWith(
        phase: VoiceCallPhase.failed,
        detail: _voiceCallErrorMessage(error),
        error: error,
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

  bool _voiceCallCanReceiveInvite(String peerId) {
    return !_shutDown &&
        _started &&
        (!_voiceCallState.hasCall ||
            _voiceCallState.phase == VoiceCallPhase.failed);
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
    for (final prefix in prefixes) {
      if (raw.startsWith(prefix)) {
        return raw.substring(prefix.length).trim();
      }
    }
    return raw;
  }
}
