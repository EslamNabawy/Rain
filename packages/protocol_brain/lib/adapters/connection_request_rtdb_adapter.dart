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
      quota: await fetchConnectionRequestQuota(),
      diagnostics: <String, Object?>{
        'backendMode': 'rtdbOnly',
        'authority': 'clientBestEffort',
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

    final pendingInboundCount = await _countPendingPayloads(
      'connectionRequests/$username',
    );
    final pendingOutboundCount = await _countPendingPayloads(
      'connectionRequestOutboxes/$username',
    );
    return _quotaSnapshot(
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
    int pendingInboundCount = 0,
    int pendingOutboundCount = 0,
  }) {
    return ConnectionRequestQuotaSnapshot(
      dailyLimit: bestEffortDailyLimit,
      usedToday: 0,
      extraCreditsRemaining: 0,
      perTargetRemainingToday: bestEffortPerTargetDailyLimit,
      pendingOutboundCount: pendingOutboundCount,
      pendingInboundCount: pendingInboundCount,
      disabled: false,
    );
  }

  ConnectionRequestDecision _blocked(
    ConnectionRequestReasonCode reasonCode, {
    String? requestId,
    String? peerId,
    ConnectionRequestStatus? status,
    int? retryAfterMs,
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
      diagnostics: <String, Object?>{
        'backendMode': 'rtdbOnly',
        'authority': 'clientBestEffort',
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
