# Lease Management

## Problem

Current call setup claims caller user lock, callee user lock, pair lock, then room/inbox. This can create partial state.

## Target

Use [[CallLeaseManager]] to own:

- claim
- repair
- retry
- cleanup
- terminal release

## Rules

- Offline beats busy.
- Expired/missing/terminal/corrupt lock can be repaired.
- Live non-terminal room returns true busy.
- Never delete a newer lock.
- Phase 2 proof on 2026-06-05 validated that malformed lock writes are rejected, denied writes preserve live locks/rooms/inboxes, terminal leftover locks can be reclaimed before reverse calls, and voice lock transactions are server-authoritative.

Related: [[Signaling Reliability Epic]], [[Rules Strategy]], [[Emulator Coverage]].
