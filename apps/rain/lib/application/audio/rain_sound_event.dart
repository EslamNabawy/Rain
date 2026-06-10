import 'package:protocol_brain/protocol_brain.dart' show CallMediaMode;

enum RainSoundEventKind {
  chatSend,
  chatReceive,
  uiAction,
  warning,
  callIncomingStarted,
  callOutgoingStarted,
  callConnected,
  callEnded,
  callFailed,
  callControlMute,
  callControlUnmute,
  callControlDeafen,
  callControlUndeafen,
  callControlCameraMute,
  callControlCameraUnmute,
  callRouteChanged,
  connectionRequestInbound,
  connectionRequestOutboundAccepted,
  connectionRequestOutboundRejected,
  connectionRequestOutboundExpired,
}

final class RainSoundEvent {
  RainSoundEvent._({
    required this.kind,
    String? conversationId,
    String? peerId,
    String? callId,
    String? connectionRequestId,
    this.sessionEpoch,
    this.mediaMode = CallMediaMode.audio,
    String? errorKey,
    this.occurredAt,
  }) : conversationId = _normalizeOptionalToken(conversationId),
       peerId = _normalizeOptionalToken(peerId),
       callId = _normalizeOptionalToken(callId),
       connectionRequestId = _normalizeOptionalToken(connectionRequestId),
       errorKey = _normalizeErrorKey(errorKey);

  factory RainSoundEvent.chatSend({
    String? conversationId,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._(
      kind: RainSoundEventKind.chatSend,
      conversationId: conversationId,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.chatReceive({
    String? conversationId,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._(
      kind: RainSoundEventKind.chatReceive,
      conversationId: conversationId,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.uiAction({DateTime? occurredAt}) {
    return RainSoundEvent._(
      kind: RainSoundEventKind.uiAction,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.warning({String? errorKey, DateTime? occurredAt}) {
    return RainSoundEvent._(
      kind: RainSoundEventKind.warning,
      errorKey: errorKey,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callIncomingStarted({
    required String callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callLifecycle(
      kind: RainSoundEventKind.callIncomingStarted,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callOutgoingStarted({
    required String callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callLifecycle(
      kind: RainSoundEventKind.callOutgoingStarted,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callConnected({
    required String callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callLifecycle(
      kind: RainSoundEventKind.callConnected,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callEnded({
    required String callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callLifecycle(
      kind: RainSoundEventKind.callEnded,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callFailed({
    required String callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    String? errorKey,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callLifecycle(
      kind: RainSoundEventKind.callFailed,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      errorKey: errorKey,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callControlMute({
    String? callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callControl(
      kind: RainSoundEventKind.callControlMute,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callControlUnmute({
    String? callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callControl(
      kind: RainSoundEventKind.callControlUnmute,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callControlDeafen({
    String? callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callControl(
      kind: RainSoundEventKind.callControlDeafen,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callControlUndeafen({
    String? callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callControl(
      kind: RainSoundEventKind.callControlUndeafen,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callControlCameraMute({
    String? callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.video,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callControl(
      kind: RainSoundEventKind.callControlCameraMute,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callControlCameraUnmute({
    String? callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.video,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callControl(
      kind: RainSoundEventKind.callControlCameraUnmute,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.callRouteChanged({
    String? callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._callControl(
      kind: RainSoundEventKind.callRouteChanged,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.connectionRequestInbound({
    required String requestId,
    String? peerId,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._connectionRequest(
      kind: RainSoundEventKind.connectionRequestInbound,
      requestId: requestId,
      peerId: peerId,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.connectionRequestOutboundAccepted({
    required String requestId,
    String? peerId,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._connectionRequest(
      kind: RainSoundEventKind.connectionRequestOutboundAccepted,
      requestId: requestId,
      peerId: peerId,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.connectionRequestOutboundRejected({
    required String requestId,
    String? peerId,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._connectionRequest(
      kind: RainSoundEventKind.connectionRequestOutboundRejected,
      requestId: requestId,
      peerId: peerId,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent.connectionRequestOutboundExpired({
    required String requestId,
    String? peerId,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._connectionRequest(
      kind: RainSoundEventKind.connectionRequestOutboundExpired,
      requestId: requestId,
      peerId: peerId,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent._callLifecycle({
    required RainSoundEventKind kind,
    required String callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    String? errorKey,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._(
      kind: kind,
      callId: _requireCallId(callId),
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      errorKey: errorKey,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent._callControl({
    required RainSoundEventKind kind,
    String? callId,
    String? peerId,
    int? sessionEpoch,
    CallMediaMode mediaMode = CallMediaMode.audio,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._(
      kind: kind,
      callId: callId,
      peerId: peerId,
      sessionEpoch: sessionEpoch,
      mediaMode: mediaMode,
      occurredAt: occurredAt,
    );
  }

  factory RainSoundEvent._connectionRequest({
    required RainSoundEventKind kind,
    required String requestId,
    String? peerId,
    DateTime? occurredAt,
  }) {
    return RainSoundEvent._(
      kind: kind,
      connectionRequestId: _requireConnectionRequestId(requestId),
      peerId: peerId,
      occurredAt: occurredAt,
    );
  }

  final RainSoundEventKind kind;
  final String? conversationId;
  final String? peerId;
  final String? callId;
  final String? connectionRequestId;
  final int? sessionEpoch;
  final CallMediaMode mediaMode;
  final String? errorKey;
  final DateTime? occurredAt;

  bool get isCallLifecycleEvent {
    return switch (kind) {
      RainSoundEventKind.callIncomingStarted ||
      RainSoundEventKind.callOutgoingStarted ||
      RainSoundEventKind.callConnected ||
      RainSoundEventKind.callEnded ||
      RainSoundEventKind.callFailed => true,
      RainSoundEventKind.chatSend ||
      RainSoundEventKind.chatReceive ||
      RainSoundEventKind.uiAction ||
      RainSoundEventKind.warning ||
      RainSoundEventKind.callControlMute ||
      RainSoundEventKind.callControlUnmute ||
      RainSoundEventKind.callControlDeafen ||
      RainSoundEventKind.callControlUndeafen ||
      RainSoundEventKind.callControlCameraMute ||
      RainSoundEventKind.callControlCameraUnmute ||
      RainSoundEventKind.callRouteChanged ||
      RainSoundEventKind.connectionRequestInbound ||
      RainSoundEventKind.connectionRequestOutboundAccepted ||
      RainSoundEventKind.connectionRequestOutboundRejected ||
      RainSoundEventKind.connectionRequestOutboundExpired => false,
    };
  }

  bool get isCallControlEvent {
    return switch (kind) {
      RainSoundEventKind.callControlMute ||
      RainSoundEventKind.callControlUnmute ||
      RainSoundEventKind.callControlDeafen ||
      RainSoundEventKind.callControlUndeafen ||
      RainSoundEventKind.callControlCameraMute ||
      RainSoundEventKind.callControlCameraUnmute ||
      RainSoundEventKind.callRouteChanged => true,
      RainSoundEventKind.chatSend ||
      RainSoundEventKind.chatReceive ||
      RainSoundEventKind.uiAction ||
      RainSoundEventKind.warning ||
      RainSoundEventKind.callIncomingStarted ||
      RainSoundEventKind.callOutgoingStarted ||
      RainSoundEventKind.callConnected ||
      RainSoundEventKind.callEnded ||
      RainSoundEventKind.callFailed ||
      RainSoundEventKind.connectionRequestInbound ||
      RainSoundEventKind.connectionRequestOutboundAccepted ||
      RainSoundEventKind.connectionRequestOutboundRejected ||
      RainSoundEventKind.connectionRequestOutboundExpired => false,
    };
  }

  bool get isConnectionRequestEvent {
    return switch (kind) {
      RainSoundEventKind.connectionRequestInbound ||
      RainSoundEventKind.connectionRequestOutboundAccepted ||
      RainSoundEventKind.connectionRequestOutboundRejected ||
      RainSoundEventKind.connectionRequestOutboundExpired => true,
      RainSoundEventKind.chatSend ||
      RainSoundEventKind.chatReceive ||
      RainSoundEventKind.uiAction ||
      RainSoundEventKind.warning ||
      RainSoundEventKind.callIncomingStarted ||
      RainSoundEventKind.callOutgoingStarted ||
      RainSoundEventKind.callConnected ||
      RainSoundEventKind.callEnded ||
      RainSoundEventKind.callFailed ||
      RainSoundEventKind.callControlMute ||
      RainSoundEventKind.callControlUnmute ||
      RainSoundEventKind.callControlDeafen ||
      RainSoundEventKind.callControlUndeafen ||
      RainSoundEventKind.callControlCameraMute ||
      RainSoundEventKind.callControlCameraUnmute ||
      RainSoundEventKind.callRouteChanged => false,
    };
  }
}

String? _normalizeOptionalToken(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

String? _normalizeErrorKey(String? value) {
  final normalized = _normalizeOptionalToken(value);
  if (normalized == null) {
    return null;
  }
  return normalized.toLowerCase();
}

String _requireCallId(String value) {
  final normalized = _normalizeOptionalToken(value);
  if (normalized == null) {
    throw ArgumentError.value(
      value,
      'callId',
      'Call sound event requires callId.',
    );
  }
  return normalized;
}

String _requireConnectionRequestId(String value) {
  final normalized = _normalizeOptionalToken(value);
  if (normalized == null) {
    throw ArgumentError.value(
      value,
      'requestId',
      'Connection request sound event requires requestId.',
    );
  }
  return normalized;
}
