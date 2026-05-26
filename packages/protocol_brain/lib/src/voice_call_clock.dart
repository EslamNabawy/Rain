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
