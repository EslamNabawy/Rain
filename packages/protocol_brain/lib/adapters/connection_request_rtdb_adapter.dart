import 'dart:math';

import 'package:firebase_database/firebase_database.dart';

import '../src/connection_request_adapter.dart';
import '../src/connection_request_contract.dart';

typedef RtdbOnlyConnectionRequestValueStream =
    Stream<Object?> Function(String path);

typedef RtdbOnlyConnectionRequestValueGetter =
    Future<Object?> Function(String path);

typedef RtdbOnlyConnectionRequestUpdate =
    Future<void> Function(Map<String, Object?> updates);

typedef RtdbOnlyConnectionRequestTransactionRunner =
    Future<RtdbOnlyConnectionRequestTransactionResult> Function(
      String path,
      RtdbOnlyConnectionRequestTransactionHandler handler,
    );

typedef RtdbOnlyConnectionRequestTransactionHandler =
    RtdbOnlyConnectionRequestTransactionAction Function(Object? current);

String createConnectionRequestId({
  required String from,
  required String to,
  required int now,
  required String randomSuffix,
}) {
  final suffix = _validateRequestIdSuffix(randomSuffix);
  final pair = connectionRequestPairKey(from, to).replaceAll(':', '_');
  return validateConnectionRequestId('${now}_${pair}_$suffix');
}

final class RtdbOnlyConnectionRequestTransactionAction {
  const RtdbOnlyConnectionRequestTransactionAction._({
    required this.aborted,
    this.value,
  });

  const RtdbOnlyConnectionRequestTransactionAction.success(Object? value)
    : this._(aborted: false, value: value);

  const RtdbOnlyConnectionRequestTransactionAction.abort()
    : this._(aborted: true);

  final bool aborted;
  final Object? value;
}

final class RtdbOnlyConnectionRequestTransactionResult {
  const RtdbOnlyConnectionRequestTransactionResult({
    required this.committed,
    this.value,
  });

  final bool committed;
  final Object? value;
}

final class RtdbOnlyConnectionRequestAdapter
    implements ConnectionRequestAdapter {
  RtdbOnlyConnectionRequestAdapter({
    required DatabaseReference root,
    required Future<String> Function() currentUsername,
    required Future<bool> Function(String peerId) isAcceptedFriend,
    required Future<bool> Function(String peerId) isPeerOnline,
    ConnectionRequestAdapterDiagnosticsSink? diagnosticsSink,
    DateTime Function()? clock,
    Duration localCreateCooldown = Duration.zero,
  }) : this._(
         currentUsername: currentUsername,
         isAcceptedFriend: isAcceptedFriend,
         isPeerOnline: isPeerOnline,
         diagnosticsSink: diagnosticsSink,
         clock: clock,
         localCreateCooldown: localCreateCooldown,
         randomSuffix: _randomAlphanumericSuffix,
         watchValue: (String path) {
           return root
               .child(path)
               .onValue
               .map((DatabaseEvent event) => event.snapshot.value);
         },
         getValue: (String path) async {
           return (await root.child(path).get()).value;
         },
         updateValue: root.update,
         runTransaction: (String path, handler) async {
           final result = await root.child(path).runTransaction((
             Object? current,
           ) {
             final action = handler(current);
             if (action.aborted) {
               return Transaction.abort();
             }
             return Transaction.success(action.value);
           }, applyLocally: false);
           return RtdbOnlyConnectionRequestTransactionResult(
             committed: result.committed,
             value: result.snapshot.value,
           );
         },
       );

  RtdbOnlyConnectionRequestAdapter.forTest({
    required Future<String> Function() currentUsername,
    required Future<bool> Function(String peerId) isAcceptedFriend,
    required Future<bool> Function(String peerId) isPeerOnline,
    required RtdbOnlyConnectionRequestValueStream watchValue,
    RtdbOnlyConnectionRequestValueGetter? getValue,
    RtdbOnlyConnectionRequestUpdate? updateValue,
    RtdbOnlyConnectionRequestTransactionRunner? runTransaction,
    String Function()? randomSuffix,
    ConnectionRequestAdapterDiagnosticsSink? diagnosticsSink,
    DateTime Function()? clock,
    Duration localCreateCooldown = Duration.zero,
  }) : this._(
         currentUsername: currentUsername,
         isAcceptedFriend: isAcceptedFriend,
         isPeerOnline: isPeerOnline,
         diagnosticsSink: diagnosticsSink,
         clock: clock,
         localCreateCooldown: localCreateCooldown,
         randomSuffix: randomSuffix ?? (() => 'test0'),
         watchValue: watchValue,
         getValue: getValue ?? ((String _) async => null),
         updateValue: updateValue ?? ((Map<String, Object?> _) async {}),
         runTransaction:
             runTransaction ??
             (
               String ignoredPath,
               RtdbOnlyConnectionRequestTransactionHandler ignoredHandler,
             ) async {
               return const RtdbOnlyConnectionRequestTransactionResult(
                 committed: false,
               );
             },
       );

  RtdbOnlyConnectionRequestAdapter._({
    required Future<String> Function() currentUsername,
    required Future<bool> Function(String peerId) isAcceptedFriend,
    required Future<bool> Function(String peerId) isPeerOnline,
    required RtdbOnlyConnectionRequestValueStream watchValue,
    required RtdbOnlyConnectionRequestValueGetter getValue,
    required RtdbOnlyConnectionRequestUpdate updateValue,
    required RtdbOnlyConnectionRequestTransactionRunner runTransaction,
    required String Function() randomSuffix,
    ConnectionRequestAdapterDiagnosticsSink? diagnosticsSink,
    DateTime Function()? clock,
    required Duration localCreateCooldown,
  }) : _currentUsername = currentUsername,
       _isAcceptedFriend = isAcceptedFriend,
       _isPeerOnline = isPeerOnline,
       _watchValue = watchValue,
       _getValue = getValue,
       _updateValue = updateValue,
       _runTransaction = runTransaction,
       _randomSuffix = randomSuffix,
       _diagnosticsSink = diagnosticsSink,
       _clock = clock ?? DateTime.now,
       _localCreateCooldown = localCreateCooldown;

  static const int bestEffortDailyLimit = 20;
  static const int bestEffortPerTargetDailyLimit = 3;
  static const String bestEffortServerAuthority = 'bestEffort';
  static const String bestEffortSecurityLevel = 'sparkRules';
  static const Duration requestTtl = Duration(seconds: 45);

  final Future<String> Function() _currentUsername;
  final Future<bool> Function(String peerId) _isAcceptedFriend;
  final Future<bool> Function(String peerId) _isPeerOnline;
  final RtdbOnlyConnectionRequestValueStream _watchValue;
  final RtdbOnlyConnectionRequestValueGetter _getValue;
  final RtdbOnlyConnectionRequestUpdate _updateValue;
  final RtdbOnlyConnectionRequestTransactionRunner _runTransaction;
  final String Function() _randomSuffix;
  final ConnectionRequestAdapterDiagnosticsSink? _diagnosticsSink;
  final DateTime Function() _clock;
  final Duration _localCreateCooldown;
  int? _lastSuccessfulCreateAt;

  @override
  Future<ConnectionRequestDecision> createConnectionRequest(
    String peerId,
  ) async {
    final normalizedPeer = _normalizePeerForDecision(peerId);
    if (normalizedPeer == null) {
      return _blocked(ConnectionRequestReasonCode.invalidPeer);
    }

    late final String currentUsername;
    try {
      currentUsername = normalizeConnectionRequestUsername(
        await _currentUsername(),
      );
    } on Object catch (error) {
      return _blocked(
        ConnectionRequestReasonCode.authMissing,
        peerId: normalizedPeer,
        error: error,
      );
    }

    final now = _clock().millisecondsSinceEpoch;
    final cooldownDecision = _activeCooldownDecision(
      now: now,
      peerId: normalizedPeer,
    );
    if (cooldownDecision != null) {
      return cooldownDecision;
    }

    if (currentUsername == normalizedPeer) {
      return _blocked(
        ConnectionRequestReasonCode.selfRequest,
        peerId: normalizedPeer,
      );
    }

    try {
      if (!await _isAcceptedFriend(normalizedPeer)) {
        return _blocked(
          ConnectionRequestReasonCode.notAcceptedFriend,
          peerId: normalizedPeer,
        );
      }
    } on Object catch (error) {
      return _foundationUnavailable(
        action: 'createConnectionRequest.friendCheck',
        peerId: normalizedPeer,
        error: error,
      );
    }

    try {
      if (!await _isPeerOnline(normalizedPeer)) {
        return _blocked(
          ConnectionRequestReasonCode.peerOffline,
          peerId: normalizedPeer,
        );
      }
    } on Object catch (error) {
      return _blocked(
        ConnectionRequestReasonCode.presenceUnknown,
        peerId: normalizedPeer,
        error: error,
      );
    }

    if (await _isReceiverMuted(
      receiver: normalizedPeer,
      sender: currentUsername,
    )) {
      return _blocked(
        ConnectionRequestReasonCode.mutedByReceiver,
        peerId: normalizedPeer,
      );
    }

    final expiresAt = now + requestTtl.inMilliseconds;
    final requestId = createConnectionRequestId(
      from: currentUsername,
      to: normalizedPeer,
      now: now,
      randomSuffix: _randomSuffix(),
    );
    final pairKey = connectionRequestPairKey(currentUsername, normalizedPeer);
    final payload = ConnectionRequestPayload(
      requestId: requestId,
      from: currentUsername,
      to: normalizedPeer,
      pairKey: pairKey,
      status: ConnectionRequestStatus.pending,
      createdAt: now,
      updatedAt: now,
      expiresAt: expiresAt,
    );
    final lock = _RtdbConnectionRequestPairLock(
      requestId: requestId,
      from: currentUsername,
      to: normalizedPeer,
      pairKey: pairKey,
      status: ConnectionRequestStatus.pending,
      createdAt: now,
      updatedAt: now,
      expiresAt: expiresAt,
    );

    final lockClaim = await _claimPairLock(
      path: 'connectionRequestPairLocks/$pairKey',
      lock: lock,
      now: now,
    );
    if (!lockClaim.allowed) {
      return lockClaim.decision!;
    }

    final quotaReservation = await _reserveBestEffortQuota(
      from: currentUsername,
      to: normalizedPeer,
      now: now,
    );
    if (!quotaReservation.allowed) {
      await _rollbackPairLock(
        path: 'connectionRequestPairLocks/$pairKey',
        requestId: requestId,
      );
      return quotaReservation.decision!;
    }

    final json = payload.toJson();
    try {
      await _updateValue(<String, Object?>{
        'connectionRequests/$normalizedPeer/$requestId': json,
        'connectionRequestOutboxes/$currentUsername/$requestId': json,
      });
    } on Object catch (error) {
      final rolledBack = await _rollbackPairLock(
        path: 'connectionRequestPairLocks/$pairKey',
        requestId: requestId,
      );
      await _rollbackBestEffortQuota(
        from: currentUsername,
        to: normalizedPeer,
        dayKey: quotaReservation.dayKey!,
        now: now,
      );
      return _foundationUnavailable(
        action: 'createConnectionRequest.mirrorWrite',
        requestId: requestId,
        peerId: normalizedPeer,
        error: error,
        diagnostics: <String, Object?>{'rollbackPairLock': rolledBack},
      );
    }

    _lastSuccessfulCreateAt = now;
    return ConnectionRequestDecision(
      allowed: true,
      userMessage: 'Connection request sent to @$normalizedPeer.',
      requestId: requestId,
      status: ConnectionRequestStatus.pending,
      peerId: normalizedPeer,
      quota: await _fetchQuotaFor(
        username: currentUsername,
        targetPeer: normalizedPeer,
      ),
      diagnostics: <String, Object?>{
        'backendMode': 'rtdbOnly',
        'authority': 'clientBestEffort',
        'serverAuthority': bestEffortServerAuthority,
        'securityLevel': bestEffortSecurityLevel,
        'quotaDayKey': quotaReservation.dayKey,
        'usedToday': quotaReservation.usedToday,
        'targetUsedToday': quotaReservation.targetUsedToday,
        'pairKey': pairKey,
      },
    );
  }

  @override
  Future<ConnectionRequestDecision> cancelConnectionRequest(String requestId) {
    return _transitionRequestToTerminal(
      requestId: requestId,
      action: 'cancelConnectionRequest',
      requiredMirror: _RtdbConnectionRequestMirror.outbox,
      targetStatus: ConnectionRequestStatus.canceled,
      successMessage: 'Connection request canceled.',
    );
  }

  @override
  Future<ConnectionRequestDecision> acceptConnectionRequest(String requestId) {
    return _transitionRequestToTerminal(
      requestId: requestId,
      action: 'acceptConnectionRequest',
      requiredMirror: _RtdbConnectionRequestMirror.inbox,
      targetStatus: ConnectionRequestStatus.accepted,
      successMessage: 'Connection request accepted.',
    );
  }

  @override
  Future<ConnectionRequestDecision> rejectConnectionRequest(String requestId) {
    return _transitionRequestToTerminal(
      requestId: requestId,
      action: 'rejectConnectionRequest',
      requiredMirror: _RtdbConnectionRequestMirror.inbox,
      targetStatus: ConnectionRequestStatus.rejected,
      successMessage: 'Connection request rejected.',
    );
  }

  @override
  Future<ConnectionRequestDecision> markConnectionRequestSeen(
    String requestId,
  ) {
    return _markConnectionRequestSeen(requestId);
  }

  @override
  Future<ConnectionRequestDecision> muteConnectionRequestsFromPeer(
    String peerId,
  ) async {
    final normalizedPeer = _normalizePeerForDecision(peerId);
    if (normalizedPeer == null) {
      return _blocked(ConnectionRequestReasonCode.invalidPeer);
    }
    late final String currentUsername;
    try {
      currentUsername = normalizeConnectionRequestUsername(
        await _currentUsername(),
      );
    } on Object catch (error) {
      return _blocked(
        ConnectionRequestReasonCode.authMissing,
        peerId: normalizedPeer,
        error: error,
      );
    }
    final now = _clock().millisecondsSinceEpoch;
    try {
      await _updateValue(<String, Object?>{
        'connectionNotificationMutes/$currentUsername/$normalizedPeer':
            <String, Object?>{'muted': true, 'updatedAt': now},
      });
    } on Object catch (error) {
      return _foundationUnavailable(
        action: 'muteConnectionRequestsFromPeer',
        peerId: normalizedPeer,
        error: error,
      );
    }
    return ConnectionRequestDecision(
      allowed: true,
      userMessage: 'Muted connection requests from @$normalizedPeer.',
      peerId: normalizedPeer,
      diagnostics: const <String, Object?>{
        'backendMode': 'rtdbOnly',
        'authority': 'clientBestEffort',
      },
    );
  }

  @override
  Future<ConnectionRequestDecision> unmuteConnectionRequestsFromPeer(
    String peerId,
  ) async {
    final normalizedPeer = _normalizePeerForDecision(peerId);
    if (normalizedPeer == null) {
      return _blocked(ConnectionRequestReasonCode.invalidPeer);
    }
    late final String currentUsername;
    try {
      currentUsername = normalizeConnectionRequestUsername(
        await _currentUsername(),
      );
    } on Object catch (error) {
      return _blocked(
        ConnectionRequestReasonCode.authMissing,
        peerId: normalizedPeer,
        error: error,
      );
    }
    try {
      await _updateValue(<String, Object?>{
        'connectionNotificationMutes/$currentUsername/$normalizedPeer': null,
      });
    } on Object catch (error) {
      return _foundationUnavailable(
        action: 'unmuteConnectionRequestsFromPeer',
        peerId: normalizedPeer,
        error: error,
      );
    }
    return ConnectionRequestDecision(
      allowed: true,
      userMessage: 'Unmuted connection requests from @$normalizedPeer.',
      peerId: normalizedPeer,
      diagnostics: const <String, Object?>{
        'backendMode': 'rtdbOnly',
        'authority': 'clientBestEffort',
      },
    );
  }

  @override
  Future<ConnectionRequestQuotaSnapshot> fetchConnectionRequestQuota() async {
    late final String username;
    try {
      username = normalizeConnectionRequestUsername(await _currentUsername());
    } on Object catch (error) {
      _emitDiagnostic(
        name: 'connection_request_rtdb_quota_identity_failed',
        path: 'connectionRequestQuota',
        error: error,
      );
      return _quotaSnapshot();
    }
    return _fetchQuotaFor(username: username);
  }

  Future<ConnectionRequestQuotaSnapshot> _fetchQuotaFor({
    required String username,
    String? targetPeer,
  }) async {
    final normalizedTarget = targetPeer == null
        ? null
        : normalizeConnectionRequestUsername(targetPeer);
    final now = _clock().millisecondsSinceEpoch;
    final dayKey = _dayKeyUtc(now);

    final pendingInboundCount = await _countPendingPayloads(
      'connectionRequests/$username',
    );
    final pendingOutboundCount = await _countPendingPayloads(
      'connectionRequestOutboxes/$username',
    );
    final usedToday = await _readUsageCounter(
      path: 'connectionRequestUsage/$username/$dayKey',
    );
    final targetUsedToday = normalizedTarget == null
        ? 0
        : await _readUsageCounter(
            path:
                'connectionRequestTargetUsage/$username/$normalizedTarget/$dayKey',
          );
    return _quotaSnapshot(
      usedToday: usedToday,
      targetUsedToday: targetUsedToday,
      pendingInboundCount: pendingInboundCount,
      pendingOutboundCount: pendingOutboundCount,
    );
  }

  @override
  Stream<List<ConnectionRequestPayload>> watchIncomingConnectionRequests(
    String username,
  ) {
    final normalizedUsername = normalizeConnectionRequestUsername(username);
    return _watchConnectionRequestList(
      path: 'connectionRequests/$normalizedUsername',
    );
  }

  @override
  Stream<List<ConnectionRequestPayload>> watchOutgoingConnectionRequests(
    String username,
  ) {
    final normalizedUsername = normalizeConnectionRequestUsername(username);
    return _watchConnectionRequestList(
      path: 'connectionRequestOutboxes/$normalizedUsername',
    );
  }

  Stream<List<ConnectionRequestPayload>> _watchConnectionRequestList({
    required String path,
  }) {
    return _watchValue(path).map(
      (Object? value) => connectionRequestPayloadsFromSnapshotValue(
        path: path,
        value: value,
        diagnosticsSink: _diagnosticsSink,
      ),
    );
  }

  Future<ConnectionRequestDecision> _transitionRequestToTerminal({
    required String requestId,
    required String action,
    required _RtdbConnectionRequestMirror requiredMirror,
    required ConnectionRequestStatus targetStatus,
    required String successMessage,
  }) async {
    final lookup = await _lookupRequestForAction(
      requestId: requestId,
      action: action,
      requiredMirror: requiredMirror,
    );
    final denied = lookup.deniedDecision;
    if (denied != null) {
      return denied;
    }

    final payload = lookup.payload!;
    final peerId = _peerForPayload(payload, lookup.mirror!);
    if (payload.status.isTerminal) {
      if (payload.status == targetStatus) {
        return _allowedNoopDecision(
          payload: payload,
          peerId: peerId,
          userMessage: successMessage,
        );
      }
      return _terminalRaceDecision(payload, peerId: peerId);
    }

    final now = _clock().millisecondsSinceEpoch;
    final finalStatus =
        canTransition(payload.status, targetStatus, now, payload.expiresAt)
        ? targetStatus
        : ConnectionRequestStatus.expired;
    _RtdbConnectionRequestPairLock? raceLock;
    var lockMismatch = false;
    try {
      final transaction = await _runTransaction(
        'connectionRequestPairLocks/${payload.pairKey}',
        (Object? current) {
          if (current is! Map) {
            lockMismatch = true;
            return const RtdbOnlyConnectionRequestTransactionAction.abort();
          }
          try {
            final lock = _RtdbConnectionRequestPairLock.fromJson(
              pairKey: payload.pairKey,
              json: connectionRequestObjectMap(current),
            );
            if (lock.requestId != payload.requestId) {
              lockMismatch = true;
              return const RtdbOnlyConnectionRequestTransactionAction.abort();
            }
            if (lock.status.isTerminal) {
              raceLock = lock;
              return const RtdbOnlyConnectionRequestTransactionAction.abort();
            }
            return RtdbOnlyConnectionRequestTransactionAction.success(
              lock.copyWith(status: finalStatus, updatedAt: now).toJson(),
            );
          } on FormatException {
            lockMismatch = true;
            return const RtdbOnlyConnectionRequestTransactionAction.abort();
          }
        },
      );
      if (!transaction.committed) {
        final terminalLock = raceLock;
        if (terminalLock != null) {
          return _terminalRaceDecision(
            _copyPayload(
              payload,
              status: terminalLock.status,
              updatedAt: terminalLock.updatedAt,
              respondedAt: terminalLock.updatedAt,
            ),
            peerId: peerId,
          );
        }
        if (lockMismatch) {
          _emitDiagnostic(
            name: 'connection_request_rtdb_pair_lock_mismatch',
            path: 'connectionRequestPairLocks/${payload.pairKey}',
            requestId: payload.requestId,
          );
          return _blocked(
            ConnectionRequestReasonCode.rtdbConflict,
            requestId: payload.requestId,
            peerId: peerId,
            diagnostics: <String, Object?>{'action': action},
          );
        }
        return _foundationUnavailable(
          action: '$action.pairLock',
          requestId: payload.requestId,
          peerId: peerId,
        );
      }
    } on Object catch (error) {
      return _foundationUnavailable(
        action: '$action.pairLock',
        requestId: payload.requestId,
        peerId: peerId,
        error: error,
      );
    }

    final terminal = _copyPayload(
      payload,
      status: finalStatus,
      updatedAt: now,
      respondedAt: now,
    );
    try {
      await _updateValue(_mirrorUpdates(terminal));
    } on Object catch (error) {
      return _foundationUnavailable(
        action: '$action.mirrorWrite',
        requestId: payload.requestId,
        peerId: peerId,
        error: error,
      );
    }

    if (finalStatus == ConnectionRequestStatus.expired &&
        targetStatus != ConnectionRequestStatus.expired) {
      return _blocked(
        ConnectionRequestReasonCode.expired,
        requestId: terminal.requestId,
        peerId: peerId,
        status: terminal.status,
      );
    }
    return ConnectionRequestDecision(
      allowed: true,
      userMessage: successMessage,
      requestId: terminal.requestId,
      status: terminal.status,
      peerId: peerId,
      quota: await fetchConnectionRequestQuota(),
      diagnostics: <String, Object?>{
        'backendMode': 'rtdbOnly',
        'authority': 'clientBestEffort',
        'pairKey': terminal.pairKey,
        'action': action,
      },
    );
  }

  Future<ConnectionRequestDecision> _markConnectionRequestSeen(
    String requestId,
  ) async {
    final lookup = await _lookupRequestForAction(
      requestId: requestId,
      action: 'markConnectionRequestSeen',
      requiredMirror: _RtdbConnectionRequestMirror.inbox,
    );
    final denied = lookup.deniedDecision;
    if (denied != null) {
      return denied;
    }

    final payload = lookup.payload!;
    if (payload.status.isTerminal) {
      return _terminalRaceDecision(payload, peerId: payload.from);
    }
    if (payload.status == ConnectionRequestStatus.seen) {
      return _allowedNoopDecision(
        payload: payload,
        peerId: payload.from,
        userMessage: 'Connection request already seen.',
      );
    }

    final now = _clock().millisecondsSinceEpoch;
    final seen = _copyPayload(
      payload,
      status: ConnectionRequestStatus.seen,
      updatedAt: now,
      seenAt: now,
    );
    try {
      await _updateValue(_mirrorUpdates(seen));
    } on Object catch (error) {
      return _foundationUnavailable(
        action: 'markConnectionRequestSeen.mirrorWrite',
        requestId: seen.requestId,
        peerId: seen.from,
        error: error,
      );
    }
    return ConnectionRequestDecision(
      allowed: true,
      userMessage: 'Connection request marked seen.',
      requestId: seen.requestId,
      status: seen.status,
      peerId: seen.from,
      quota: await fetchConnectionRequestQuota(),
      diagnostics: <String, Object?>{
        'backendMode': 'rtdbOnly',
        'authority': 'clientBestEffort',
        'pairKey': seen.pairKey,
      },
    );
  }

  Future<_RtdbRequestLookup> _lookupRequestForAction({
    required String requestId,
    required String action,
    required _RtdbConnectionRequestMirror requiredMirror,
  }) async {
    late final String normalizedRequestId;
    try {
      normalizedRequestId = validateConnectionRequestId(requestId);
    } on Object catch (error) {
      return _RtdbRequestLookup.denied(
        _blocked(ConnectionRequestReasonCode.malformedRequest, error: error),
      );
    }

    late final String currentUsername;
    try {
      currentUsername = normalizeConnectionRequestUsername(
        await _currentUsername(),
      );
    } on Object catch (error) {
      return _RtdbRequestLookup.denied(
        _blocked(
          ConnectionRequestReasonCode.authMissing,
          requestId: normalizedRequestId,
          error: error,
        ),
      );
    }

    final outbox = await _readRequestPayload(
      path: 'connectionRequestOutboxes/$currentUsername/$normalizedRequestId',
      requestId: normalizedRequestId,
    );
    if (outbox != null) {
      if (requiredMirror != _RtdbConnectionRequestMirror.outbox) {
        return _RtdbRequestLookup.denied(
          _blocked(
            ConnectionRequestReasonCode.permissionDenied,
            requestId: normalizedRequestId,
            peerId: outbox.to,
            diagnostics: <String, Object?>{'action': action},
          ),
        );
      }
      return _RtdbRequestLookup.found(
        payload: outbox,
        mirror: _RtdbConnectionRequestMirror.outbox,
      );
    }

    final inbox = await _readRequestPayload(
      path: 'connectionRequests/$currentUsername/$normalizedRequestId',
      requestId: normalizedRequestId,
    );
    if (inbox != null) {
      if (requiredMirror != _RtdbConnectionRequestMirror.inbox) {
        return _RtdbRequestLookup.denied(
          _blocked(
            ConnectionRequestReasonCode.permissionDenied,
            requestId: normalizedRequestId,
            peerId: inbox.from,
            diagnostics: <String, Object?>{'action': action},
          ),
        );
      }
      return _RtdbRequestLookup.found(
        payload: inbox,
        mirror: _RtdbConnectionRequestMirror.inbox,
      );
    }

    return _RtdbRequestLookup.denied(
      _blocked(
        ConnectionRequestReasonCode.staleRequest,
        requestId: normalizedRequestId,
        diagnostics: <String, Object?>{'action': action},
      ),
    );
  }

  Future<ConnectionRequestPayload?> _readRequestPayload({
    required String path,
    required String requestId,
  }) async {
    try {
      final value = await _getValue(path);
      if (value == null) {
        return null;
      }
      return ConnectionRequestPayload.fromJson(
        requestId: requestId,
        json: connectionRequestObjectMap(value),
      );
    } on FormatException catch (error) {
      _emitDiagnostic(
        name: 'corrupt_connection_request_action_row_ignored',
        path: path,
        requestId: requestId,
        error: error,
      );
      return null;
    } on Object catch (error) {
      _emitDiagnostic(
        name: 'connection_request_rtdb_action_read_failed',
        path: path,
        requestId: requestId,
        error: error,
      );
      return null;
    }
  }

  Future<_RtdbBestEffortQuotaReservation> _reserveBestEffortQuota({
    required String from,
    required String to,
    required int now,
  }) async {
    final dayKey = _dayKeyUtc(now);
    final usagePath = 'connectionRequestUsage/$from/$dayKey';
    final targetUsagePath = 'connectionRequestTargetUsage/$from/$to/$dayKey';

    final daily = await _incrementUsageCounter(
      path: usagePath,
      limit: bestEffortDailyLimit,
      now: now,
    );
    if (!daily.allowed) {
      return _RtdbBestEffortQuotaReservation.denied(
        _quotaDeniedDecision(
          reasonCode:
              daily.reasonCode ??
              ConnectionRequestReasonCode.backendUnavailable,
          peerId: to,
          dayKey: dayKey,
          usedToday: daily.used,
          targetUsedToday: 0,
          path: usagePath,
        ),
      );
    }

    final target = await _incrementUsageCounter(
      path: targetUsagePath,
      limit: bestEffortPerTargetDailyLimit,
      now: now,
    );
    if (!target.allowed) {
      await _decrementUsageCounter(path: usagePath, now: now);
      return _RtdbBestEffortQuotaReservation.denied(
        _quotaDeniedDecision(
          reasonCode:
              target.reasonCode ??
              ConnectionRequestReasonCode.backendUnavailable,
          peerId: to,
          dayKey: dayKey,
          usedToday: max(0, daily.used - 1),
          targetUsedToday: target.used,
          path: targetUsagePath,
        ),
      );
    }

    return _RtdbBestEffortQuotaReservation.allowed(
      dayKey: dayKey,
      usedToday: daily.used,
      targetUsedToday: target.used,
    );
  }

  Future<void> _rollbackBestEffortQuota({
    required String from,
    required String to,
    required String dayKey,
    required int now,
  }) async {
    await _decrementUsageCounter(
      path: 'connectionRequestUsage/$from/$dayKey',
      now: now,
    );
    await _decrementUsageCounter(
      path: 'connectionRequestTargetUsage/$from/$to/$dayKey',
      now: now,
    );
  }

  Future<_RtdbUsageCounterMutation> _incrementUsageCounter({
    required String path,
    required int limit,
    required int now,
  }) async {
    var currentUsed = 0;
    var malformed = false;
    try {
      final transaction = await _runTransaction(path, (Object? current) {
        try {
          final usage = _usageCounterFromValue(current);
          currentUsed = usage.used;
          if (usage.used >= limit) {
            return const RtdbOnlyConnectionRequestTransactionAction.abort();
          }
          return RtdbOnlyConnectionRequestTransactionAction.success(
            _usageCounterJson(usage.used + 1, now),
          );
        } on FormatException {
          malformed = true;
          return const RtdbOnlyConnectionRequestTransactionAction.abort();
        }
      });
      if (!transaction.committed) {
        return _RtdbUsageCounterMutation.denied(
          malformed
              ? ConnectionRequestReasonCode.repairNotAllowed
              : ConnectionRequestReasonCode.bestEffortLimit,
          used: currentUsed,
        );
      }
      final committed = _usageCounterFromValue(transaction.value);
      return _RtdbUsageCounterMutation.allowed(used: committed.used);
    } on Object catch (error) {
      _emitDiagnostic(
        name: 'connection_request_rtdb_usage_increment_failed',
        path: path,
        error: error,
      );
      return _RtdbUsageCounterMutation.denied(
        ConnectionRequestReasonCode.backendUnavailable,
        used: currentUsed,
      );
    }
  }

  Future<void> _decrementUsageCounter({
    required String path,
    required int now,
  }) async {
    try {
      await _runTransaction(path, (Object? current) {
        try {
          final usage = _usageCounterFromValue(current);
          return RtdbOnlyConnectionRequestTransactionAction.success(
            _usageCounterJson(max(0, usage.used - 1), now),
          );
        } on FormatException {
          return const RtdbOnlyConnectionRequestTransactionAction.abort();
        }
      });
    } on Object catch (error) {
      _emitDiagnostic(
        name: 'connection_request_rtdb_usage_rollback_failed',
        path: path,
        error: error,
      );
    }
  }

  Future<int> _readUsageCounter({required String path}) async {
    try {
      return _usageCounterFromValue(await _getValue(path)).used;
    } on Object catch (error) {
      _emitDiagnostic(
        name: 'connection_request_rtdb_usage_read_failed',
        path: path,
        error: error,
      );
      return 0;
    }
  }

  _RtdbUsageCounter _usageCounterFromValue(Object? value) {
    if (value == null) {
      return const _RtdbUsageCounter(used: 0);
    }
    if (value is int) {
      if (value < 0) {
        throw const FormatException('Connection request usage is negative.');
      }
      return _RtdbUsageCounter(used: value);
    }
    if (value is num && value.isFinite && value.roundToDouble() == value) {
      final used = value.toInt();
      if (used < 0) {
        throw const FormatException('Connection request usage is negative.');
      }
      return _RtdbUsageCounter(used: used);
    }
    final map = connectionRequestObjectMap(value);
    final used = map['used'];
    if (used is int) {
      if (used < 0) {
        throw const FormatException('Connection request usage is negative.');
      }
      return _RtdbUsageCounter(used: used);
    }
    if (used is num && used.isFinite && used.roundToDouble() == used) {
      final normalized = used.toInt();
      if (normalized < 0) {
        throw const FormatException('Connection request usage is negative.');
      }
      return _RtdbUsageCounter(used: normalized);
    }
    throw const FormatException('Connection request usage is invalid.');
  }

  Map<String, Object?> _usageCounterJson(int used, int now) {
    return <String, Object?>{
      'used': used,
      'updatedAt': now,
      'serverAuthority': bestEffortServerAuthority,
      'securityLevel': bestEffortSecurityLevel,
    };
  }

  String _dayKeyUtc(int millisecondsSinceEpoch) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      millisecondsSinceEpoch,
      isUtc: true,
    );
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<int> _countPendingPayloads(String path) async {
    try {
      final payloads = connectionRequestPayloadsFromSnapshotValue(
        path: path,
        value: await _getValue(path),
        diagnosticsSink: _diagnosticsSink,
      );
      final now = _clock().millisecondsSinceEpoch;
      return payloads
          .where(
            (ConnectionRequestPayload payload) =>
                !payload.status.isTerminal && !payload.isExpiredAt(now),
          )
          .length;
    } on Object catch (error) {
      _emitDiagnostic(
        name: 'connection_request_rtdb_quota_read_failed',
        path: path,
        error: error,
      );
      return 0;
    }
  }

  Future<bool> _isReceiverMuted({
    required String receiver,
    required String sender,
  }) async {
    try {
      final value = await _getValue(
        'connectionNotificationMutes/$receiver/$sender',
      );
      if (value == true) {
        return true;
      }
      if (value is Map) {
        final mute = connectionRequestObjectMap(value);
        return mute['muted'] == true;
      }
      return false;
    } on Object catch (error) {
      _emitDiagnostic(
        name: 'connection_request_rtdb_mute_read_failed',
        path: 'connectionNotificationMutes/$receiver/$sender',
        error: error,
      );
      return false;
    }
  }

  Future<_RtdbPairLockClaim> _claimPairLock({
    required String path,
    required _RtdbConnectionRequestPairLock lock,
    required int now,
  }) async {
    _RtdbConnectionRequestPairLock? duplicateLock;
    var unknownConflict = false;
    try {
      final transaction = await _runTransaction(path, (Object? current) {
        if (current == null) {
          return RtdbOnlyConnectionRequestTransactionAction.success(
            lock.toJson(),
          );
        }
        if (current is Map) {
          try {
            final existing = _RtdbConnectionRequestPairLock.fromJson(
              pairKey: lock.pairKey,
              json: connectionRequestObjectMap(current),
            );
            if (existing.status.isTerminal || existing.isExpiredAt(now)) {
              return RtdbOnlyConnectionRequestTransactionAction.success(
                lock.toJson(),
              );
            }
            if (existing.status == ConnectionRequestStatus.pending ||
                existing.status == ConnectionRequestStatus.seen) {
              duplicateLock = existing;
              return const RtdbOnlyConnectionRequestTransactionAction.abort();
            }
          } on FormatException {
            unknownConflict = true;
            return const RtdbOnlyConnectionRequestTransactionAction.abort();
          }
        } else {
          unknownConflict = true;
          return const RtdbOnlyConnectionRequestTransactionAction.abort();
        }
        unknownConflict = true;
        return const RtdbOnlyConnectionRequestTransactionAction.abort();
      });
      if (transaction.committed) {
        return const _RtdbPairLockClaim.allowed();
      }
      final duplicate = duplicateLock;
      if (duplicate != null) {
        return _RtdbPairLockClaim.denied(
          _blocked(
            ConnectionRequestReasonCode.duplicatePendingRequest,
            requestId: duplicate.requestId,
            peerId: duplicate.from == lock.from ? duplicate.to : duplicate.from,
            status: duplicate.status,
            diagnostics: <String, Object?>{
              'duplicateRequestId': duplicate.requestId,
              'duplicateExpiresAt': duplicate.expiresAt,
            },
          ),
        );
      }
      return _RtdbPairLockClaim.denied(
        _blocked(
          unknownConflict
              ? ConnectionRequestReasonCode.rtdbConflict
              : ConnectionRequestReasonCode.backendUnavailable,
          requestId: lock.requestId,
          peerId: lock.to,
          diagnostics: <String, Object?>{'pairLockCommitted': false},
        ),
      );
    } on Object catch (error) {
      return _RtdbPairLockClaim.denied(
        _foundationUnavailable(
          action: 'createConnectionRequest.pairLock',
          requestId: lock.requestId,
          peerId: lock.to,
          error: error,
        ),
      );
    }
  }

  Future<bool> _rollbackPairLock({
    required String path,
    required String requestId,
  }) async {
    try {
      final transaction = await _runTransaction(path, (Object? current) {
        if (current is! Map) {
          return const RtdbOnlyConnectionRequestTransactionAction.abort();
        }
        try {
          final value = connectionRequestObjectMap(current);
          if (value['requestId'] == requestId) {
            return const RtdbOnlyConnectionRequestTransactionAction.success(
              null,
            );
          }
        } on FormatException {
          return const RtdbOnlyConnectionRequestTransactionAction.abort();
        }
        return const RtdbOnlyConnectionRequestTransactionAction.abort();
      });
      return transaction.committed;
    } on Object catch (error) {
      _emitDiagnostic(
        name: 'connection_request_rtdb_lock_rollback_failed',
        path: path,
        requestId: requestId,
        error: error,
      );
      return false;
    }
  }

  Map<String, Object?> _mirrorUpdates(ConnectionRequestPayload payload) {
    final json = payload.toJson();
    return <String, Object?>{
      'connectionRequests/${payload.to}/${payload.requestId}': json,
      'connectionRequestOutboxes/${payload.from}/${payload.requestId}': json,
    };
  }

  ConnectionRequestPayload _copyPayload(
    ConnectionRequestPayload payload, {
    required ConnectionRequestStatus status,
    required int updatedAt,
    int? seenAt,
    int? respondedAt,
  }) {
    return ConnectionRequestPayload(
      requestId: payload.requestId,
      from: payload.from,
      to: payload.to,
      pairKey: payload.pairKey,
      status: status,
      reasonCode: payload.reasonCode,
      createdAt: payload.createdAt,
      updatedAt: updatedAt,
      expiresAt: payload.expiresAt,
      seenAt: seenAt ?? payload.seenAt,
      respondedAt: respondedAt ?? payload.respondedAt,
      senderPresenceAt: payload.senderPresenceAt,
      receiverPresenceAt: payload.receiverPresenceAt,
      v: payload.v,
    );
  }

  ConnectionRequestDecision _allowedNoopDecision({
    required ConnectionRequestPayload payload,
    required String peerId,
    required String userMessage,
  }) {
    return ConnectionRequestDecision(
      allowed: true,
      userMessage: userMessage,
      requestId: payload.requestId,
      status: payload.status,
      peerId: peerId,
      diagnostics: const <String, Object?>{
        'backendMode': 'rtdbOnly',
        'authority': 'clientBestEffort',
        'idempotent': true,
      },
    );
  }

  ConnectionRequestDecision _terminalRaceDecision(
    ConnectionRequestPayload payload, {
    required String peerId,
  }) {
    return _blocked(
      ConnectionRequestReasonCode.terminalRaceLost,
      requestId: payload.requestId,
      peerId: peerId,
      status: payload.status,
      diagnostics: <String, Object?>{'terminalStatus': payload.status.name},
    );
  }

  String _peerForPayload(
    ConnectionRequestPayload payload,
    _RtdbConnectionRequestMirror mirror,
  ) {
    return switch (mirror) {
      _RtdbConnectionRequestMirror.outbox => payload.to,
      _RtdbConnectionRequestMirror.inbox => payload.from,
    };
  }

  ConnectionRequestQuotaSnapshot _quotaSnapshot({
    int usedToday = 0,
    int targetUsedToday = 0,
    int pendingInboundCount = 0,
    int pendingOutboundCount = 0,
    int? retryAfterMs,
  }) {
    return ConnectionRequestQuotaSnapshot(
      dailyLimit: bestEffortDailyLimit,
      usedToday: max(0, usedToday),
      extraCreditsRemaining: 0,
      perTargetRemainingToday: max(
        0,
        bestEffortPerTargetDailyLimit - targetUsedToday,
      ),
      pendingOutboundCount: pendingOutboundCount,
      pendingInboundCount: pendingInboundCount,
      retryAfterMs: retryAfterMs,
      disabled: false,
    );
  }

  ConnectionRequestDecision _quotaDeniedDecision({
    required ConnectionRequestReasonCode reasonCode,
    required String peerId,
    required String dayKey,
    required int usedToday,
    required int targetUsedToday,
    required String path,
  }) {
    final quota = _quotaSnapshot(
      usedToday: usedToday,
      targetUsedToday: targetUsedToday,
    );
    return _blocked(
      reasonCode,
      peerId: peerId,
      quota: quota,
      diagnostics: <String, Object?>{
        'quotaPath': path,
        'quotaDayKey': dayKey,
        'serverAuthority': bestEffortServerAuthority,
        'securityLevel': bestEffortSecurityLevel,
        'dailyLimit': bestEffortDailyLimit,
        'usedToday': quota.usedToday,
        'perTargetDailyLimit': bestEffortPerTargetDailyLimit,
        'perTargetRemainingToday': quota.perTargetRemainingToday,
      },
    );
  }

  ConnectionRequestDecision _blocked(
    ConnectionRequestReasonCode reasonCode, {
    String? requestId,
    String? peerId,
    ConnectionRequestStatus? status,
    int? retryAfterMs,
    ConnectionRequestQuotaSnapshot? quota,
    Map<String, Object?> diagnostics = const <String, Object?>{},
    Object? error,
  }) {
    final path = 'connectionRequestRtdb/blocked/${reasonCode.name}';
    _emitDiagnostic(
      name: 'connection_request_rtdb_blocked',
      path: path,
      requestId: requestId,
      error: error,
    );
    return ConnectionRequestDecision(
      allowed: false,
      reasonCode: reasonCode,
      userMessage: messageForConnectionRequestReason(
        reasonCode,
        peerId ?? 'Peer',
        retryAfterMs == null ? null : Duration(milliseconds: retryAfterMs),
      ),
      requestId: requestId,
      status: status,
      peerId: peerId,
      retryAfterMs: retryAfterMs,
      quota: quota,
      diagnostics: <String, Object?>{
        'backendMode': 'rtdbOnly',
        'authority': 'clientBestEffort',
        'serverAuthority': bestEffortServerAuthority,
        'securityLevel': bestEffortSecurityLevel,
        'reasonCode': reasonCode.name,
        'path': path,
        ...diagnostics,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  ConnectionRequestDecision _foundationUnavailable({
    required String action,
    String? requestId,
    String? peerId,
    Map<String, Object?> diagnostics = const <String, Object?>{},
    Object? error,
  }) {
    final path = 'connectionRequestRtdb/$action';
    _emitDiagnostic(
      name: 'connection_request_rtdb_foundation_unavailable',
      path: path,
      requestId: requestId,
      error: error,
    );
    return ConnectionRequestDecision(
      allowed: false,
      reasonCode: ConnectionRequestReasonCode.backendUnavailable,
      userMessage: messageForConnectionRequestReason(
        ConnectionRequestReasonCode.backendUnavailable,
        peerId ?? 'Peer',
      ),
      requestId: requestId,
      peerId: peerId,
      diagnostics: <String, Object?>{
        'backendMode': 'rtdbOnly',
        'authority': 'clientBestEffort',
        'phase': 'foundation',
        'action': action,
        'now': _clock().millisecondsSinceEpoch,
        ...diagnostics,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  ConnectionRequestDecision? _activeCooldownDecision({
    required int now,
    required String peerId,
  }) {
    if (_localCreateCooldown <= Duration.zero) {
      return null;
    }
    final lastCreateAt = _lastSuccessfulCreateAt;
    if (lastCreateAt == null) {
      return null;
    }
    final retryAfterMs =
        _localCreateCooldown.inMilliseconds - (now - lastCreateAt);
    if (retryAfterMs <= 0) {
      return null;
    }
    return _blocked(
      ConnectionRequestReasonCode.rateLimited,
      peerId: peerId,
      retryAfterMs: retryAfterMs,
      diagnostics: <String, Object?>{'localCooldown': true},
    );
  }

  String? _normalizePeerForDecision(String peerId) {
    try {
      return normalizeConnectionRequestUsername(peerId);
    } on FormatException {
      return null;
    }
  }

  void _emitDiagnostic({
    required String name,
    required String path,
    String? requestId,
    Object? error,
  }) {
    _diagnosticsSink?.call(
      ConnectionRequestAdapterDiagnosticEvent(
        name: name,
        path: path,
        requestId: requestId,
        error: error,
      ),
    );
  }
}

final class _RtdbPairLockClaim {
  const _RtdbPairLockClaim.allowed() : allowed = true, decision = null;

  const _RtdbPairLockClaim.denied(this.decision) : allowed = false;

  final bool allowed;
  final ConnectionRequestDecision? decision;
}

final class _RtdbBestEffortQuotaReservation {
  const _RtdbBestEffortQuotaReservation.allowed({
    required this.dayKey,
    required this.usedToday,
    required this.targetUsedToday,
  }) : allowed = true,
       decision = null;

  const _RtdbBestEffortQuotaReservation.denied(this.decision)
    : allowed = false,
      dayKey = null,
      usedToday = 0,
      targetUsedToday = 0;

  final bool allowed;
  final String? dayKey;
  final int usedToday;
  final int targetUsedToday;
  final ConnectionRequestDecision? decision;
}

final class _RtdbUsageCounterMutation {
  const _RtdbUsageCounterMutation.allowed({required this.used})
    : allowed = true,
      reasonCode = null;

  const _RtdbUsageCounterMutation.denied(this.reasonCode, {required this.used})
    : allowed = false;

  final bool allowed;
  final int used;
  final ConnectionRequestReasonCode? reasonCode;
}

final class _RtdbUsageCounter {
  const _RtdbUsageCounter({required this.used});

  final int used;
}

enum _RtdbConnectionRequestMirror { outbox, inbox }

final class _RtdbRequestLookup {
  const _RtdbRequestLookup.found({required this.payload, required this.mirror})
    : deniedDecision = null;

  const _RtdbRequestLookup.denied(this.deniedDecision)
    : payload = null,
      mirror = null;

  final ConnectionRequestPayload? payload;
  final _RtdbConnectionRequestMirror? mirror;
  final ConnectionRequestDecision? deniedDecision;
}

final class _RtdbConnectionRequestPairLock {
  const _RtdbConnectionRequestPairLock({
    required this.requestId,
    required this.from,
    required this.to,
    required this.pairKey,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
  });

  factory _RtdbConnectionRequestPairLock.fromJson({
    required String pairKey,
    required Map<Object?, Object?> json,
  }) {
    final requestId = validateConnectionRequestId(
      _requiredString(json, 'requestId'),
    );
    final from = normalizeConnectionRequestUsername(
      _requiredString(json, 'from'),
    );
    final to = normalizeConnectionRequestUsername(_requiredString(json, 'to'));
    final status = connectionRequestStatusFromName(
      _requiredString(json, 'status'),
    );
    final actualPairKey = _requiredString(json, 'pairKey');
    if (actualPairKey != pairKey ||
        actualPairKey != connectionRequestPairKey(from, to)) {
      throw const FormatException('Connection request lock pairKey invalid.');
    }
    final createdAt = _requiredInt(json, 'createdAt');
    final updatedAt = _requiredInt(json, 'updatedAt');
    final expiresAt = _requiredInt(json, 'expiresAt');
    if (createdAt <= 0 || updatedAt < createdAt || expiresAt <= createdAt) {
      throw const FormatException(
        'Connection request lock timestamps are invalid.',
      );
    }
    return _RtdbConnectionRequestPairLock(
      requestId: requestId,
      from: from,
      to: to,
      pairKey: actualPairKey,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      expiresAt: expiresAt,
    );
  }

  final String requestId;
  final String from;
  final String to;
  final String pairKey;
  final ConnectionRequestStatus status;
  final int createdAt;
  final int updatedAt;
  final int expiresAt;

  bool isExpiredAt(int now) => now >= expiresAt;

  _RtdbConnectionRequestPairLock copyWith({
    ConnectionRequestStatus? status,
    int? updatedAt,
  }) {
    return _RtdbConnectionRequestPairLock(
      requestId: requestId,
      from: from,
      to: to,
      pairKey: pairKey,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestId': requestId,
      'from': from,
      'to': to,
      'pairKey': pairKey,
      'status': status.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'expiresAt': expiresAt,
    };
  }
}

String _validateRequestIdSuffix(String value) {
  final suffix = value.trim();
  if (!_requestIdSuffixPattern.hasMatch(suffix)) {
    throw const FormatException(
      'Connection request id suffix must be short alphanumeric text.',
    );
  }
  return suffix;
}

String _randomAlphanumericSuffix() {
  final random = Random.secure();
  return String.fromCharCodes(
    List<int>.generate(
      8,
      (_) => _requestIdSuffixCharacters.codeUnitAt(
        random.nextInt(_requestIdSuffixCharacters.length),
      ),
    ),
  );
}

String _requiredString(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('Connection request lock $key must be a string.');
}

int _requiredInt(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite && value.roundToDouble() == value) {
    return value.toInt();
  }
  throw FormatException('Connection request lock $key must be an integer.');
}

final RegExp _requestIdSuffixPattern = RegExp(r'^[A-Za-z0-9]{1,16}$');
const String _requestIdSuffixCharacters =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
