/// # media_interruption.dart
///
/// Defines media interruption types and events for handling audio focus loss, permission revocation, camera disconnection, and app lifecycle changes during calls.
///
/// **Key types:** MediaInterruptionType, MediaInterruptionEvent
///
/// **Depends on:** none (dart:core only)
library;

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
