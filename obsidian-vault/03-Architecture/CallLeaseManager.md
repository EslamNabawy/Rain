# CallLeaseManager

## Purpose

Own Firebase call rooms, inboxes, user locks, pair locks, stale lock repair, and terminal cleanup.

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

Related: [[Lease Management]], [[Firebase Architecture]], [[Signaling Reliability Epic]].
