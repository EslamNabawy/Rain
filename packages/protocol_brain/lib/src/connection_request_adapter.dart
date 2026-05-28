import 'connection_request_contract.dart';

abstract interface class ConnectionRequestAdapter {
  Future<ConnectionRequestDecision> createConnectionRequest(String peerId);

  Future<ConnectionRequestDecision> cancelConnectionRequest(String requestId);

  Future<ConnectionRequestDecision> acceptConnectionRequest(String requestId);

  Future<ConnectionRequestDecision> rejectConnectionRequest(String requestId);

  Future<ConnectionRequestDecision> markConnectionRequestSeen(String requestId);

  Future<ConnectionRequestDecision> muteConnectionRequestsFromPeer(
    String peerId,
  );

  Future<ConnectionRequestDecision> unmuteConnectionRequestsFromPeer(
    String peerId,
  );

  Future<ConnectionRequestQuotaSnapshot> fetchConnectionRequestQuota();

  Stream<List<ConnectionRequestPayload>> watchIncomingConnectionRequests(
    String username,
  );

  Stream<List<ConnectionRequestPayload>> watchOutgoingConnectionRequests(
    String username,
  );
}

typedef ConnectionRequestAdapterDiagnosticsSink =
    void Function(ConnectionRequestAdapterDiagnosticEvent event);

final class ConnectionRequestAdapterDiagnosticEvent {
  const ConnectionRequestAdapterDiagnosticEvent({
    required this.name,
    required this.path,
    this.requestId,
    this.error,
  });

  final String name;
  final String path;
  final String? requestId;
  final Object? error;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'path': path,
      if (requestId != null) 'requestId': requestId,
      if (error != null) 'error': error.toString(),
    };
  }
}

ConnectionRequestDecision connectionRequestDecisionFromFunctionJson(
  Map<Object?, Object?> json, {
  String? fallbackPeerId,
}) {
  final allowed = _requiredBool(json, 'allowed');
  final retryAfterMs = _optionalInt(json, 'retryAfterMs');
  final reasonCode = _optionalReasonCode(json, 'reasonCode');
  final status = _optionalStatus(json, 'status');
  final requestId = _optionalRequestId(json, 'requestId');
  final peerId =
      _optionalUsername(json, 'peerId') ??
      _optionalUsername(json, 'peer') ??
      _optionalUsername(json, 'to') ??
      _optionalUsername(json, 'from') ??
      _safeOptionalUsername(fallbackPeerId);
  final quotaJson = _optionalMap(json, 'quota');
  final diagnostics = _diagnosticsFromJson(_optionalMap(json, 'diagnostics'));
  final message =
      _optionalString(json, 'userMessage') ??
      (reasonCode == null
          ? ''
          : messageForConnectionRequestReason(
              reasonCode,
              peerId ?? fallbackPeerId ?? 'Peer',
              retryAfterMs == null
                  ? null
                  : Duration(milliseconds: retryAfterMs),
            ));

  return ConnectionRequestDecision(
    allowed: allowed,
    reasonCode: reasonCode,
    userMessage: message,
    requestId: requestId,
    status: status,
    peerId: peerId,
    blockingPeerId: _optionalUsername(json, 'blockingPeerId'),
    retryAfterMs: retryAfterMs,
    quota: quotaJson == null
        ? null
        : connectionRequestQuotaSnapshotFromFunctionJson(quotaJson),
    diagnostics: diagnostics,
  );
}

ConnectionRequestDecision backendRejectedConnectionRequestDecision({
  String? peerId,
  Object? error,
  Map<String, Object?> diagnostics = const <String, Object?>{},
}) {
  final normalizedPeer = _safeOptionalUsername(peerId);
  return ConnectionRequestDecision(
    allowed: false,
    reasonCode: ConnectionRequestReasonCode.backendRejected,
    userMessage: messageForConnectionRequestReason(
      ConnectionRequestReasonCode.backendRejected,
      normalizedPeer ?? 'Peer',
    ),
    peerId: normalizedPeer,
    diagnostics: <String, Object?>{
      if (error != null) 'error': error.toString(),
      ...diagnostics,
    },
  );
}

ConnectionRequestQuotaSnapshot connectionRequestQuotaSnapshotFromFunctionJson(
  Map<Object?, Object?> json,
) {
  if (json.containsKey('dailyLimit')) {
    return ConnectionRequestQuotaSnapshot.fromJson(json);
  }
  final dailyLimit = _optionalNonNegativeInt(json, 'dailyFreeLimit') ?? 0;
  final usedToday =
      _optionalNonNegativeInt(json, 'usedToday') ??
      _optionalNonNegativeInt(json, 'freeUsed') ??
      0;
  final perTargetLimit =
      _optionalNonNegativeInt(json, 'perTargetDailyLimit') ?? 0;
  final perTargetUsed = _optionalNonNegativeInt(json, 'perTargetUsed') ?? 0;
  return ConnectionRequestQuotaSnapshot(
    dailyLimit: dailyLimit,
    usedToday: usedToday,
    extraCreditsRemaining:
        _optionalNonNegativeInt(json, 'extraCreditsRemaining') ?? 0,
    perTargetRemainingToday: (perTargetLimit - perTargetUsed)
        .clamp(0, 1 << 31)
        .toInt(),
    pendingOutboundCount:
        _optionalNonNegativeInt(json, 'pendingOutboundCount') ?? 0,
    pendingInboundCount:
        _optionalNonNegativeInt(json, 'pendingInboundCount') ?? 0,
    retryAfterMs: _optionalNonNegativeInt(json, 'retryAfterMs'),
    unlimitedUntil: _optionalNonNegativeInt(json, 'unlimitedUntil'),
    disabled: _optionalBool(json, 'disabled') ?? false,
  );
}

List<ConnectionRequestPayload> connectionRequestPayloadsFromSnapshotValue({
  required String path,
  required Object? value,
  ConnectionRequestAdapterDiagnosticsSink? diagnosticsSink,
}) {
  if (value == null) {
    return const <ConnectionRequestPayload>[];
  }
  Map<Object?, Object?> rows;
  try {
    rows = connectionRequestObjectMap(value);
  } on FormatException catch (error) {
    diagnosticsSink?.call(
      ConnectionRequestAdapterDiagnosticEvent(
        name: 'corrupt_connection_request_list_ignored',
        path: path,
        error: error,
      ),
    );
    return const <ConnectionRequestPayload>[];
  }

  final payloads = <ConnectionRequestPayload>[];
  for (final entry in rows.entries) {
    final requestId = entry.key;
    if (requestId is! String) {
      diagnosticsSink?.call(
        ConnectionRequestAdapterDiagnosticEvent(
          name: 'corrupt_connection_request_row_ignored',
          path: path,
          error: 'request id is not a string',
        ),
      );
      continue;
    }
    try {
      payloads.add(
        ConnectionRequestPayload.fromJson(
          requestId: requestId,
          json: connectionRequestObjectMap(entry.value),
        ),
      );
    } on FormatException catch (error) {
      diagnosticsSink?.call(
        ConnectionRequestAdapterDiagnosticEvent(
          name: 'corrupt_connection_request_row_ignored',
          path: path,
          requestId: requestId,
          error: error,
        ),
      );
      continue;
    }
  }
  payloads.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return List<ConnectionRequestPayload>.unmodifiable(payloads);
}

Map<Object?, Object?> connectionRequestObjectMap(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<Object?, Object?>.from(value);
  }
  throw const FormatException('Expected connection request JSON map.');
}

bool _requiredBool(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Connection request decision $key must be a boolean.');
}

bool? _optionalBool(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('Connection request decision $key must be a boolean.');
}

int? _optionalInt(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite && value.roundToDouble() == value) {
    return value.toInt();
  }
  throw FormatException('Connection request decision $key must be an integer.');
}

int? _optionalNonNegativeInt(Map<Object?, Object?> json, String key) {
  final value = _optionalInt(json, key);
  if (value == null) {
    return null;
  }
  if (value < 0) {
    throw FormatException(
      'Connection request decision $key must be non-negative.',
    );
  }
  return value;
}

String? _optionalString(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('Connection request decision $key must be a string.');
}

String? _optionalRequestId(Map<Object?, Object?> json, String key) {
  final value = _optionalString(json, key);
  if (value == null) {
    return null;
  }
  return validateConnectionRequestId(value);
}

String? _optionalUsername(Map<Object?, Object?> json, String key) {
  return _safeOptionalUsername(_optionalString(json, key));
}

String? _safeOptionalUsername(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  try {
    return normalizeConnectionRequestUsername(value);
  } on FormatException {
    return null;
  }
}

ConnectionRequestReasonCode? _optionalReasonCode(
  Map<Object?, Object?> json,
  String key,
) {
  final value = _optionalString(json, key);
  if (value == null) {
    return null;
  }
  return connectionRequestReasonCodeFromName(value);
}

ConnectionRequestStatus? _optionalStatus(
  Map<Object?, Object?> json,
  String key,
) {
  final value = _optionalString(json, key);
  if (value == null) {
    return null;
  }
  return connectionRequestStatusFromName(value);
}

Map<Object?, Object?>? _optionalMap(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  return connectionRequestObjectMap(value);
}

Map<String, Object?> _diagnosticsFromJson(Map<Object?, Object?>? json) {
  if (json == null) {
    return const <String, Object?>{};
  }
  final diagnostics = <String, Object?>{};
  for (final entry in json.entries) {
    final key = entry.key;
    if (key is String) {
      diagnostics[key] = entry.value;
    }
  }
  return diagnostics;
}
