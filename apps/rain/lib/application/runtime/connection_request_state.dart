import 'package:protocol_brain/protocol_brain.dart';

final class ConnectionRequestUserMessage {
  const ConnectionRequestUserMessage({
    required this.message,
    required this.createdAt,
    this.reasonCode,
    this.requestId,
    this.peerId,
  });

  final String message;
  final DateTime createdAt;
  final ConnectionRequestReasonCode? reasonCode;
  final String? requestId;
  final String? peerId;
}

final class ConnectionRequestState {
  const ConnectionRequestState({
    required this.available,
    required this.incomingRequests,
    required this.outgoingRequests,
    required this.incomingSurfaces,
    required this.outgoingSurfaces,
    required this.updatedAt,
    this.quota,
    this.lastUserMessage,
  });

  const ConnectionRequestState.idle()
    : available = false,
      incomingRequests = const <ConnectionRequestPayload>[],
      outgoingRequests = const <ConnectionRequestPayload>[],
      incomingSurfaces = const <ConnectionRequestSurfaceModel>[],
      outgoingSurfaces = const <ConnectionRequestSurfaceModel>[],
      quota = null,
      lastUserMessage = null,
      updatedAt = null;

  final bool available;
  final List<ConnectionRequestPayload> incomingRequests;
  final List<ConnectionRequestPayload> outgoingRequests;
  final List<ConnectionRequestSurfaceModel> incomingSurfaces;
  final List<ConnectionRequestSurfaceModel> outgoingSurfaces;
  final ConnectionRequestQuotaSnapshot? quota;
  final ConnectionRequestUserMessage? lastUserMessage;
  final DateTime? updatedAt;

  bool get hasPendingIncoming => incomingRequests.any(
    (ConnectionRequestPayload request) => !request.status.isTerminal,
  );

  bool get hasPendingOutgoing => outgoingRequests.any(
    (ConnectionRequestPayload request) => !request.status.isTerminal,
  );

  ConnectionRequestPayload? incomingById(String requestId) {
    return _firstWhereOrNull(
      incomingRequests,
      (ConnectionRequestPayload request) => request.requestId == requestId,
    );
  }

  ConnectionRequestPayload? outgoingById(String requestId) {
    return _firstWhereOrNull(
      outgoingRequests,
      (ConnectionRequestPayload request) => request.requestId == requestId,
    );
  }

  ConnectionRequestState copyWith({
    bool? available,
    List<ConnectionRequestPayload>? incomingRequests,
    List<ConnectionRequestPayload>? outgoingRequests,
    List<ConnectionRequestSurfaceModel>? incomingSurfaces,
    List<ConnectionRequestSurfaceModel>? outgoingSurfaces,
    ConnectionRequestQuotaSnapshot? quota,
    ConnectionRequestUserMessage? lastUserMessage,
    DateTime? updatedAt,
    bool clearQuota = false,
    bool clearLastUserMessage = false,
  }) {
    return ConnectionRequestState(
      available: available ?? this.available,
      incomingRequests: incomingRequests ?? this.incomingRequests,
      outgoingRequests: outgoingRequests ?? this.outgoingRequests,
      incomingSurfaces: incomingSurfaces ?? this.incomingSurfaces,
      outgoingSurfaces: outgoingSurfaces ?? this.outgoingSurfaces,
      quota: clearQuota ? null : quota ?? this.quota,
      lastUserMessage: clearLastUserMessage
          ? null
          : lastUserMessage ?? this.lastUserMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) {
      return value;
    }
  }
  return null;
}
