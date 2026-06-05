import 'voice_signaling_contract.dart';

enum VoiceLockReclaimAction {
  keepBusy,
  reclaimLockOnly,
  reclaimLockAndDeleteRoomArtifacts,
}

final class VoiceLockReclaimDecision {
  const VoiceLockReclaimDecision._(this.action, this.reason);

  const VoiceLockReclaimDecision.keepBusy(String reason)
    : this._(VoiceLockReclaimAction.keepBusy, reason);

  const VoiceLockReclaimDecision.reclaimLockOnly(String reason)
    : this._(VoiceLockReclaimAction.reclaimLockOnly, reason);

  const VoiceLockReclaimDecision.reclaimLockAndDeleteRoomArtifacts(
    String reason,
  ) : this._(VoiceLockReclaimAction.reclaimLockAndDeleteRoomArtifacts, reason);

  final VoiceLockReclaimAction action;
  final String reason;

  bool get shouldReclaimLock => action != VoiceLockReclaimAction.keepBusy;

  bool get shouldDeleteRoomArtifacts =>
      action == VoiceLockReclaimAction.reclaimLockAndDeleteRoomArtifacts;
}

final class VoiceLockReclaimPolicy {
  const VoiceLockReclaimPolicy._();

  static const int orphanVoiceLockGraceMs = 15000;

  static VoiceLockReclaimDecision forPairLock({
    required VoiceActivePairLock lock,
    required VoiceCallRoom? room,
    required String caller,
    required String callee,
    required int createdAt,
    required int now,
  }) {
    if (!pairLockMatches(lock, caller: caller, callee: callee)) {
      return const VoiceLockReclaimDecision.keepBusy('pairMismatch');
    }
    return _forMatchingLock(
      callId: lock.callId,
      lockCaller: lock.caller,
      room: room,
      caller: caller,
      createdAt: createdAt,
      updatedAt: lock.updatedAt,
      expiresAt: lock.expiresAt,
      now: now,
    );
  }

  static VoiceLockReclaimDecision forUserLock({
    required VoiceActiveUserLock lock,
    required VoiceCallRoom? room,
    required String caller,
    required String callee,
    required int createdAt,
    required int now,
  }) {
    if (!userLockMatches(lock, caller: caller, callee: callee)) {
      return const VoiceLockReclaimDecision.keepBusy('userMismatch');
    }
    return _forMatchingLock(
      callId: lock.callId,
      lockCaller: lock.caller,
      room: room,
      caller: caller,
      createdAt: createdAt,
      updatedAt: lock.updatedAt,
      expiresAt: lock.expiresAt,
      now: now,
    );
  }

  static bool pairLockMatches(
    VoiceActivePairLock lock, {
    required String caller,
    required String callee,
  }) {
    final normalizedCaller = normalizeVoiceCallUsername(caller);
    final normalizedCallee = normalizeVoiceCallUsername(callee);
    return lock.pairId == voiceCallPairId(normalizedCaller, normalizedCallee) &&
        ((lock.caller == normalizedCaller && lock.callee == normalizedCallee) ||
            (lock.caller == normalizedCallee &&
                lock.callee == normalizedCaller));
  }

  static bool userLockMatches(
    VoiceActiveUserLock lock, {
    required String caller,
    required String callee,
  }) {
    final normalizedCaller = normalizeVoiceCallUsername(caller);
    final normalizedCallee = normalizeVoiceCallUsername(callee);
    return lock.pairId == voiceCallPairId(normalizedCaller, normalizedCallee) &&
        ((lock.caller == normalizedCaller && lock.callee == normalizedCallee) ||
            (lock.caller == normalizedCallee &&
                lock.callee == normalizedCaller));
  }

  static VoiceLockReclaimDecision _forMatchingLock({
    required String callId,
    required String lockCaller,
    required VoiceCallRoom? room,
    required String caller,
    required int createdAt,
    required int updatedAt,
    required int expiresAt,
    required int now,
  }) {
    final normalizedCaller = normalizeVoiceCallUsername(caller);

    if (room != null) {
      if (room.callId != callId) {
        return const VoiceLockReclaimDecision.keepBusy('roomCallMismatch');
      }
      if (room.status == VoiceCallSignalingStatus.connected) {
        return const VoiceLockReclaimDecision.keepBusy('connectedRoom');
      }
    }

    if (expiresAt <= createdAt || expiresAt <= now) {
      if (room != null &&
          _shouldDeleteReclaimedVoiceRoom(
            room,
            createdAt: createdAt,
            now: now,
            caller: normalizedCaller,
          )) {
        return const VoiceLockReclaimDecision.reclaimLockAndDeleteRoomArtifacts(
          'expiredLockWithCleanableRoom',
        );
      }
      return const VoiceLockReclaimDecision.reclaimLockOnly('expiredLock');
    }

    if (room == null) {
      if (lockCaller == normalizedCaller) {
        return const VoiceLockReclaimDecision.reclaimLockOnly(
          'callerOwnedMissingRoom',
        );
      }
      if (createdAt - updatedAt >= orphanVoiceLockGraceMs ||
          now - updatedAt >= orphanVoiceLockGraceMs) {
        return const VoiceLockReclaimDecision.reclaimLockOnly(
          'orphanAgedMissingRoom',
        );
      }
      return const VoiceLockReclaimDecision.keepBusy('freshMissingRoom');
    }

    if (room.isTerminal) {
      return const VoiceLockReclaimDecision.reclaimLockAndDeleteRoomArtifacts(
        'terminalRoom',
      );
    }
    if (room.status != VoiceCallSignalingStatus.connected &&
        lockCaller == normalizedCaller) {
      return const VoiceLockReclaimDecision.reclaimLockAndDeleteRoomArtifacts(
        'callerOwnedSetupRoom',
      );
    }
    if (room.status != VoiceCallSignalingStatus.connected &&
        (room.expiresAt <= createdAt || room.expiresAt <= now)) {
      return const VoiceLockReclaimDecision.reclaimLockAndDeleteRoomArtifacts(
        'expiredSetupRoom',
      );
    }
    return const VoiceLockReclaimDecision.keepBusy('liveRoom');
  }

  static bool _shouldDeleteReclaimedVoiceRoom(
    VoiceCallRoom room, {
    required int createdAt,
    required int now,
    required String caller,
  }) {
    if (room.isTerminal) {
      return true;
    }
    if (room.status != VoiceCallSignalingStatus.connected &&
        room.caller == caller) {
      return true;
    }
    return room.status != VoiceCallSignalingStatus.connected &&
        (room.expiresAt <= createdAt || room.expiresAt <= now);
  }
}
