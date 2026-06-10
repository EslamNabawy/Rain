import 'package:protocol_brain/protocol_brain.dart';

ConnectionRequestSurfaceModel buildConnectionRequestSurfaceModel({
  required ConnectionRequestPayload payload,
  required ConnectionRequestDirection direction,
  ConnectionRequestQuotaSnapshot? quota,
  ConnectionRequestFeedbackModel? feedback,
}) {
  final peerId = direction == ConnectionRequestDirection.inbound
      ? payload.from
      : payload.to;
  final peerLabel = _peerLabel(peerId);
  return ConnectionRequestSurfaceModel(
    requestId: payload.requestId,
    peerId: peerId,
    peerLabel: peerLabel,
    direction: direction,
    status: payload.status,
    title: _titleFor(payload.status, direction, peerLabel),
    subtitle: _subtitleFor(payload.status, direction, peerLabel),
    actions: _actionsFor(payload.status, direction, peerLabel),
    feedback: feedback,
    quota: quota,
  );
}

ConnectionRequestFeedbackModel? buildConnectionRequestFeedback({
  required ConnectionRequestDecision decision,
}) {
  final reasonCode = decision.reasonCode;
  if (reasonCode == null || decision.userMessage.trim().isEmpty) {
    return null;
  }
  return ConnectionRequestFeedbackModel(
    reasonCode: reasonCode,
    message: decision.userMessage,
    retryAfter: decision.retryAfterMs == null
        ? null
        : Duration(milliseconds: decision.retryAfterMs!),
  );
}

ConnectionRequestDecision deniedConnectionRequestDecision({
  required ConnectionRequestReasonCode reasonCode,
  required String peerId,
  String? requestId,
  String? userMessage,
  String? blockingPeerId,
  int? retryAfterMs,
  Map<String, Object?> diagnostics = const <String, Object?>{},
}) {
  final normalizedPeerId = peerId.trim().replaceFirst(RegExp(r'^@+'), '');
  return ConnectionRequestDecision(
    allowed: false,
    reasonCode: reasonCode,
    userMessage:
        userMessage ??
        messageForConnectionRequestReason(
          reasonCode,
          normalizedPeerId,
          retryAfterMs == null ? null : Duration(milliseconds: retryAfterMs),
        ),
    requestId: requestId,
    peerId: normalizedPeerId.isEmpty ? null : normalizedPeerId,
    blockingPeerId: blockingPeerId,
    retryAfterMs: retryAfterMs,
    diagnostics: diagnostics,
  );
}

String _peerLabel(String peerId) {
  final normalized = peerId.trim().replaceFirst(RegExp(r'^@+'), '');
  return normalized.isEmpty ? 'Peer' : '@$normalized';
}

String _titleFor(
  ConnectionRequestStatus status,
  ConnectionRequestDirection direction,
  String peerLabel,
) {
  return switch ((direction, status)) {
    (ConnectionRequestDirection.inbound, ConnectionRequestStatus.pending) ||
    (
      ConnectionRequestDirection.inbound,
      ConnectionRequestStatus.seen,
    ) => '$peerLabel wants to connect',
    (ConnectionRequestDirection.outbound, ConnectionRequestStatus.pending) ||
    (
      ConnectionRequestDirection.outbound,
      ConnectionRequestStatus.seen,
    ) => 'Connection request pending',
    (_, ConnectionRequestStatus.accepted) => 'Connection request accepted',
    (_, ConnectionRequestStatus.rejected) => 'Connection request declined',
    (_, ConnectionRequestStatus.canceled) => 'Connection request canceled',
    (_, ConnectionRequestStatus.expired) => 'Connection request expired',
    (_, ConnectionRequestStatus.failed) => 'Connection request failed',
  };
}

String _subtitleFor(
  ConnectionRequestStatus status,
  ConnectionRequestDirection direction,
  String peerLabel,
) {
  return switch ((direction, status)) {
    (ConnectionRequestDirection.inbound, ConnectionRequestStatus.pending) ||
    (ConnectionRequestDirection.inbound, ConnectionRequestStatus.seen) =>
      'Accept to open the peer lane. Ignore keeps your current connection state unchanged.',
    (ConnectionRequestDirection.outbound, ConnectionRequestStatus.pending) =>
      'Waiting for $peerLabel to accept.',
    (ConnectionRequestDirection.outbound, ConnectionRequestStatus.seen) =>
      '$peerLabel has seen your request.',
    (_, ConnectionRequestStatus.accepted) => 'The peer lane can be opened now.',
    (_, ConnectionRequestStatus.rejected) => '$peerLabel declined the request.',
    (_, ConnectionRequestStatus.canceled) => 'This request was canceled.',
    (_, ConnectionRequestStatus.expired) => 'Send a new request if needed.',
    (_, ConnectionRequestStatus.failed) =>
      'The request could not be completed.',
  };
}

List<ConnectionRequestActionModel> _actionsFor(
  ConnectionRequestStatus status,
  ConnectionRequestDirection direction,
  String peerLabel,
) {
  if (status.isTerminal) {
    return <ConnectionRequestActionModel>[
      const ConnectionRequestActionModel(
        kind: ConnectionRequestActionKind.dismiss,
        label: 'Dismiss',
        semanticLabel: 'Dismiss connection request status',
        enabled: true,
      ),
    ];
  }
  if (direction == ConnectionRequestDirection.outbound) {
    return <ConnectionRequestActionModel>[
      ConnectionRequestActionModel(
        kind: ConnectionRequestActionKind.cancel,
        label: 'Cancel',
        semanticLabel: 'Cancel connection request to $peerLabel',
        enabled: true,
      ),
    ];
  }
  return <ConnectionRequestActionModel>[
    ConnectionRequestActionModel(
      kind: ConnectionRequestActionKind.connect,
      label: 'Connect',
      semanticLabel: 'Accept connection request from $peerLabel',
      enabled: true,
    ),
    ConnectionRequestActionModel(
      kind: ConnectionRequestActionKind.ignore,
      label: 'Ignore',
      semanticLabel: 'Ignore connection request from $peerLabel',
      enabled: true,
    ),
    ConnectionRequestActionModel(
      kind: ConnectionRequestActionKind.reject,
      label: 'Decline',
      semanticLabel: 'Decline connection request from $peerLabel',
      enabled: true,
    ),
    ConnectionRequestActionModel(
      kind: ConnectionRequestActionKind.mute,
      label: 'Mute',
      semanticLabel: 'Mute connection requests from $peerLabel',
      enabled: true,
      tooltip: 'Hide future connection request prompts from this peer.',
    ),
  ];
}
