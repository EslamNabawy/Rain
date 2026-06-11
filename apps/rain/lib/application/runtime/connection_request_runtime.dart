/// # connection_request_runtime.dart
///
/// [ConnectionRequestRuntime] extension on [RainRuntimeController] manages the
/// inbound/outbound connection-request stream lifecycle: watches Firebase for
/// new requests, enforces burst limits and cooldowns, updates
/// [ConnectionRequestState], and triggers notifications.
///
/// **Key types:** (extension methods on RainRuntimeController)
///
/// **Part of:** connection_request_runtime.dart (extension)
///
/// **Depends on:** protocol_brain, rain_core, notifications

import 'dart:async';

import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/infrastructure/notifications/rain_notification_service.dart';
import 'connection_request_messages.dart';
import 'connection_request_state.dart';
import 'rain_runtime_controller.dart';
import 'runtime_interaction_guard.dart';

const int _connectionRequestBurstLimit = 3;
const Duration _connectionRequestBurstWindow = Duration(seconds: 60);
const Duration _connectionRequestBurstCooldown = Duration(seconds: 15);

extension ConnectionRequestRuntime on RainRuntimeController {
  Future<void> startConnectionRequestRuntime() async {
    final requestAdapter = connectionRequestAdapter;
    if (requestAdapter == null) {
      _setConnectionRequestState(
        const ConnectionRequestState.idle().copyWith(updatedAt: DateTime.now()),
      );
      return;
    }
    await stopConnectionRequestRuntime();
    _setConnectionRequestState(
      connectionRequestState.copyWith(
        available: true,
        updatedAt: DateTime.now(),
      ),
    );
    await _refreshConnectionRequestQuota();

    final username = normalizeUsername(selfIdentity.username);
    connectionRequestSubscriptions.add(
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
    connectionRequestSubscriptions.add(
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

  Future<void> stopConnectionRequestRuntime() async {
    for (final subscription in connectionRequestSubscriptions) {
      await subscription.cancel();
    }
    connectionRequestSubscriptions.clear();
    await _dismissAllConnectionRequestNotifications();
  }

  Stream<ConnectionRequestState> watchConnectionRequestState() async* {
    yield connectionRequestState;
    yield* connectionRequestStateController.stream;
  }

  Future<ConnectionRequestDecision> sendConnectionRequest(
    String username, {
    required bool confirmedOfflineNotification,
  }) async {
    final peerId = normalizeUsername(username);
    final adapter = connectionRequestAdapter;
    if (adapter == null) {
      return _emitDeniedConnectionRequest(
        reasonCode: ConnectionRequestReasonCode.backendUnavailable,
        peerId: peerId,
      );
    }

    if (!confirmedOfflineNotification) {
      recordRuntimeEvent(
        category: 'connection_request',
        name: 'connection_request_confirmation_missing',
        severity: 'warning',
        message: 'Confirm before sending a request notification.',
        context: <String, Object?>{'peerId': peerId},
      );
      return _emitDeniedConnectionRequest(
        reasonCode: ConnectionRequestReasonCode.confirmationRequired,
        peerId: peerId,
        diagnostics: <String, Object?>{
          'confirmationRequired': true,
          'serverAuthority': 'localRuntime',
        },
      );
    }

    var friend = await localMutations.run(() => friendStore.loadFriend(peerId));
    bool? backendPeerOnline;
    try {
      final presence = await fetchPeerPresenceSnapshot(
        peerId,
        action: 'connectionRequest',
      );
      backendPeerOnline = presence?.online;
      if (presence != null) {
        friend = await localMutations.run(() => friendStore.loadFriend(peerId));
      }
    } catch (error, stackTrace) {
      recordRuntimeEvent(
        category: 'connection_request',
        name: 'connection_request_presence_preflight_failed',
        severity: 'warning',
        message:
            RuntimeInteractionGuard.connectionRequestPresenceUnknownMessage(
              peerId,
            ),
        context: <String, Object?>{'peerId': peerId, 'error': error.toString()},
      );
      _recordConnectionRequestAdapterError(error, stackTrace);
    }
    if (backendPeerOnline == false) {
      recordRuntimeEvent(
        category: 'connection_request',
        name: 'connection_request_presence_stale_allowed',
        message:
            'Peer presence is offline or stale; offline request flow is allowed.',
        context: <String, Object?>{'peerId': peerId},
      );
    }
    final activeTransfer = await _activeConnectionRequestBlockingTransfer();
    final guardDecision = RuntimeInteractionGuard.canSendConnectionRequest(
      peerId: peerId,
      friend: friend,
      peerOnline: backendPeerOnline,
      manualDisconnectedPeers: mutableManualDisconnectedPeers,
      voiceCallState: voiceCallState,
      activeTransfer: activeTransfer,
    );
    if (!guardDecision.allowed) {
      if (guardDecision.reasonCode ==
          RuntimeInteractionReasonCode.peerAlreadyOnline) {
        recordRuntimeEvent(
          category: 'connection_request',
          name: 'connection_request_blocked_online_rules',
          severity: 'warning',
          message: guardDecision.userMessage,
          context: <String, Object?>{'peerId': peerId},
        );
      }
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

    final cooldownDecision = _connectionRequestLocalCooldownDecision(peerId);
    if (cooldownDecision != null) {
      return cooldownDecision;
    }

    final decision = await adapter.createConnectionRequest(peerId);
    if (decision.allowed) {
      _recordConnectionRequestLocalSend(peerId);
    }
    await _applyConnectionRequestDecision(decision);
    return decision;
  }

  Future<void> cleanupConnectionRequestsForPeer(String username) async {
    final peerId = normalizeUsername(username);
    await _runConnectionRequestCleanup(peerId: peerId);
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
    final request = connectionRequestState.incomingById(requestId);
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
      voiceCallState: voiceCallState,
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
    final peerId = normalizeUsername(username);
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
    final peerId = normalizeUsername(username);
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
      connectionRequestState.copyWith(
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
      connectionRequestState.copyWith(
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

  Future<void> reconcileConnectionRequestsWithRelationships() async {
    if (connectionRequestAdapter == null) {
      return;
    }
    final incoming = await _filterConnectionRequests(
      connectionRequestState.incomingRequests,
      direction: ConnectionRequestDirection.inbound,
    );
    final outgoing = await _filterConnectionRequests(
      connectionRequestState.outgoingRequests,
      direction: ConnectionRequestDirection.outbound,
    );
    _setConnectionRequestState(
      connectionRequestState.copyWith(
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
    final acceptedFriends = await localMutations.run(friendStore.loadFriends);
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
    final feedback = connectionRequestState.lastUserMessage;
    final quota = quotaOverride ?? connectionRequestState.quota;
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
        connectionRequestState.copyWith(
          available: true,
          quota: quota,
          incomingSurfaces: _connectionRequestSurfaces(
            connectionRequestState.incomingRequests,
            direction: ConnectionRequestDirection.inbound,
            quotaOverride: quota,
          ),
          outgoingSurfaces: _connectionRequestSurfaces(
            connectionRequestState.outgoingRequests,
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
        connectionRequestState.copyWith(quota: decision.quota),
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
    int? retryAfterMs,
    Map<String, Object?> diagnostics = const <String, Object?>{},
  }) {
    final decision = deniedConnectionRequestDecision(
      reasonCode: reasonCode,
      peerId: peerId,
      requestId: requestId,
      userMessage: userMessage,
      blockingPeerId: blockingPeerId,
      retryAfterMs: retryAfterMs,
      diagnostics: diagnostics,
    );
    _emitConnectionRequestMessage(decision);
    return decision;
  }

  ConnectionRequestDecision? _connectionRequestLocalCooldownDecision(
    String peerId,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cooldownUntil = connectionRequestCooldownUntilByPeer[peerId];
    if (cooldownUntil != null && cooldownUntil > now) {
      return _emitDeniedConnectionRequest(
        reasonCode: ConnectionRequestReasonCode.bestEffortLimit,
        peerId: peerId,
        retryAfterMs: cooldownUntil - now,
        diagnostics: <String, Object?>{
          'localBurstCooldown': true,
          'burstLimit': _connectionRequestBurstLimit,
          'burstWindowMs': _connectionRequestBurstWindow.inMilliseconds,
          'cooldownUntil': cooldownUntil,
          'serverAuthority': 'bestEffort',
          'securityLevel': 'localRuntime',
        },
      );
    }

    final windowStart = now - _connectionRequestBurstWindow.inMilliseconds;
    final history = connectionRequestSendHistoryByPeer.putIfAbsent(
      peerId,
      () => <int>[],
    )..removeWhere((int sentAt) => sentAt < windowStart);
    if (history.length < _connectionRequestBurstLimit) {
      return null;
    }

    final nextCooldownUntil =
        now + _connectionRequestBurstCooldown.inMilliseconds;
    connectionRequestCooldownUntilByPeer[peerId] = nextCooldownUntil;
    return _emitDeniedConnectionRequest(
      reasonCode: ConnectionRequestReasonCode.bestEffortLimit,
      peerId: peerId,
      retryAfterMs: _connectionRequestBurstCooldown.inMilliseconds,
      diagnostics: <String, Object?>{
        'localBurstDenied': true,
        'burstLimit': _connectionRequestBurstLimit,
        'burstWindowMs': _connectionRequestBurstWindow.inMilliseconds,
        'cooldownUntil': nextCooldownUntil,
        'serverAuthority': 'bestEffort',
        'securityLevel': 'localRuntime',
      },
    );
  }

  void _recordConnectionRequestLocalSend(String peerId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowStart = now - _connectionRequestBurstWindow.inMilliseconds;
    final history = connectionRequestSendHistoryByPeer.putIfAbsent(
      peerId,
      () => <int>[],
    )..removeWhere((int sentAt) => sentAt < windowStart);
    history.add(now);
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
      connectionRequestState.copyWith(
        lastUserMessage: message,
        incomingSurfaces: _connectionRequestSurfaces(
          connectionRequestState.incomingRequests,
          direction: ConnectionRequestDirection.inbound,
        ),
        outgoingSurfaces: _connectionRequestSurfaces(
          connectionRequestState.outgoingRequests,
          direction: ConnectionRequestDirection.outbound,
        ),
        updatedAt: message.createdAt,
      ),
    );
    recordRuntimeEvent(
      category: 'connection_request',
      name: decision.allowed
          ? 'connection_request_decision_allowed'
          : 'connection_request_decision_denied',
      severity: decision.allowed ? 'info' : 'warning',
      message: decision.userMessage,
      context: _connectionRequestDiagnosticContext(decision),
    );
  }

  Map<String, Object?> _connectionRequestDiagnosticContext(
    ConnectionRequestDecision decision, {
    String? notificationFallbackState,
  }) {
    final quota = decision.quota ?? connectionRequestState.quota;
    return <String, Object?>{
      'requestId': decision.requestId,
      'peerId': decision.peerId,
      'blockingPeerId': decision.blockingPeerId,
      'direction': _connectionRequestDirectionFor(decision)?.name,
      'status': decision.status?.name,
      'reasonCode': decision.reasonCode?.name,
      'userMessageKey': _connectionRequestUserMessageKey(decision),
      'renderedMessage': decision.userMessage,
      'quotaSummary': quota?.toJson(),
      'retryAfterMs': decision.retryAfterMs ?? quota?.retryAfterMs,
      'notificationFallbackState':
          notificationFallbackState ??
          _connectionRequestNotificationFallbackState(decision.requestId),
      ...decision.diagnostics,
    };
  }

  ConnectionRequestDirection? _connectionRequestDirectionFor(
    ConnectionRequestDecision decision,
  ) {
    final requestId = decision.requestId;
    if (requestId != null) {
      if (connectionRequestState.incomingById(requestId) != null) {
        return ConnectionRequestDirection.inbound;
      }
      if (connectionRequestState.outgoingById(requestId) != null) {
        return ConnectionRequestDirection.outbound;
      }
    }
    if (decision.status == ConnectionRequestStatus.pending ||
        decision.peerId != null) {
      return ConnectionRequestDirection.outbound;
    }
    return null;
  }

  String _connectionRequestUserMessageKey(ConnectionRequestDecision decision) {
    final reasonCode = decision.reasonCode;
    if (reasonCode != null) {
      return 'connectionRequest.reason.${reasonCode.name}';
    }
    final status = decision.status;
    if (status != null) {
      return 'connectionRequest.status.${status.name}';
    }
    return decision.allowed
        ? 'connectionRequest.allowed'
        : 'connectionRequest.denied';
  }

  String _connectionRequestNotificationFallbackState(String? requestId) {
    if (requestId == null || requestId.isEmpty) {
      return 'notEvaluated';
    }
    final hasFallback = connectionRequestNotificationFallbackKeys.any(
      (String key) => key.startsWith('$requestId:'),
    );
    return hasFallback ? 'inAppFallbackShown' : 'notEvaluated';
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
    connectionRequestState = next;
    if (!connectionRequestStateController.isClosed) {
      connectionRequestStateController.add(next);
    }
  }

  Future<void> _runConnectionRequestCleanup({String? peerId}) async {
    final adapter = connectionRequestAdapter;
    if (adapter is! RtdbOnlyConnectionRequestAdapter) {
      return;
    }
    try {
      await adapter.cleanupConnectionRequests(peerId: peerId);
    } on Object catch (error, stackTrace) {
      _recordConnectionRequestAdapterError(error, stackTrace);
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
    for (final activeId in activeConnectionRequestNotificationIds.toList()) {
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
        activeConnectionRequestNotificationIds.add(surface.requestId);
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
      activeConnectionRequestNotificationIds.remove(requestId);
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
        for (final request in connectionRequestState.incomingRequests)
          if (request.from == peerId) request.requestId,
      };
      activeConnectionRequestNotificationIds.removeAll(currentIds);
    } catch (error, stackTrace) {
      _recordConnectionRequestNotificationError(error, stackTrace);
    }
  }

  Future<void> _dismissAllConnectionRequestNotifications() async {
    for (final requestId in activeConnectionRequestNotificationIds.toList()) {
      await _dismissConnectionRequestNotification(requestId);
    }
    activeConnectionRequestNotificationIds.clear();
  }

  void _handleConnectionRequestNotificationResult(
    RainNotificationResult result,
  ) {
    recordRuntimeEvent(
      category: 'connection_request',
      name: 'connection_request_notification_${result.kind.name}',
      severity: result.needsInAppFallback ? 'warning' : 'info',
      message: result.message,
      context: <String, Object?>{
        'requestId': result.requestId,
        'peerId': result.peerId,
        'notificationResult': result.kind.name,
        'notificationFallbackState': result.needsInAppFallback
            ? 'inAppFallbackRequired'
            : 'notNeeded',
        'renderedMessage': result.message,
      },
    );
    if (!result.needsInAppFallback) {
      return;
    }
    final key = '${result.requestId}:${result.kind.name}';
    if (!connectionRequestNotificationFallbackKeys.add(key)) {
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
    recordRuntimeEvent(
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
    recordRuntimeEvent(
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
      RuntimeInteractionReasonCode.peerAlreadyOnline =>
        ConnectionRequestReasonCode.peerAlreadyOnline,
      RuntimeInteractionReasonCode.presenceUnknown =>
        ConnectionRequestReasonCode.presenceUnknown,
      RuntimeInteractionReasonCode.staleCallCleanup =>
        ConnectionRequestReasonCode.staleRequest,
      RuntimeInteractionReasonCode.callCleanupInProgress =>
        ConnectionRequestReasonCode.backendRejected,
    };
  }
}
