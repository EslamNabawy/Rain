const int maxCallCleanupItemsPerRun = 25;

enum VoiceCallCleanupAction {
  none,
  deleteExpiredRoom,
  deleteTerminalRoom,
  deleteCorruptRoom,
  deleteMatchingPairLock,
  deleteMatchingUserLock,
  deleteCorruptInbox,
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
