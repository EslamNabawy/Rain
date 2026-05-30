enum MediaInterruptionType {
  audioFocusLost,
  audioFocusRestored,
  routeChanged,
  microphonePermissionRevoked,
  cameraPermissionRevoked,
  cameraDisconnected,
  appPaused,
  appResumed,
}

final class MediaInterruptionEvent {
  const MediaInterruptionEvent({
    required this.type,
    required this.occurredAt,
    this.detail,
  });

  final MediaInterruptionType type;
  final DateTime occurredAt;
  final String? detail;
}
