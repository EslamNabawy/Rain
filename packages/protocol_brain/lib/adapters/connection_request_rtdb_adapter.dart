import 'package:firebase_database/firebase_database.dart';

import '../src/connection_request_adapter.dart';
import '../src/connection_request_contract.dart';

typedef RtdbOnlyConnectionRequestValueStream =
    Stream<Object?> Function(String path);

typedef RtdbOnlyConnectionRequestValueGetter =
    Future<Object?> Function(String path);

final class RtdbOnlyConnectionRequestAdapter
    implements ConnectionRequestAdapter {
  RtdbOnlyConnectionRequestAdapter({
    required DatabaseReference root,
    required Future<String> Function() currentUsername,
    required Future<bool> Function(String peerId) isAcceptedFriend,
    required Future<bool> Function(String peerId) isPeerOnline,
    ConnectionRequestAdapterDiagnosticsSink? diagnosticsSink,
    DateTime Function()? clock,
  }) : this._(
         currentUsername: currentUsername,
         isAcceptedFriend: isAcceptedFriend,
         isPeerOnline: isPeerOnline,
         diagnosticsSink: diagnosticsSink,
         clock: clock,
         watchValue: (String path) {
           return root
               .child(path)
               .onValue
               .map((DatabaseEvent event) => event.snapshot.value);
         },
         getValue: (String path) async {
           return (await root.child(path).get()).value;
         },
       );

  RtdbOnlyConnectionRequestAdapter.forTest({
    required Future<String> Function() currentUsername,
    required Future<bool> Function(String peerId) isAcceptedFriend,
    required Future<bool> Function(String peerId) isPeerOnline,
    required RtdbOnlyConnectionRequestValueStream watchValue,
    RtdbOnlyConnectionRequestValueGetter? getValue,
    ConnectionRequestAdapterDiagnosticsSink? diagnosticsSink,
    DateTime Function()? clock,
  }) : this._(
         currentUsername: currentUsername,
         isAcceptedFriend: isAcceptedFriend,
         isPeerOnline: isPeerOnline,
         diagnosticsSink: diagnosticsSink,
         clock: clock,
         watchValue: watchValue,
         getValue: getValue ?? ((String _) async => null),
       );

  RtdbOnlyConnectionRequestAdapter._({
    required Future<String> Function() currentUsername,
    required Future<bool> Function(String peerId) isAcceptedFriend,
    required Future<bool> Function(String peerId) isPeerOnline,
    required RtdbOnlyConnectionRequestValueStream watchValue,
    required RtdbOnlyConnectionRequestValueGetter getValue,
    ConnectionRequestAdapterDiagnosticsSink? diagnosticsSink,
    DateTime Function()? clock,
  }) : _currentUsername = currentUsername,
       _isAcceptedFriend = isAcceptedFriend,
       _isPeerOnline = isPeerOnline,
       _watchValue = watchValue,
       _getValue = getValue,
       _diagnosticsSink = diagnosticsSink,
       _clock = clock ?? DateTime.now;

  static const int bestEffortDailyLimit = 20;
  static const int bestEffortPerTargetDailyLimit = 3;

  final Future<String> Function() _currentUsername;
  final Future<bool> Function(String peerId) _isAcceptedFriend;
  final Future<bool> Function(String peerId) _isPeerOnline;
  final RtdbOnlyConnectionRequestValueStream _watchValue;
  final RtdbOnlyConnectionRequestValueGetter _getValue;
  final ConnectionRequestAdapterDiagnosticsSink? _diagnosticsSink;
  final DateTime Function() _clock;

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

    return _foundationUnavailable(
      action: 'createConnectionRequest',
      peerId: normalizedPeer,
    );
  }

  @override
  Future<ConnectionRequestDecision> cancelConnectionRequest(String requestId) {
    return _requestActionUnavailable(
      action: 'cancelConnectionRequest',
      requestId: requestId,
    );
  }

  @override
  Future<ConnectionRequestDecision> acceptConnectionRequest(String requestId) {
    return _requestActionUnavailable(
      action: 'acceptConnectionRequest',
      requestId: requestId,
    );
  }

  @override
  Future<ConnectionRequestDecision> rejectConnectionRequest(String requestId) {
    return _requestActionUnavailable(
      action: 'rejectConnectionRequest',
      requestId: requestId,
    );
  }

  @override
  Future<ConnectionRequestDecision> markConnectionRequestSeen(
    String requestId,
  ) {
    return _requestActionUnavailable(
      action: 'markConnectionRequestSeen',
      requestId: requestId,
    );
  }

  @override
  Future<ConnectionRequestDecision> muteConnectionRequestsFromPeer(
    String peerId,
  ) async {
    final normalizedPeer = _normalizePeerForDecision(peerId);
    if (normalizedPeer == null) {
      return _blocked(ConnectionRequestReasonCode.invalidPeer);
    }
    return _foundationUnavailable(
      action: 'muteConnectionRequestsFromPeer',
      peerId: normalizedPeer,
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
    return _foundationUnavailable(
      action: 'unmuteConnectionRequestsFromPeer',
      peerId: normalizedPeer,
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

  Future<ConnectionRequestDecision> _requestActionUnavailable({
    required String action,
    required String requestId,
  }) async {
    late final String normalizedRequestId;
    try {
      normalizedRequestId = validateConnectionRequestId(requestId);
    } on Object catch (error) {
      return _blocked(
        ConnectionRequestReasonCode.malformedRequest,
        error: error,
      );
    }
    return _foundationUnavailable(
      action: action,
      requestId: normalizedRequestId,
    );
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
      ),
      requestId: requestId,
      peerId: peerId,
      diagnostics: <String, Object?>{
        'backendMode': 'rtdbOnly',
        'authority': 'clientBestEffort',
        'reasonCode': reasonCode.name,
        'path': path,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  ConnectionRequestDecision _foundationUnavailable({
    required String action,
    String? requestId,
    String? peerId,
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
        if (error != null) 'error': error.toString(),
      },
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
