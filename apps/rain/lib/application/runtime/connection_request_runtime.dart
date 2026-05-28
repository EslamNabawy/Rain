part of 'rain_runtime_controller.dart';

extension ConnectionRequestRuntime on RainRuntimeController {
  Future<void> _startConnectionRequestRuntime() async {
    final requestAdapter = connectionRequestAdapter;
    if (requestAdapter == null) {
      _setConnectionRequestState(
        const ConnectionRequestState.idle().copyWith(updatedAt: DateTime.now()),
      );
      return;
    }
    await _stopConnectionRequestRuntime();
    _setConnectionRequestState(
      _connectionRequestState.copyWith(
        available: true,
        updatedAt: DateTime.now(),
      ),
    );
    await _refreshConnectionRequestQuota();

    final username = _normalizedUsername(selfIdentity.username);
    _connectionRequestSubscriptions.add(
      requestAdapter
          .watchIncomingConnectionRequests(username)
          .listen(
            (List<ConnectionRequestPayload> requests) async {
              await _handleIncomingConnectionRequests(requests);
            },
            onError: (Object error, StackTrace stackTrace) {
              _recordConnectionRequestAdapterError(error, stackTrace);
            },
          ),
    );
    _connectionRequestSubscriptions.add(
      requestAdapter
          .watchOutgoingConnectionRequests(username)
          .listen(
            (List<ConnectionRequestPayload> requests) async {
              await _handleOutgoingConnectionRequests(requests);
            },
            onError: (Object error, StackTrace stackTrace) {
              _recordConnectionRequestAdapterError(error, stackTrace);
            },
          ),
    );
  }

  Future<void> _stopConnectionRequestRuntime() async {
    for (final subscription in _connectionRequestSubscriptions) {
      await subscription.cancel();
    }
    _connectionRequestSubscriptions.clear();
    await _dismissAllConnectionRequestNotifications();
  }

  Stream<ConnectionRequestState> watchConnectionRequestState() async* {
    yield _connectionRequestState;
    yield* _connectionRequestStateController.stream;
  }

  Future<ConnectionRequestDecision> sendConnectionRequest(
    String username,
  ) async {
    final peerId = _normalizedUsername(username);
    final adapter = connectionRequestAdapter;
    if (adapter == null) {
      return _emitDeniedConnectionRequest(
        reasonCode: ConnectionRequestReasonCode.backendUnavailable,
        peerId: peerId,
      );
    }

    var friend = await _localMutations.run(
      () => friendStore.loadFriend(peerId),
    );
    try {
      final backendIdentity = await this.adapter.fetchIdentity(peerId);
      if (backendIdentity != null) {
        await _localMutations.run(
          () => friendStore.updatePresence(peerId, backendIdentity.online),
        );
        friend = await _localMutations.run(
          () => friendStore.loadFriend(peerId),
        );
      }
    } catch (_) {
      // Local presence is still a useful guard when backend preflight fails.
    }
    final activeTransfer = await _activeConnectionRequestBlockingTransfer();
    final guardDecision = RuntimeInteractionGuard.canSendConnectionRequest(
      peerId: peerId,
      friend: friend,
      manualDisconnectedPeers: _manualDisconnectedPeers,
      voiceCallState: _voiceCallState,
      activeTransfer: activeTransfer,
    );
    if (!guardDecision.allowed) {
      return _emitDeniedConnectionRequest(
        reasonCode: _connectionRequestReasonForRuntimeDecision(guardDecision),
        peerId: peerId,
        userMessage: guardDecision.userMessage,
        blockingPeerId: guardDecision.blockingPeerId,
        diagnostics: <String, Object?>{
          'runtimeReasonCode': guardDecision.reasonCode.name,
          'callId': guardDecision.callId,
          'transferId': guardDecision.transferId,
        },
      );
    }

    final decision = await adapter.createConnectionRequest(peerId);
    await _applyConnectionRequestDecision(decision);
    return decision;
  }

  Future<ConnectionRequestDecision> acceptConnectionRequest(
    String requestId,
  ) async {
    final adapter = connectionRequestAdapter;
    if (adapter == null) {
      return _emitDeniedConnectionRequest(
        reasonCode: ConnectionRequestReasonCode.backendUnavailable,
        peerId: '',
        requestId: requestId,
      );
    }
    final request = _connectionRequestState.incomingById(requestId);
    final peerId = request?.from ?? '';
    if (peerId.isEmpty) {
      return _emitDeniedConnectionRequest(
        reasonCode: ConnectionRequestReasonCode.staleRequest,
        peerId: '',
        requestId: requestId,
      );
    }
    final activeTransfer = await _activeConnectionRequestBlockingTransfer();
    final guardDecision = RuntimeInteractionGuard.canAcceptConnectionRequest(
      peerId: peerId,
      voiceCallState: _voiceCallState,
      activeTransfer: activeTransfer,
    );
    if (!guardDecision.allowed) {
      return _emitDeniedConnectionRequest(
        reasonCode: _connectionRequestReasonForRuntimeDecision(guardDecision),
        peerId: peerId,
        requestId: requestId,
        userMessage: guardDecision.userMessage,
        blockingPeerId: guardDecision.blockingPeerId,
        diagnostics: <String, Object?>{
          'runtimeReasonCode': guardDecision.reasonCode.name,
          'callId': guardDecision.callId,
          'transferId': guardDecision.transferId,
        },
      );
    }

    final decision = await adapter.acceptConnectionRequest(requestId);
    await _applyConnectionRequestDecision(decision);
    await _dismissConnectionRequestNotification(requestId);
    if (decision.allowed) {
      await connectPeer(peerId, interactive: true, bypassRetryBackoff: true);
    }
    return decision;
  }

  Future<ConnectionRequestDecision> cancelConnectionRequest(
    String requestId,
  ) async {
    final adapter = connectionRequestAdapter;
    if (adapter == null) {
      return _emitDeniedConnectionRequest(
        reasonCode: ConnectionRequestReasonCode.backendUnavailable,
        peerId: '',
        requestId: requestId,
      );
    }
    final decision = await adapter.cancelConnectionRequest(requestId);
    await _applyConnectionRequestDecision(decision);
    await _dismissConnectionRequestNotification(requestId);
    return decision;
  }

  Future<ConnectionRequestDecision> rejectConnectionRequest(
    String requestId,
  ) async {
    final adapter = connectionRequestAdapter;
    if (adapter == null) {
      return _emitDeniedConnectionRequest(
        reasonCode: ConnectionRequestReasonCode.backendUnavailable,
        peerId: '',
        requestId: requestId,
      );
    }
    final decision = await adapter.rejectConnectionRequest(requestId);
    await _applyConnectionRequestDecision(decision);
    await _dismissConnectionRequestNotification(requestId);
    return decision;
  }

  Future<ConnectionRequestDecision> markConnectionRequestSeen(
    String requestId,
  ) async {
    final adapter = connectionRequestAdapter;
    if (adapter == null) {
      return _emitDeniedConnectionRequest(
        reasonCode: ConnectionRequestReasonCode.backendUnavailable,
        peerId: '',
        requestId: requestId,
      );
    }
    final decision = await adapter.markConnectionRequestSeen(requestId);
    await _applyConnectionRequestDecision(decision);
    await _dismissConnectionRequestNotification(requestId);
    return decision;
  }

  Future<ConnectionRequestDecision> muteConnectionRequestsFromPeer(
    String username,
  ) async {
    final peerId = _normalizedUsername(username);
    final adapter = connectionRequestAdapter;
    if (adapter == null) {
      return _emitDeniedConnectionRequest(
        reasonCode: ConnectionRequestReasonCode.backendUnavailable,
        peerId: peerId,
      );
    }
    final decision = await adapter.muteConnectionRequestsFromPeer(peerId);
    await _applyConnectionRequestDecision(decision);
    await _dismissConnectionRequestNotificationsFromPeer(peerId);
    return decision;
  }

  Future<ConnectionRequestDecision> unmuteConnectionRequestsFromPeer(
    String username,
  ) async {
    final peerId = _normalizedUsername(username);
    final adapter = connectionRequestAdapter;
    if (adapter == null) {
      return _emitDeniedConnectionRequest(
        reasonCode: ConnectionRequestReasonCode.backendUnavailable,
        peerId: peerId,
      );
    }
    final decision = await adapter.unmuteConnectionRequestsFromPeer(peerId);
    await _applyConnectionRequestDecision(decision);
    return decision;
  }

  Future<void> _handleIncomingConnectionRequests(
    List<ConnectionRequestPayload> requests,
  ) async {
    final filtered = await _filterConnectionRequests(
      requests,
      direction: ConnectionRequestDirection.inbound,
    );
    final surfaces = _connectionRequestSurfaces(
      filtered,
      direction: ConnectionRequestDirection.inbound,
    );
    _setConnectionRequestState(
      _connectionRequestState.copyWith(
        available: connectionRequestAdapter != null,
        incomingRequests: filtered,
        incomingSurfaces: surfaces,
        updatedAt: DateTime.now(),
      ),
    );
    unawaited(_syncConnectionRequestNotifications(surfaces));
  }

  Future<void> _handleOutgoingConnectionRequests(
    List<ConnectionRequestPayload> requests,
  ) async {
    final filtered = await _filterConnectionRequests(
      requests,
      direction: ConnectionRequestDirection.outbound,
    );
    _setConnectionRequestState(
      _connectionRequestState.copyWith(
        available: connectionRequestAdapter != null,
        outgoingRequests: filtered,
        outgoingSurfaces: _connectionRequestSurfaces(
          filtered,
          direction: ConnectionRequestDirection.outbound,
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _reconcileConnectionRequestsWithRelationships() async {
    if (connectionRequestAdapter == null) {
      return;
    }
    final incoming = await _filterConnectionRequests(
      _connectionRequestState.incomingRequests,
      direction: ConnectionRequestDirection.inbound,
    );
    final outgoing = await _filterConnectionRequests(
      _connectionRequestState.outgoingRequests,
      direction: ConnectionRequestDirection.outbound,
    );
    _setConnectionRequestState(
      _connectionRequestState.copyWith(
        incomingRequests: incoming,
        outgoingRequests: outgoing,
        incomingSurfaces: _connectionRequestSurfaces(
          incoming,
          direction: ConnectionRequestDirection.inbound,
        ),
        outgoingSurfaces: _connectionRequestSurfaces(
          outgoing,
          direction: ConnectionRequestDirection.outbound,
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<List<ConnectionRequestPayload>> _filterConnectionRequests(
    List<ConnectionRequestPayload> requests, {
    required ConnectionRequestDirection direction,
  }) async {
    if (requests.isEmpty) {
      return const <ConnectionRequestPayload>[];
    }
    final acceptedFriends = await _localMutations.run(friendStore.loadFriends);
    final accepted = <String>{
      for (final friend in acceptedFriends)
        if (friend.state == FriendState.friend) friend.username,
    };
    return List<ConnectionRequestPayload>.unmodifiable(
      requests.where((ConnectionRequestPayload request) {
        final peerId = direction == ConnectionRequestDirection.inbound
            ? request.from
            : request.to;
        return accepted.contains(peerId);
      }),
    );
  }

  List<ConnectionRequestSurfaceModel> _connectionRequestSurfaces(
    List<ConnectionRequestPayload> requests, {
    required ConnectionRequestDirection direction,
    ConnectionRequestQuotaSnapshot? quotaOverride,
  }) {
    final feedback = _connectionRequestState.lastUserMessage;
    final quota = quotaOverride ?? _connectionRequestState.quota;
    return List<ConnectionRequestSurfaceModel>.unmodifiable(
      requests.map((ConnectionRequestPayload request) {
        final requestFeedback =
            feedback != null && feedback.requestId == request.requestId
            ? ConnectionRequestFeedbackModel(
                reasonCode:
                    feedback.reasonCode ??
                    ConnectionRequestReasonCode.backendRejected,
                message: feedback.message,
              )
            : null;
        return buildConnectionRequestSurfaceModel(
          payload: request,
          direction: direction,
          quota: quota,
          feedback: requestFeedback,
        );
      }),
    );
  }

  Future<void> _refreshConnectionRequestQuota() async {
    final adapter = connectionRequestAdapter;
    if (adapter == null) {
      return;
    }
    try {
      final quota = await adapter.fetchConnectionRequestQuota();
      _setConnectionRequestState(
        _connectionRequestState.copyWith(
          available: true,
          quota: quota,
          incomingSurfaces: _connectionRequestSurfaces(
            _connectionRequestState.incomingRequests,
            direction: ConnectionRequestDirection.inbound,
            quotaOverride: quota,
          ),
          outgoingSurfaces: _connectionRequestSurfaces(
            _connectionRequestState.outgoingRequests,
            direction: ConnectionRequestDirection.outbound,
            quotaOverride: quota,
          ),
          updatedAt: DateTime.now(),
        ),
      );
    } on Object catch (error, stackTrace) {
      _recordConnectionRequestAdapterError(error, stackTrace);
    }
  }

  Future<ConnectionRequestDecision> _applyConnectionRequestDecision(
    ConnectionRequestDecision decision,
  ) async {
    if (decision.quota != null) {
      _setConnectionRequestState(
        _connectionRequestState.copyWith(quota: decision.quota),
      );
    } else {
      await _refreshConnectionRequestQuota();
    }
    _emitConnectionRequestMessage(decision);
    return decision;
  }

  ConnectionRequestDecision _emitDeniedConnectionRequest({
    required ConnectionRequestReasonCode reasonCode,
    required String peerId,
    String? requestId,
    String? userMessage,
    String? blockingPeerId,
    Map<String, Object?> diagnostics = const <String, Object?>{},
  }) {
    final decision = deniedConnectionRequestDecision(
      reasonCode: reasonCode,
      peerId: peerId,
      requestId: requestId,
      userMessage: userMessage,
      blockingPeerId: blockingPeerId,
      diagnostics: diagnostics,
    );
    _emitConnectionRequestMessage(decision);
    return decision;
  }

  void _emitConnectionRequestMessage(ConnectionRequestDecision decision) {
    if (decision.userMessage.trim().isEmpty) {
      return;
    }
    final message = ConnectionRequestUserMessage(
      message: decision.userMessage,
      createdAt: DateTime.now(),
      reasonCode: decision.reasonCode,
      requestId: decision.requestId,
      peerId: decision.peerId ?? decision.blockingPeerId,
    );
    _setConnectionRequestState(
      _connectionRequestState.copyWith(
        lastUserMessage: message,
        incomingSurfaces: _connectionRequestSurfaces(
          _connectionRequestState.incomingRequests,
          direction: ConnectionRequestDirection.inbound,
        ),
        outgoingSurfaces: _connectionRequestSurfaces(
          _connectionRequestState.outgoingRequests,
          direction: ConnectionRequestDirection.outbound,
        ),
        updatedAt: message.createdAt,
      ),
    );
    _recordRuntimeEvent(
      category: 'connection_request',
      name: decision.allowed
          ? 'connection_request_decision_allowed'
          : 'connection_request_decision_denied',
      severity: decision.allowed ? 'info' : 'warning',
      message: decision.userMessage,
      context: <String, Object?>{
        'requestId': decision.requestId,
        'peerId': decision.peerId,
        'blockingPeerId': decision.blockingPeerId,
        'reasonCode': decision.reasonCode?.name,
        'status': decision.status?.name,
        ...decision.diagnostics,
      },
    );
  }

  Future<FileTransferRecord?> _activeConnectionRequestBlockingTransfer() async {
    final activeTransfers = await fileTransferStore.loadActiveTransfers();
    for (final transfer in activeTransfers) {
      if (transfer.isActive) {
        return transfer;
      }
    }
    return null;
  }

  void _setConnectionRequestState(ConnectionRequestState next) {
    _connectionRequestState = next;
    if (!_connectionRequestStateController.isClosed) {
      _connectionRequestStateController.add(next);
    }
  }

  Future<void> _syncConnectionRequestNotifications(
    List<ConnectionRequestSurfaceModel> surfaces,
  ) async {
    final notificationService = connectionRequestNotificationService;
    if (notificationService == null) {
      return;
    }
    final currentRequestIds = <String>{
      for (final surface in surfaces)
        if (!surface.status.isTerminal) surface.requestId,
    };
    for (final activeId in _activeConnectionRequestNotificationIds.toList()) {
      if (!currentRequestIds.contains(activeId)) {
        await _dismissConnectionRequestNotification(activeId);
      }
    }
    for (final surface in surfaces) {
      if (surface.status.isTerminal) {
        await _dismissConnectionRequestNotification(surface.requestId);
        continue;
      }
      final result = await notificationService.showConnectionRequest(surface);
      if (result.kind == RainNotificationResultKind.shown) {
        _activeConnectionRequestNotificationIds.add(surface.requestId);
      }
      _handleConnectionRequestNotificationResult(result);
    }
  }

  Future<void> _dismissConnectionRequestNotification(String requestId) async {
    final notificationService = connectionRequestNotificationService;
    if (notificationService == null) {
      return;
    }
    try {
      await notificationService.dismissConnectionRequest(requestId);
      _activeConnectionRequestNotificationIds.remove(requestId);
    } catch (error, stackTrace) {
      _recordConnectionRequestNotificationError(error, stackTrace);
    }
  }

  Future<void> _dismissConnectionRequestNotificationsFromPeer(
    String peerId,
  ) async {
    final notificationService = connectionRequestNotificationService;
    if (notificationService == null) {
      return;
    }
    try {
      await notificationService.dismissConnectionRequestsFromPeer(peerId);
      final currentIds = <String>{
        for (final request in _connectionRequestState.incomingRequests)
          if (request.from == peerId) request.requestId,
      };
      _activeConnectionRequestNotificationIds.removeAll(currentIds);
    } catch (error, stackTrace) {
      _recordConnectionRequestNotificationError(error, stackTrace);
    }
  }

  Future<void> _dismissAllConnectionRequestNotifications() async {
    for (final requestId in _activeConnectionRequestNotificationIds.toList()) {
      await _dismissConnectionRequestNotification(requestId);
    }
    _activeConnectionRequestNotificationIds.clear();
  }

  void _handleConnectionRequestNotificationResult(
    RainNotificationResult result,
  ) {
    _recordRuntimeEvent(
      category: 'connection_request',
      name: 'connection_request_notification_${result.kind.name}',
      severity: result.needsInAppFallback ? 'warning' : 'info',
      message: result.message,
      context: <String, Object?>{
        'requestId': result.requestId,
        'peerId': result.peerId,
      },
    );
    if (!result.needsInAppFallback) {
      return;
    }
    final key = '${result.requestId}:${result.kind.name}';
    if (!_connectionRequestNotificationFallbackKeys.add(key)) {
      return;
    }
    final decision = deniedConnectionRequestDecision(
      reasonCode: result.kind == RainNotificationResultKind.permissionDenied
          ? ConnectionRequestReasonCode.permissionDenied
          : ConnectionRequestReasonCode.notificationUnavailable,
      peerId: result.peerId ?? '',
      requestId: result.requestId,
      userMessage: result.message,
    );
    _emitConnectionRequestMessage(decision);
  }

  void _recordConnectionRequestNotificationError(
    Object error,
    StackTrace stackTrace,
  ) {
    errorRecorder?.call(
      error,
      stackTrace,
      source: 'connection-request-notifications',
      fatal: false,
    );
    _recordRuntimeEvent(
      category: 'connection_request',
      name: 'connection_request_notification_error',
      severity: 'warning',
      message: error.toString(),
    );
  }

  void _recordConnectionRequestAdapterError(
    Object error,
    StackTrace stackTrace,
  ) {
    errorRecorder?.call(
      error,
      stackTrace,
      source: 'connection-request-runtime',
      fatal: false,
    );
    _recordRuntimeEvent(
      category: 'connection_request',
      name: 'connection_request_runtime_error',
      severity: 'warning',
      message: error.toString(),
    );
  }

  ConnectionRequestReasonCode _connectionRequestReasonForRuntimeDecision(
    RuntimeInteractionDecision decision,
  ) {
    return switch (decision.reasonCode) {
      RuntimeInteractionReasonCode.none =>
        ConnectionRequestReasonCode.backendRejected,
      RuntimeInteractionReasonCode.manualDisconnectActive =>
        ConnectionRequestReasonCode.manualDisconnectActive,
      RuntimeInteractionReasonCode.peerConnectionUnavailable =>
        ConnectionRequestReasonCode.backendUnavailable,
      RuntimeInteractionReasonCode.notAcceptedFriend =>
        ConnectionRequestReasonCode.notAcceptedFriend,
      RuntimeInteractionReasonCode.activeCall =>
        ConnectionRequestReasonCode.activeCall,
      RuntimeInteractionReasonCode.noIncomingCall =>
        ConnectionRequestReasonCode.staleRequest,
      RuntimeInteractionReasonCode.activeFileTransfer =>
        ConnectionRequestReasonCode.activeTransfer,
      RuntimeInteractionReasonCode.peerBusy =>
        ConnectionRequestReasonCode.activeCall,
      RuntimeInteractionReasonCode.peerOffline =>
        ConnectionRequestReasonCode.peerOffline,
      RuntimeInteractionReasonCode.presenceUnknown =>
        ConnectionRequestReasonCode.presenceUnknown,
      RuntimeInteractionReasonCode.staleCallCleanup =>
        ConnectionRequestReasonCode.staleRequest,
      RuntimeInteractionReasonCode.callCleanupInProgress =>
        ConnectionRequestReasonCode.backendRejected,
    };
  }
}
