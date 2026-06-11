/// # voice_lock_reclaim_policy_test.dart — protocol_brain package
///
/// Tests for VoiceLockReclaimPolicy verifying lock reclamation decisions for terminal rooms, missing rooms, and orphan-aged artifacts.
///
/// **Key types:** (no top-level types — test-only file)
///
/// **Package:** protocol_brain
///
/// **Depends on:** flutter_test, protocol_brain, voice_lock_reclaim_policy
///
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:protocol_brain/src/voice_lock_reclaim_policy.dart';

void main() {
  group('VoiceLockReclaimPolicy', () {
    test('reclaims terminal rooms and deletes old artifacts', () {
      final decision = VoiceLockReclaimPolicy.forPairLock(
        lock: _pairLock(),
        room: _room(status: VoiceCallSignalingStatus.failed),
        caller: 'alice',
        callee: 'bob',
        createdAt: 2000,
        now: 2000,
      );

      expect(
        decision.action,
        VoiceLockReclaimAction.reclaimLockAndDeleteRoomArtifacts,
      );
    });

    test('reclaims caller-owned missing rooms without deleting artifacts', () {
      final decision = VoiceLockReclaimPolicy.forPairLock(
        lock: _pairLock(updatedAt: 1999),
        room: null,
        caller: 'alice',
        callee: 'bob',
        createdAt: 2000,
        now: 2000,
      );

      expect(decision.action, VoiceLockReclaimAction.reclaimLockOnly);
    });

    test('reclaims orphan-aged missing rooms', () {
      final decision = VoiceLockReclaimPolicy.forPairLock(
        lock: _pairLock(caller: 'bob', callee: 'alice', updatedAt: 1000),
        room: null,
        caller: 'alice',
        callee: 'bob',
        createdAt: 20000,
        now: 20000,
      );

      expect(decision.action, VoiceLockReclaimAction.reclaimLockOnly);
    });

    test('reclaims caller-owned setup rooms', () {
      final decision = VoiceLockReclaimPolicy.forPairLock(
        lock: _pairLock(),
        room: _room(status: VoiceCallSignalingStatus.ringing),
        caller: 'alice',
        callee: 'bob',
        createdAt: 2000,
        now: 2000,
      );

      expect(
        decision.action,
        VoiceLockReclaimAction.reclaimLockAndDeleteRoomArtifacts,
      );
    });

    test('reclaims expired setup rooms owned by the other participant', () {
      final decision = VoiceLockReclaimPolicy.forPairLock(
        lock: _pairLock(caller: 'bob', callee: 'alice'),
        room: _room(
          callId: 'call-1',
          caller: 'bob',
          callee: 'alice',
          status: VoiceCallSignalingStatus.accepted,
          expiresAt: 1900,
        ),
        caller: 'alice',
        callee: 'bob',
        createdAt: 2000,
        now: 2000,
      );

      expect(
        decision.action,
        VoiceLockReclaimAction.reclaimLockAndDeleteRoomArtifacts,
      );
    });

    test('does not reclaim live connected rooms even when lock is expired', () {
      final decision = VoiceLockReclaimPolicy.forPairLock(
        lock: _pairLock(expiresAt: 1900),
        room: _room(
          status: VoiceCallSignalingStatus.connected,
          expiresAt: 1900,
        ),
        caller: 'alice',
        callee: 'bob',
        createdAt: 2000,
        now: 2000,
      );

      expect(decision.action, VoiceLockReclaimAction.keepBusy);
    });

    test(
      'does not reclaim fresh setup rooms owned by the other participant',
      () {
        final decision = VoiceLockReclaimPolicy.forPairLock(
          lock: _pairLock(caller: 'bob', callee: 'alice'),
          room: _room(
            caller: 'bob',
            callee: 'alice',
            status: VoiceCallSignalingStatus.ringing,
          ),
          caller: 'alice',
          callee: 'bob',
          createdAt: 2000,
          now: 2000,
        );

        expect(decision.action, VoiceLockReclaimAction.keepBusy);
      },
    );

    test('does not reclaim user locks for a different participant pair', () {
      final decision = VoiceLockReclaimPolicy.forUserLock(
        lock: _userLock(
          username: 'alice',
          caller: 'alice',
          callee: 'cara',
          pairId: voiceCallPairId('alice', 'cara'),
        ),
        room: null,
        caller: 'alice',
        callee: 'bob',
        createdAt: 20000,
        now: 20000,
      );

      expect(decision.action, VoiceLockReclaimAction.keepBusy);
    });

    test('does not reclaim when lock and room call ids differ', () {
      final decision = VoiceLockReclaimPolicy.forPairLock(
        lock: _pairLock(callId: 'call-1'),
        room: _room(callId: 'call-2', status: VoiceCallSignalingStatus.failed),
        caller: 'alice',
        callee: 'bob',
        createdAt: 2000,
        now: 2000,
      );

      expect(decision.action, VoiceLockReclaimAction.keepBusy);
    });
  });
}

VoiceActivePairLock _pairLock({
  String callId = 'call-1',
  String caller = 'alice',
  String callee = 'bob',
  int createdAt = 1000,
  int updatedAt = 1000,
  int expiresAt = 60000,
}) {
  return VoiceActivePairLock(
    pairId: voiceCallPairId(caller, callee),
    callId: callId,
    caller: caller,
    callee: callee,
    createdAt: createdAt,
    updatedAt: updatedAt,
    expiresAt: expiresAt,
  );
}

VoiceActiveUserLock _userLock({
  String username = 'alice',
  String callId = 'call-1',
  String pairId = 'alice:bob',
  String caller = 'alice',
  String callee = 'bob',
  int createdAt = 1000,
  int updatedAt = 1000,
  int expiresAt = 60000,
}) {
  return VoiceActiveUserLock(
    username: username,
    callId: callId,
    pairId: pairId,
    caller: caller,
    callee: callee,
    createdAt: createdAt,
    updatedAt: updatedAt,
    expiresAt: expiresAt,
  );
}

VoiceCallRoom _room({
  String callId = 'call-1',
  String caller = 'alice',
  String callee = 'bob',
  VoiceCallSignalingStatus status = VoiceCallSignalingStatus.ringing,
  int createdAt = 1000,
  int updatedAt = 1000,
  int expiresAt = 60000,
}) {
  return VoiceCallRoom(
    v: VoiceCallRoom.version,
    callId: callId,
    pairId: voiceCallPairId(caller, callee),
    caller: caller,
    callee: callee,
    status: status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    expiresAt: expiresAt,
    connectedAt: status == VoiceCallSignalingStatus.connected
        ? updatedAt
        : null,
  );
}
