# Refactoring Strategy

## Strategy

Use strangler refactoring. Introduce coordinators around existing behavior, move one responsibility at a time, and keep regression tests passing.

The detailed Phase 7 planning entrypoint is [[Architecture Refactor Plan Index]].

## Order

1. Extract diagnostics recording into [[CallDiagnosticsRecorder]].
2. Extract presence/start preflight into [[CallStartCoordinator]].
3. Extract Firebase room/lock behavior into [[CallLeaseManager]].
4. Extract media setup/reconnect into [[CallMediaCoordinator]].
5. Extract terminal-room reconciliation into [[CallTerminalReconciler]].
6. Delete dead paths from `VoiceCallRuntime`.

## Safety Rules

- No media/signaling rewrite in the same task as UI polish.
- Every extracted coordinator gets contract tests.
- Keep old behavior covered before deleting old code.

Related: [[VoiceCallRuntime Refactor]], [[Test Strategy]], [[Technical Debt Register]].

## Detailed Plans

- [[VoiceCallRuntime Refactor Plan]]
- [[Firebase Lease Management Refactor Plan]]
- [[Presence Management Refactor Plan]]
- [[Message Loading Refactor Plan]]
- [[File Transfer Runtime Refactor Plan]]
