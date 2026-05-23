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
  static const String _voiceCallMicrophonePermissionRequired =
      'Microphone permission required.';
  static const String _voiceCallRemoteMicrophonePermissionRequired =
      'Peer microphone permission required.';
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
  static bool get _legacyControlChannelVoiceSignalingFrozen => true;
  static const Duration _voiceCallExpiry = Duration(minutes: 2);
  static const int _voiceCallTerminalSeq = 1 << 30;

  Future<void> startVoiceCall(String username) async {
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
        isOutgoing: true,
        updatedAt: sessionEpoch,
        detail: 'Checking microphone permission.',
      ),
    );

    try {
      final session = await _createVoiceCallSession(
        peerId: peerId,
        callId: callId,
        sessionEpoch: sessionEpoch,
        isOutgoing: true,
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
    _requireVoiceSignalingAdapter();

    await _disposeCurrentVoiceCallSession();
    final media = await manager.createVoiceMediaConnection(peerId);
    final session = VoiceCallSession(
      localPeerId: selfIdentity.username,
      remotePeerId: peerId,
      callId: callId,
      sessionEpoch: sessionEpoch,
      media: media,
      sendFrame: (VoiceCallFrame frame) => _sendVoiceFrameObject(peerId, frame),
      isOfferOwner: isOutgoing,
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
              if (room == null || _voiceCallSession != session) {
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
    if (_voiceCallSession != session || room.callId != session.callId) {
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
        if (room.endedBy == localUsername) {
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

  Future<void> _handleFirebaseVoiceEnvelope({
    required VoiceCallSession session,
    required String peerId,
    required VoiceSignalingEnvelope envelope,
    required String purpose,
  }) async {
    if (_voiceCallSession != session) {
      return;
    }
    try {
      final frame = await _decryptVoiceFrame(
        callId: session.callId,
        envelope: envelope,
        purpose: purpose,
      );
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
        await voiceAdapter.setMuted(
          callId: frame.callId,
          username: localUsername,
          muted: frame.muted ?? false,
          updatedAt: now,
        );
        break;
    }
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
          status: VoiceCallSignalingStatus.ended,
          reason: detail,
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
        status: VoiceCallSignalingStatus.ended,
        reason: detail,
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
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      clearError: true,
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
    await _disposeCurrentVoiceCallSession();
    final effectiveFailureReason =
        failureReason ?? _voiceCallFailureReasonForError(error);
    _setVoiceCallState(
      current.copyWith(
        phase: VoiceCallPhase.failed,
        detail:
            detail ??
            _voiceCallFailureDetailForError(error) ??
            _voiceCallErrorMessage(error),
        error: error,
        failureReason: effectiveFailureReason,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
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
