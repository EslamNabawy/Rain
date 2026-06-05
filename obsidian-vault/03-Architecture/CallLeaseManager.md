# CallLeaseManager

## Purpose

Own Firebase call rooms, inboxes, user locks, pair locks, stale lock repair, and terminal cleanup.

Detailed implementation planning: [[Firebase Lease Management Refactor Plan]].

## Responsibilities

- Claim call lease.
- Repair stale/corrupt/missing/terminal locks.
- Write room and inbox.
- Release locks only when call id matches.
- Expose typed lease diagnostics.

## Key Problem

Current call setup claims multiple locks sequentially. This can leave partial state after network/rules failures.

## Target Behavior

- Offline wins over busy.
- Stale locks are repaired and retried once.
- Live non-terminal room returns real busy.
- Permission denied is classified as rules/signaling failure.

## Current Implementation Notes

- 2026-06-05: `packages/protocol_brain/lib/src/voice_lock_reclaim_policy.dart` is the shared reclaim decision point for Firebase and fake voice signaling.
- Firebase create-call lock claims now treat any existing lock as a policy decision, compare-delete only matching pair/user locks, retry the claim once after cleanup, and surface "old call state was cleaned" when cleanup succeeded but a newer lock wins.
- Reclaimable states: expired locks, caller-owned or orphan-aged missing rooms, terminal rooms, caller-owned setup rooms, and expired setup rooms.
- Protected states: live `connected` rooms, fresh other-owned setup rooms, mismatched caller/callee pairs, and lock/room call-id mismatches.
- Remaining gap: emulator/live Firebase proof for the same stale, live, and newer-lock cases.

Related: [[Lease Management]], [[Firebase Architecture]], [[Signaling Reliability Epic]].
