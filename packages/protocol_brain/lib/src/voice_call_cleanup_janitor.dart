import 'voice_signaling_contract.dart';

const int maxCallCleanupItemsPerRun = 25;

enum VoiceCallCleanupAction {
  none,
  deleteExpiredRoom,
  deleteExpiredConnectedRoom,
  deleteTerminalRoom,
  deleteCorruptRoom,
  deleteMatchingPairLock,
  deleteMatchingUserLock,
  deleteCorruptInbox,
}

/// What the janitor should do with the room referenced by a stale lock.
enum VoiceCallRoomCleanupVerdict {
  keep,
  missingRoom,
  terminal,
  expiredSetup,
  expiredConnected,
}

/// Pure decision for one room found through the signed-in user's lock.
///
/// [liveCallId] is the call the local runtime is currently in; that call must
/// never be cleaned up, even when its room has passed `expiresAt` (voice call
/// rooms expire after two minutes and are not refreshed while connected).
VoiceCallRoomCleanupVerdict decideVoiceCallRoomCleanup({
  required VoiceCallRoom? room,
  required int now,
  String? liveCallId,
}) {
  if (room == null) {
    return VoiceCallRoomCleanupVerdict.missingRoom;
  }
  if (room.isTerminal) {
    return VoiceCallRoomCleanupVerdict.terminal;
  }
  if (liveCallId != null && room.callId == liveCallId) {
    return VoiceCallRoomCleanupVerdict.keep;
  }
  if (room.expiresAt > now) {
    return VoiceCallRoomCleanupVerdict.keep;
  }
  return room.status == VoiceCallSignalingStatus.connected
      ? VoiceCallRoomCleanupVerdict.expiredConnected
      : VoiceCallRoomCleanupVerdict.expiredSetup;
}

final class VoiceCallCleanupDecision {
  const VoiceCallCleanupDecision({
    required this.action,
    required this.callId,
    required this.reason,
    this.path,
  });

  final VoiceCallCleanupAction action;
  final String callId;
  final String reason;
  final String? path;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'action': action.name,
      'callId': callId,
      'reason': reason,
      if (path != null) 'path': path,
    };
  }
}

final class VoiceCallCleanupSummary {
  const VoiceCallCleanupSummary({
    required this.username,
    required this.now,
    required this.decisions,
  });

  final String username;
  final int now;
  final List<VoiceCallCleanupDecision> decisions;

  bool get cleanedAny => decisions.any(
    (decision) => decision.action != VoiceCallCleanupAction.none,
  );

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'username': username,
      'now': now,
      'cleanedAny': cleanedAny,
      'decisionCount': decisions.length,
      'decisions': decisions.map((decision) => decision.toJson()).toList(),
    };
  }
}
