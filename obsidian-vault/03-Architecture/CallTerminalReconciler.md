# CallTerminalReconciler

## Purpose

Make Firebase terminal room state authoritative for both peers.

## Responsibilities

- Reconcile `ended`, `failed`, `expired`, `rejected`, and `busy`.
- Stop local media.
- Release locks.
- Ignore late hangup/markConnected frames.
- Keep cleanup idempotent.

## Tests

- Local voice hangup ends remote.
- Remote voice hangup ends local.
- Terminal room beats late frames.
- Unknown voice call cleanup is not fatal.

Related: [[Call State Machine]], [[Voice Calls]], [[Video Calls]].
