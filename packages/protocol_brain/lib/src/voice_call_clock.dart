/// # voice_call_clock.dart — protocol_brain package
///
/// Pure utility for monotonic timestamp generation in voice call signaling. Ensures timestamps are strictly increasing relative to room creation/update times, preventing ordering conflicts in Firebase RTDB.
///
/// **Key types:** VoiceCallTimestampClock
///
/// **Package:** protocol_brain
///
/// **Depends on:** None (standalone pure class)
final class VoiceCallTimestampClock {
  const VoiceCallTimestampClock._();

  static int nextInitialTimestamp(int requestedAt) {
    if (requestedAt > 0) {
      return requestedAt;
    }
    return 1;
  }

  static int nextRoomTimestamp({
    required int requestedAt,
    required int roomCreatedAt,
    required int roomUpdatedAt,
  }) {
    final floor = roomUpdatedAt >= roomCreatedAt
        ? roomUpdatedAt
        : roomCreatedAt;
    if (requestedAt > floor) {
      return requestedAt;
    }
    return floor + 1;
  }

  static int nextExpiry({
    required int createdAt,
    required int requestedExpiresAt,
  }) {
    if (requestedExpiresAt > createdAt) {
      return requestedExpiresAt;
    }
    return createdAt + const Duration(minutes: 15).inMilliseconds;
  }
}
