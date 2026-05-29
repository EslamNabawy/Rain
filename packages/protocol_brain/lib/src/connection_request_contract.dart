enum ConnectionRequestStatus {
  pending,
  seen,
  accepted,
  rejected,
  canceled,
  expired,
  failed;

  bool get isTerminal => isTerminalStatus(this);
}

enum ConnectionRequestReasonCode {
  authMissing,
  unknownUser,
  invalidPeer,
  selfRequest,
  backendUnavailable,
  malformedRequest,
  confirmationRequired,
  peerOffline,
  peerAlreadyOnline,
  presenceUnknown,
  notAcceptedFriend,
  blocked,
  mutedByReceiver,
  manualDisconnectActive,
  activeCall,
  activeTransfer,
  rateLimited,
  dailyLimitExceeded,
  extraCreditsExhausted,
  perTargetLimitExceeded,
  tooManyPendingRequests,
  receiverInboxFull,
  duplicatePendingRequest,
  bestEffortLimit,
  rtdbConflict,
  repairNotAllowed,
  notificationsDisabledByAdmin,
  notificationsTemporarilyDisabled,
  expired,
  backendRejected,
  permissionDenied,
  notificationUnavailable,
  staleRequest,
  terminalRaceLost,
}

enum ConnectionRequestDirection { inbound, outbound }

enum ConnectionRequestActionKind {
  connect,
  ignore,
  cancel,
  reject,
  mute,
  unmute,
  dismiss,
}

final class ConnectionRequestTransition {
  const ConnectionRequestTransition({
    required this.from,
    required this.to,
    required this.now,
    required this.expiresAt,
  });

  final ConnectionRequestStatus from;
  final ConnectionRequestStatus to;
  final int now;
  final int expiresAt;

  bool get allowed => canTransition(from, to, now, expiresAt);
}

final class ConnectionRequestQuotaSnapshot {
  const ConnectionRequestQuotaSnapshot({
    required this.dailyLimit,
    required this.usedToday,
    required this.extraCreditsRemaining,
    required this.perTargetRemainingToday,
    required this.pendingOutboundCount,
    required this.pendingInboundCount,
    this.retryAfterMs,
    this.unlimitedUntil,
    this.disabled = false,
  });

  final int dailyLimit;
  final int usedToday;
  final int extraCreditsRemaining;
  final int perTargetRemainingToday;
  final int pendingOutboundCount;
  final int pendingInboundCount;
  final int? retryAfterMs;
  final int? unlimitedUntil;
  final bool disabled;

  Map<String, Object?> toJson() {
    _validateNonNegative('dailyLimit', dailyLimit);
    _validateNonNegative('usedToday', usedToday);
    _validateNonNegative('extraCreditsRemaining', extraCreditsRemaining);
    _validateNonNegative('perTargetRemainingToday', perTargetRemainingToday);
    _validateNonNegative('pendingOutboundCount', pendingOutboundCount);
    _validateNonNegative('pendingInboundCount', pendingInboundCount);
    if (retryAfterMs != null) {
      _validateNonNegative('retryAfterMs', retryAfterMs!);
    }
    if (unlimitedUntil != null && unlimitedUntil! <= 0) {
      throw const FormatException(
        'Connection request unlimitedUntil must be positive.',
      );
    }
    return <String, Object?>{
      'dailyLimit': dailyLimit,
      'usedToday': usedToday,
      'extraCreditsRemaining': extraCreditsRemaining,
      'perTargetRemainingToday': perTargetRemainingToday,
      'pendingOutboundCount': pendingOutboundCount,
      'pendingInboundCount': pendingInboundCount,
      if (retryAfterMs != null) 'retryAfterMs': retryAfterMs,
      if (unlimitedUntil != null) 'unlimitedUntil': unlimitedUntil,
      'disabled': disabled,
    };
  }

  factory ConnectionRequestQuotaSnapshot.fromJson(Map<Object?, Object?> json) {
    return ConnectionRequestQuotaSnapshot(
      dailyLimit: _requiredInt(json, 'dailyLimit'),
      usedToday: _requiredInt(json, 'usedToday'),
      extraCreditsRemaining: _requiredInt(json, 'extraCreditsRemaining'),
      perTargetRemainingToday: _requiredInt(json, 'perTargetRemainingToday'),
      pendingOutboundCount: _requiredInt(json, 'pendingOutboundCount'),
      pendingInboundCount: _requiredInt(json, 'pendingInboundCount'),
      retryAfterMs: _optionalInt(json, 'retryAfterMs'),
      unlimitedUntil: _optionalInt(json, 'unlimitedUntil'),
      disabled: _optionalBool(json, 'disabled') ?? false,
    )..toJson();
  }
}

final class ConnectionRequestDecision {
  const ConnectionRequestDecision({
    required this.allowed,
    required this.userMessage,
    this.reasonCode,
    this.requestId,
    this.status,
    this.peerId,
    this.blockingPeerId,
    this.retryAfterMs,
    this.quota,
    this.diagnostics = const <String, Object?>{},
  });

  final bool allowed;
  final ConnectionRequestReasonCode? reasonCode;
  final String userMessage;
  final String? requestId;
  final ConnectionRequestStatus? status;
  final String? peerId;
  final String? blockingPeerId;
  final int? retryAfterMs;
  final ConnectionRequestQuotaSnapshot? quota;
  final Map<String, Object?> diagnostics;
}

final class ConnectionRequestPayload {
  const ConnectionRequestPayload({
    required this.requestId,
    required this.from,
    required this.to,
    required this.pairKey,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    this.reasonCode,
    this.seenAt,
    this.respondedAt,
    this.senderPresenceAt,
    this.receiverPresenceAt,
    this.v = version,
  });

  static const int version = 1;

  final int v;
  final String requestId;
  final String from;
  final String to;
  final String pairKey;
  final ConnectionRequestStatus status;
  final ConnectionRequestReasonCode? reasonCode;
  final int createdAt;
  final int updatedAt;
  final int expiresAt;
  final int? seenAt;
  final int? respondedAt;
  final int? senderPresenceAt;
  final int? receiverPresenceAt;

  Map<String, Object?> toJson() {
    validate();
    return <String, Object?>{
      'v': v,
      'requestId': requestId,
      'from': from,
      'to': to,
      'pairKey': pairKey,
      'status': status.name,
      if (reasonCode != null) 'reasonCode': reasonCode!.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'expiresAt': expiresAt,
      if (seenAt != null) 'seenAt': seenAt,
      if (respondedAt != null) 'respondedAt': respondedAt,
      if (senderPresenceAt != null) 'senderPresenceAt': senderPresenceAt,
      if (receiverPresenceAt != null) 'receiverPresenceAt': receiverPresenceAt,
    };
  }

  factory ConnectionRequestPayload.fromJson({
    required String requestId,
    required Map<Object?, Object?> json,
  }) {
    final payload = ConnectionRequestPayload(
      v: _optionalInt(json, 'v') ?? version,
      requestId: _pathOrBodyRequestId(pathRequestId: requestId, json: json),
      from: _requiredString(json, 'from', max: _maxUsernameLength),
      to: _requiredString(json, 'to', max: _maxUsernameLength),
      pairKey: _requiredString(json, 'pairKey', max: _maxPairKeyLength),
      status: connectionRequestStatusFromName(
        _requiredString(json, 'status', max: 32),
      ),
      reasonCode: _optionalReasonCode(json, 'reasonCode'),
      createdAt: _requiredInt(json, 'createdAt'),
      updatedAt: _requiredInt(json, 'updatedAt'),
      expiresAt: _requiredInt(json, 'expiresAt'),
      seenAt: _optionalInt(json, 'seenAt'),
      respondedAt: _terminalResponseTimestamp(json),
      senderPresenceAt: _optionalInt(json, 'senderPresenceAt'),
      receiverPresenceAt: _optionalInt(json, 'receiverPresenceAt'),
    );
    payload.validate();
    return payload;
  }

  static ConnectionRequestCleanupPayload? tryParseForCleanup({
    required String requestId,
    required Map<Object?, Object?> json,
  }) {
    try {
      final payload = ConnectionRequestPayload.fromJson(
        requestId: requestId,
        json: json,
      );
      return ConnectionRequestCleanupPayload(
        requestId: payload.requestId,
        from: payload.from,
        to: payload.to,
        pairKey: payload.pairKey,
        status: payload.status,
        expiresAt: payload.expiresAt,
      );
    } on FormatException {
      try {
        final from = normalizeConnectionRequestUsername(
          _requiredString(json, 'from', max: _maxUsernameLength),
        );
        final to = normalizeConnectionRequestUsername(
          _requiredString(json, 'to', max: _maxUsernameLength),
        );
        final statusName = _optionalString(json, 'status', max: 32);
        final status = statusName == null
            ? null
            : _tryConnectionRequestStatusFromName(statusName);
        return ConnectionRequestCleanupPayload(
          requestId: validateConnectionRequestId(requestId),
          from: from,
          to: to,
          pairKey: connectionRequestPairKey(from, to),
          status: status,
          expiresAt: _optionalInt(json, 'expiresAt'),
        );
      } on FormatException {
        return null;
      }
    }
  }

  bool isExpiredAt(int now) => now >= expiresAt;

  void validate() {
    if (v != version) {
      throw const FormatException('Connection request version invalid.');
    }
    validateConnectionRequestId(requestId);
    final normalizedFrom = normalizeConnectionRequestUsername(from);
    final normalizedTo = normalizeConnectionRequestUsername(to);
    if (normalizedFrom == normalizedTo) {
      throw const FormatException(
        'Connection request participants must differ.',
      );
    }
    if (from != normalizedFrom || to != normalizedTo) {
      throw const FormatException(
        'Connection request usernames must be normalized.',
      );
    }
    if (pairKey != connectionRequestPairKey(from, to)) {
      throw const FormatException(
        'Connection request pairKey is not canonical.',
      );
    }
    _validateTimestampOrder(createdAt: createdAt, updatedAt: updatedAt);
    _validateExpiresAt(createdAt: createdAt, expiresAt: expiresAt);
    if (seenAt != null && seenAt! < createdAt) {
      throw const FormatException('Connection request seenAt invalid.');
    }
    if (respondedAt != null && respondedAt! < createdAt) {
      throw const FormatException('Connection request respondedAt invalid.');
    }
    if (senderPresenceAt != null && senderPresenceAt! <= 0) {
      throw const FormatException(
        'Connection request senderPresenceAt invalid.',
      );
    }
    if (receiverPresenceAt != null && receiverPresenceAt! <= 0) {
      throw const FormatException(
        'Connection request receiverPresenceAt invalid.',
      );
    }
    if (status.isTerminal && respondedAt == null) {
      throw const FormatException(
        'Terminal connection request requires respondedAt.',
      );
    }
  }
}

final class ConnectionRequestCleanupPayload {
  const ConnectionRequestCleanupPayload({
    required this.requestId,
    required this.from,
    required this.to,
    required this.pairKey,
    required this.status,
    required this.expiresAt,
  });

  final String requestId;
  final String from;
  final String to;
  final String pairKey;
  final ConnectionRequestStatus? status;
  final int? expiresAt;
}

final class ConnectionRequestSurfaceModel {
  const ConnectionRequestSurfaceModel({
    required this.requestId,
    required this.peerId,
    required this.peerLabel,
    required this.direction,
    required this.status,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.feedback,
    this.quota,
  });

  final String requestId;
  final String peerId;
  final String peerLabel;
  final ConnectionRequestDirection direction;
  final ConnectionRequestStatus status;
  final String title;
  final String subtitle;
  final List<ConnectionRequestActionModel> actions;
  final ConnectionRequestFeedbackModel? feedback;
  final ConnectionRequestQuotaSnapshot? quota;
}

final class ConnectionRequestActionModel {
  const ConnectionRequestActionModel({
    required this.kind,
    required this.label,
    required this.semanticLabel,
    required this.enabled,
    this.tooltip,
    this.reasonCode,
  });

  final ConnectionRequestActionKind kind;
  final String label;
  final String semanticLabel;
  final bool enabled;
  final String? tooltip;
  final ConnectionRequestReasonCode? reasonCode;
}

final class ConnectionRequestFeedbackModel {
  const ConnectionRequestFeedbackModel({
    required this.reasonCode,
    required this.message,
    this.retryAfter,
  });

  final ConnectionRequestReasonCode reasonCode;
  final String message;
  final Duration? retryAfter;
}

bool isTerminalStatus(ConnectionRequestStatus status) {
  return switch (status) {
    ConnectionRequestStatus.accepted ||
    ConnectionRequestStatus.rejected ||
    ConnectionRequestStatus.canceled ||
    ConnectionRequestStatus.expired ||
    ConnectionRequestStatus.failed => true,
    ConnectionRequestStatus.pending || ConnectionRequestStatus.seen => false,
  };
}

bool canTransition(
  ConnectionRequestStatus from,
  ConnectionRequestStatus to,
  int now,
  int expiresAt,
) {
  if (now <= 0 || expiresAt <= 0) {
    return false;
  }
  if (from == to) {
    return true;
  }
  if (from.isTerminal) {
    return false;
  }
  if (to == ConnectionRequestStatus.accepted && now >= expiresAt) {
    return false;
  }
  return switch (from) {
    ConnectionRequestStatus.pending => switch (to) {
      ConnectionRequestStatus.seen ||
      ConnectionRequestStatus.accepted ||
      ConnectionRequestStatus.rejected ||
      ConnectionRequestStatus.canceled ||
      ConnectionRequestStatus.expired ||
      ConnectionRequestStatus.failed => true,
      ConnectionRequestStatus.pending => true,
    },
    ConnectionRequestStatus.seen => switch (to) {
      ConnectionRequestStatus.accepted ||
      ConnectionRequestStatus.rejected ||
      ConnectionRequestStatus.canceled ||
      ConnectionRequestStatus.expired ||
      ConnectionRequestStatus.failed => true,
      ConnectionRequestStatus.pending || ConnectionRequestStatus.seen => false,
    },
    ConnectionRequestStatus.accepted ||
    ConnectionRequestStatus.rejected ||
    ConnectionRequestStatus.canceled ||
    ConnectionRequestStatus.expired ||
    ConnectionRequestStatus.failed => false,
  };
}

String messageForConnectionRequestReason(
  ConnectionRequestReasonCode reasonCode,
  String peerLabel, [
  Duration? retryAfter,
]) {
  final peer = _displayPeerLabel(peerLabel);
  return switch (reasonCode) {
    ConnectionRequestReasonCode.authMissing =>
      'Sign in before requesting a connection.',
    ConnectionRequestReasonCode.unknownUser =>
      'Could not find your Rain account. Sign in again.',
    ConnectionRequestReasonCode.invalidPeer =>
      'Choose a valid peer before requesting a connection.',
    ConnectionRequestReasonCode.selfRequest =>
      'You cannot request a connection with yourself.',
    ConnectionRequestReasonCode.backendUnavailable =>
      'Connection request service is unavailable. Try again.',
    ConnectionRequestReasonCode.malformedRequest =>
      'Connection request is malformed. Try again.',
    ConnectionRequestReasonCode.confirmationRequired =>
      'Confirm before sending a request notification.',
    ConnectionRequestReasonCode.peerOffline =>
      '$peer is offline. Keep both apps open, then try again.',
    ConnectionRequestReasonCode.peerAlreadyOnline =>
      '$peer is online. Connect directly instead of sending a request notification.',
    ConnectionRequestReasonCode.presenceUnknown =>
      'Could not confirm $peer is offline. Try again.',
    ConnectionRequestReasonCode.notAcceptedFriend =>
      'You can only request a connection with accepted friends.',
    ConnectionRequestReasonCode.blocked =>
      'This connection request cannot be sent.',
    ConnectionRequestReasonCode.mutedByReceiver =>
      '$peer is not receiving connection request notifications right now.',
    ConnectionRequestReasonCode.manualDisconnectActive =>
      'You disconnected $peer. Press Connect to open the peer lane again.',
    ConnectionRequestReasonCode.activeCall =>
      'Finish the call before requesting another connection.',
    ConnectionRequestReasonCode.activeTransfer =>
      'Finish the active file transfer before requesting a connection.',
    ConnectionRequestReasonCode.rateLimited =>
      'Too many connection requests. Try again ${_retryAfterText(retryAfter)}.',
    ConnectionRequestReasonCode.dailyLimitExceeded =>
      'Daily connection request limit reached.',
    ConnectionRequestReasonCode.extraCreditsExhausted =>
      'No extra connection request credits are available.',
    ConnectionRequestReasonCode.perTargetLimitExceeded =>
      'You have sent too many connection requests to $peer today.',
    ConnectionRequestReasonCode.tooManyPendingRequests =>
      'You have too many pending connection requests.',
    ConnectionRequestReasonCode.receiverInboxFull =>
      '$peer has too many pending connection requests.',
    ConnectionRequestReasonCode.duplicatePendingRequest =>
      'A connection request to $peer is already pending.',
    ConnectionRequestReasonCode.bestEffortLimit =>
      'Connection requests are cooling down. Try again soon.',
    ConnectionRequestReasonCode.rtdbConflict =>
      'Another request is already in progress.',
    ConnectionRequestReasonCode.repairNotAllowed =>
      'This request could not be repaired. Try again.',
    ConnectionRequestReasonCode.notificationsDisabledByAdmin =>
      'Connection request notifications are temporarily disabled.',
    ConnectionRequestReasonCode.notificationsTemporarilyDisabled =>
      'Connection request notifications are temporarily unavailable.',
    ConnectionRequestReasonCode.expired =>
      'This connection request expired. Try again.',
    ConnectionRequestReasonCode.backendRejected =>
      'Connection request could not be sent. Try again.',
    ConnectionRequestReasonCode.permissionDenied =>
      'Connection request is not allowed for this account.',
    ConnectionRequestReasonCode.notificationUnavailable =>
      'Notification delivery is unavailable. Try again later.',
    ConnectionRequestReasonCode.staleRequest =>
      'This connection request is no longer current.',
    ConnectionRequestReasonCode.terminalRaceLost =>
      'This connection request was already handled.',
  };
}

String normalizeConnectionRequestUsername(String value) {
  final normalized = value.trim().toLowerCase();
  _validateUsername(normalized);
  return normalized;
}

String validateConnectionRequestId(String value) {
  final normalized = value.trim();
  _validateRequestId(normalized);
  return normalized;
}

String connectionRequestPairKey(String from, String to) {
  final normalizedFrom = normalizeConnectionRequestUsername(from);
  final normalizedTo = normalizeConnectionRequestUsername(to);
  if (normalizedFrom == normalizedTo) {
    throw const FormatException('Connection request pair requires two users.');
  }
  return '$normalizedFrom:$normalizedTo';
}

ConnectionRequestStatus connectionRequestStatusFromName(String value) {
  final status = _tryConnectionRequestStatusFromName(value);
  if (status != null) {
    return status;
  }
  throw FormatException('Unknown connection request status: $value');
}

ConnectionRequestReasonCode connectionRequestReasonCodeFromName(String value) {
  for (final reasonCode in ConnectionRequestReasonCode.values) {
    if (reasonCode.name == value) {
      return reasonCode;
    }
  }
  throw FormatException('Unknown connection request reason code: $value');
}

ConnectionRequestStatus? _tryConnectionRequestStatusFromName(String value) {
  for (final status in ConnectionRequestStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  return null;
}

ConnectionRequestReasonCode? _optionalReasonCode(
  Map<Object?, Object?> json,
  String key,
) {
  final value = _optionalString(json, key, max: 64);
  if (value == null) {
    return null;
  }
  return connectionRequestReasonCodeFromName(value);
}

String _pathOrBodyRequestId({
  required String pathRequestId,
  required Map<Object?, Object?> json,
}) {
  final normalized = validateConnectionRequestId(pathRequestId);
  final bodyRequestId = _optionalString(
    json,
    'requestId',
    max: _maxRequestIdLength,
  );
  if (bodyRequestId != null &&
      validateConnectionRequestId(bodyRequestId) != normalized) {
    throw const FormatException('Connection request id mismatch.');
  }
  return normalized;
}

String _displayPeerLabel(String peerLabel) {
  final trimmed = peerLabel.trim();
  if (trimmed.isEmpty) {
    return 'Peer';
  }
  return trimmed.startsWith('@') ? trimmed : '@$trimmed';
}

String _retryAfterText(Duration? retryAfter) {
  if (retryAfter == null) {
    return 'later';
  }
  final seconds = retryAfter.inSeconds <= 0 ? 1 : retryAfter.inSeconds;
  if (seconds < 60) {
    return 'in ${seconds}s';
  }
  final minutes = (seconds / 60).ceil();
  return 'in ${minutes}m';
}

const int _maxUsernameLength = 24;
const int _maxRequestIdLength = 128;
const int _maxPairKeyLength = (_maxUsernameLength * 2) + 1;

final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');
final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{3,128}$');

void _validateUsername(String value) {
  if (!_usernamePattern.hasMatch(value)) {
    throw const FormatException(
      'Connection request username must be normalized.',
    );
  }
}

void _validateRequestId(String value) {
  if (!_requestIdPattern.hasMatch(value)) {
    throw const FormatException('Connection request id is invalid.');
  }
}

void _validateTimestampOrder({required int createdAt, required int updatedAt}) {
  if (createdAt <= 0 || updatedAt < createdAt) {
    throw const FormatException('Connection request timestamps are invalid.');
  }
}

void _validateExpiresAt({required int createdAt, required int expiresAt}) {
  if (expiresAt <= createdAt) {
    throw const FormatException(
      'Connection request expiresAt must be after createdAt.',
    );
  }
}

void _validateNonNegative(String key, int value) {
  if (value < 0) {
    throw FormatException('Connection request $key must be non-negative.');
  }
}

String _requiredString(
  Map<Object?, Object?> json,
  String key, {
  required int max,
}) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Connection request $key must be a string.');
  }
  if (value.trim().isEmpty || value.length > max) {
    throw FormatException('Connection request $key length is invalid.');
  }
  return value;
}

String? _optionalString(
  Map<Object?, Object?> json,
  String key, {
  required int max,
}) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Connection request $key must be a string.');
  }
  if (value.trim().isEmpty || value.length > max) {
    throw FormatException('Connection request $key length is invalid.');
  }
  return value;
}

int _requiredInt(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite && value.roundToDouble() == value) {
    return value.toInt();
  }
  throw FormatException('Connection request $key must be an integer.');
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
  throw FormatException('Connection request $key must be an integer.');
}

int? _terminalResponseTimestamp(Map<Object?, Object?> json) {
  return _optionalInt(json, 'respondedAt') ??
      _optionalInt(json, 'terminalAt') ??
      _optionalInt(json, 'acceptedAt') ??
      _optionalInt(json, 'rejectedAt') ??
      _optionalInt(json, 'canceledAt') ??
      _optionalInt(json, 'expiredAt') ??
      _optionalInt(json, 'failedAt');
}

bool? _optionalBool(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('Connection request $key must be a boolean.');
}
