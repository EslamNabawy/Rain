# CallTerminalReconciler

Last updated: 2026-06-08

## Purpose

Make Firebase terminal room state authoritative for both peers.

## Responsibilities

- Reconcile `ended`, `failed`, `expired`, `rejected`, and `busy`.
- Keep terminal failed UI state authoritative over late local session cleanup callbacks.
- Stop local media.
- Release locks.
- Ignore late hangup/markConnected frames.
- Keep cleanup idempotent.

## Current Implementation

As of 2026-06-08, `apps/rain/lib/application/runtime/voice_call/voice_call_terminal_reconciler.dart` owns the pure decision for whether a latched terminal call session state may still update UI state. Failed terminal call state ignores later `idle` or `ending` states emitted by local `session.hangUp()` cleanup, so video renderer failures and terminal Firebase failed rooms cannot be visually resurrected or collapsed to false idle before the failed result is shown.

`VoiceCallRuntime` still owns Firebase room writes, room watches, lock cleanup, and session disposal. Those paths remain future extraction work.

## Tests

- Local voice hangup ends remote.
- Remote voice hangup ends local.
- Terminal room beats late frames.
- Unknown voice call cleanup is not fatal.
- `voice_call_terminal_reconciler_test.dart` covers failed terminal state beating session idle, non-idle late states after terminal room latch, and allowed idle cleanup for non-failed terminal rooms.
- `friend_flow_test.dart --plain-name "video renderer"` covers live video renderer failure writing a terminal failed room and preserving failed UI state through cleanup.

Related: [[Call State Machine]], [[Voice Calls]], [[Video Calls]].
