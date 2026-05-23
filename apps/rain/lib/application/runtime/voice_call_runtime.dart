part of 'rain_runtime_controller.dart';

enum _IncomingVoiceInviteDisposition { accept, busy, ignore }

extension VoiceCallRuntime on RainRuntimeController {
  static const String _voiceCallFailedReasonCode = 'failed';
  static const String _voiceCallBusyReasonCode = 'busy';
  static const String _voiceCallRejectedReasonCode = 'rejected';
  static const String _voiceCallSignalingFailedReasonCode = 'signalingFailed';
  static const String _voiceCallNetworkLostReasonCode = 'networkLost';
  static const String _voiceCallExpiredReasonCode = 'expired';
  static const String _voiceCallRingingTimeoutReasonCode = 'ringingTimeout';
  static const String _voiceCallIceTimeoutReasonCode = 'iceTimeout';
  static const String _voiceCallNoRemoteAudioReasonCode = 'noRemoteAudio';
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
  static const String _voiceCallAudioRouteUnavailable =
      'Audio route unavailable.';
  static bool get _legacyControlChannelVoiceSignalingFrozen => true;
  static const Duration _voiceCallExpiry = Duration(minutes: 2);
  static const int _voiceCallTerminalSeq = 1 << 30;

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
    if (await fileTransferStore.hasActiveTransferForPeer(peerId)) {
      throw StateError(_voiceCallFileTransferRequired);
    }

    _assertVoiceCallCanStart();
    await _assertVoiceCallPeerIsFriend(peerId);

    await _disposeCurrentVoiceCallSession();
    final callId = _newVoiceCallId(peerId);
    final sessionEpoch = DateTime.now().millisecondsSinceEpoch;
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
    final current = _voiceCallState;
    final session = _voiceCallSession;
    if (!current.isActive ||
        current.peerId == null ||
        current.callId == null ||
        session == null) {
      throw StateError('There is no active call to route audio.');
    }
    try {
      await session.setAudioOutputRoute(_voiceMediaOutputRoute(route));
      if (!_isCurrentVoiceCall(
        current.peerId!,
        current.callId!,
        sessionEpoch: current.sessionEpoch,
      )) {
        return;
      }
      _setVoiceCallState(
        _voiceCallState.copyWith(
          outputRoute: route,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          clearOutputRouteWarning: true,
        ),
      );
    } catch (error, stackTrace) {
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
    if (entry.status.isTerminal) {
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
        room.isTerminal ||
        room.caller != peerId ||
        room.callee != localUsername) {
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
    final disposition = await _prepareIncomingVoiceInvite(peerId, frame);
    if (disposition == _IncomingVoiceInviteDisposition.ignore) {
      await _voiceCallSession?.handleFrame(frame);
      return;
    }
    if (disposition == _IncomingVoiceInviteDisposition.busy ||
        await fileTransferStore.hasActiveTransferForPeer(peerId)) {
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

    _voiceSignalingSubscriptions.add(
      voiceAdapter
          .watchCall(session.callId)
          .listen(
            (VoiceCallRoom? room) async {
              if (room == null || !_isLiveVoiceCallSession(session)) {
                return;
              }
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
        if (room.endedBy == localUsername &&
            (_voiceCallState.phase == VoiceCallPhase.idle ||
                _voiceCallState.phase == VoiceCallPhase.ending)) {
          return;
        }
        await session.handleFrame(
          _terminalVoiceFrameFromRoom(
            room: room,
            from: peerId,
            to: localUsername,
          ),
        );
        break;
    }
  }

  VoiceCallFrame _terminalVoiceFrameFromRoom({
    required VoiceCallRoom room,
    required String from,
    required String to,
  }) {
    final type = switch (room.status) {
      VoiceCallSignalingStatus.failed
          when room.reasonCode == _voiceCallBusyReasonCode =>
        VoiceCallFrameType.busy,
      VoiceCallSignalingStatus.failed
          when room.reasonCode == _voiceCallMicrophoneDeniedReasonCode =>
        VoiceCallFrameType.reject,
      VoiceCallSignalingStatus.failed
          when room.reasonCode == _voiceCallCameraDeniedReasonCode =>
        VoiceCallFrameType.reject,
      VoiceCallSignalingStatus.failed
          when room.reasonCode == _voiceCallRejectedReasonCode =>
        VoiceCallFrameType.reject,
      VoiceCallSignalingStatus.failed => VoiceCallFrameType.hangup,
      VoiceCallSignalingStatus.expired => VoiceCallFrameType.hangup,
      VoiceCallSignalingStatus.ended => VoiceCallFrameType.hangup,
      VoiceCallSignalingStatus.ringing ||
      VoiceCallSignalingStatus.accepted ||
      VoiceCallSignalingStatus.negotiating ||
      VoiceCallSignalingStatus.connected => VoiceCallFrameType.hangup,
    };
    return VoiceCallFrame(
      type: type,
      callId: room.callId,
      from: from,
      to: to,
      sentAt: room.endedAt ?? room.updatedAt,
      seq: _voiceCallTerminalSeq,
      sessionEpoch: room.createdAt,
      reason: room.reason ?? _terminalVoiceCallReason(room.status),
      reasonCode: room.reasonCode ?? _terminalVoiceCallReasonCode(room.status),
    );
  }

  String? _terminalVoiceCallReason(VoiceCallSignalingStatus status) {
    return switch (status) {
      VoiceCallSignalingStatus.expired => _voiceCallTimedOut,
      _ => null,
    };
  }

  String? _terminalVoiceCallReasonCode(VoiceCallSignalingStatus status) {
    return switch (status) {
      VoiceCallSignalingStatus.expired => _voiceCallExpiredReasonCode,
      VoiceCallSignalingStatus.failed => _voiceCallFailedReasonCode,
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
      VoiceCallFailureReason.videoFirstFrameTimeout =>
        _voiceCallFailedReasonCode,
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
    switch (frame.type) {
      case VoiceCallFrameType.invite:
        await voiceAdapter.createOutgoingCall(
          callId: frame.callId,
          caller: localUsername,
          callee: _normalizedUsername(peerId),
          createdAt: frame.sessionEpoch,
          expiresAt: frame.sessionEpoch + _voiceCallExpiry.inMilliseconds,
          mediaMode: frame.mediaMode,
        );
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
  }

  void _applyVoiceSessionState(
    VoiceCallSession session,
    VoiceCallSessionState sessionState, {
    required bool isOutgoing,
  }) {
    if (!_isLiveVoiceCallSession(session)) {
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
    final now = sessionState.updatedAt;
    final error = sessionState.error;
    final failureReason = _voiceCallFailureReasonForSessionState(sessionState);
    final detail = _voiceCallDetailForSessionState(sessionState);
    final startedAt = mappedPhase == VoiceCallPhase.active
        ? _voiceCallState.startedAt ?? now
        : _voiceCallState.startedAt;
    final keepsLocalAudioControls = mappedPhase == VoiceCallPhase.active;

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
        isMuted: _voiceCallState.isMuted,
        isCameraMuted: _voiceCallState.isCameraMuted,
        isDeafened: keepsLocalAudioControls && _voiceCallState.isDeafened,
        isRemoteMuted: sessionState.isRemoteMuted,
        isRemoteCameraMuted: sessionState.isRemoteCameraMuted,
        hasLocalVideo: _voiceCallState.hasLocalVideo,
        hasRemoteVideo: _voiceCallState.hasRemoteVideo,
        videoFirstFrameTimedOut: _voiceCallState.videoFirstFrameTimedOut,
        outputRoute: keepsLocalAudioControls
            ? _voiceCallState.outputRoute
            : VoiceCallOutputRoute.systemDefault,
        outputRouteWarning: keepsLocalAudioControls
            ? _voiceCallState.outputRouteWarning
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
      return 'Peer is busy.';
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
        sessionEpoch: session.sessionEpoch,
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
    _videoCallMediaConnection = media;
    final renderers = VideoCallRenderers(
      rendererFactory: videoCallRendererFactory,
    );
    _videoCallRenderers = renderers;
    _videoCallRendererSubscription = renderers.onStateChanged.listen(
      _handleVideoRendererState,
      onError: (Object error, StackTrace stackTrace) {
        errorRecorder?.call(
          error,
          stackTrace,
          source: 'video-call-renderer',
          fatal: false,
        );
      },
    );
    return _VideoVoiceMediaConnection(
      media: media,
      renderers: renderers,
      kind: CallMediaKind.video,
      onError: (Object error, StackTrace stackTrace) {
        errorRecorder?.call(
          error,
          stackTrace,
          source: 'video-call-renderer',
          fatal: false,
        );
      },
    );
  }

  void _handleVideoRendererState(VideoCallRendererState rendererState) {
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
    _videoCallRenderers = null;
    _videoCallMediaConnection = null;
    await _videoCallRendererSubscription?.cancel();
    _videoCallRendererSubscription = null;
    if (renderers == null) {
      return;
    }
    try {
      await renderers.dispose();
    } catch (error, stackTrace) {
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
    try {
      await _requireVoiceSignalingAdapter().endCall(
        callId: callId,
        username: _normalizedUsername(selfIdentity.username),
        status: status,
        endedAt: DateTime.now().millisecondsSinceEpoch,
        reason: reason,
        reasonCode: reasonCode,
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
    VoiceCallFailureReason? failureReason,
    String? failureDetail,
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
          current.copyWith(
            phase: VoiceCallPhase.ending,
            detail: detail,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
            audioLevel: const VoiceAudioLevel.unavailable(),
          ),
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
    if (notifyPeer && current.callId != null) {
      await _sendVoiceFrame(
        current.peerId!,
        VoiceCallFrameType.hangup,
        callId: current.callId!,
        reason: detail,
        bestEffort: true,
      );
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
        current,
        detail: detail,
        failureReason: failureReason,
        failureDetail: failureDetail,
      ),
    );
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
      outputRoute: VoiceCallOutputRoute.systemDefault,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      clearError: true,
      clearOutputRouteWarning: true,
      audioLevel: const VoiceAudioLevel.unavailable(),
    );
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
    final effectiveFailureReason =
        failureReason ?? _voiceCallFailureReasonForError(error);
    final effectiveDetail =
        detail ??
        _voiceCallFailureDetailForError(error) ??
        _voiceCallErrorMessage(error);
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
        outputRoute: VoiceCallOutputRoute.systemDefault,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        clearOutputRouteWarning: true,
        audioLevel: const VoiceAudioLevel.unavailable(),
      ),
    );
  }

  void _assertVoiceCallCanStart() {
    if (brain == null) {
      throw StateError('Peer connection is unavailable right now.');
    }
    _requireVoiceSignalingAdapter();
    if (_voiceCallState.hasCall &&
        _voiceCallState.phase != VoiceCallPhase.failed) {
      throw StateError('Finish the active call before starting another.');
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

  bool _isCurrentVoiceCall(String peerId, String callId, {int? sessionEpoch}) {
    return _voiceCallState.peerId == _normalizedUsername(peerId) &&
        _voiceCallState.callId == callId &&
        (sessionEpoch == null || _voiceCallState.sessionEpoch == sessionEpoch);
  }

  void _recordLateVoiceFrame(VoiceCallSession session, String message) {
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
    if (_isVoiceCallSignalingError(error, normalized)) {
      return VoiceCallFailureReason.signalingFailed;
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
      return 'Peer is busy.';
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
    if (_isVoiceCallSignalingError(error, normalized)) {
      return _voiceCallSignalingFailed;
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
        normalized.contains('active voice pair');
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

  VoiceCallFailureReason? _localAudioFailureReason(Object error) {
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
      _ => null,
    };
  }
}

final class _VideoVoiceMediaConnection implements VoiceMediaConnection {
  _VideoVoiceMediaConnection({
    required CallMediaConnection media,
    required VideoCallRenderers renderers,
    required CallMediaKind kind,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) : _media = media,
       _renderers = renderers,
       _kind = kind,
       _onError = onError {
    _remoteTrackSubscription = _media.onRemoteTrack.listen(
      _handleRemoteTrack,
      onError: (Object error, StackTrace stackTrace) {
        _onError(error, stackTrace);
      },
    );
  }

  final CallMediaConnection _media;
  final VideoCallRenderers _renderers;
  final CallMediaKind _kind;
  final void Function(Object error, StackTrace stackTrace) _onError;
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
    await _renderers.attachLocalStream(_media.localStream);
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
        _onError(error, stackTrace);
      }),
    );
  }
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
    remoteAudioTrackCount: diagnostics.remoteAudioTrackCount,
    remoteStreamCount: diagnostics.remoteStreamCount,
    hasLocalAudio: diagnostics.hasLocalAudio,
    peerConnectionClosed: diagnostics.peerConnectionClosed,
    disposed: diagnostics.disposed,
    lastDetail: diagnostics.lastDetail,
    lastError: diagnostics.lastError,
  );
}
