# VoiceCallRuntime Refactor

## Current Responsibilities

Detailed implementation planning: [[VoiceCallRuntime Refactor Plan]].

- Presence preflight.
- Friend validation.
- File/call conflict checks.
- Voice/video session creation.
- Firebase room watches.
- Firebase frame encryption/decryption.
- Call lock retries and cleanup.
- Media lifecycle.
- Terminal room reconciliation.
- UI-facing state mutation.
- Diagnostics.

## Future Architecture

- [[CallStartCoordinator]] handles start eligibility and explicit phase transitions.
- [[CallLeaseManager]] owns Firebase room, inbox, user locks, pair locks, and repair.
- [[CallMediaCoordinator]] owns microphone/camera capture and WebRTC media session lifecycle.
- [[CallTerminalReconciler]] owns terminal Firebase room truth and cleanup.
- [[CallDiagnosticsRecorder]] owns event names, taxonomy, and safe diagnostics payloads.

## Migration Plan

1. Add interfaces beside current runtime.
2. Move diagnostics helpers first.
3. Move start preflight next.
4. Move lease creation/repair.
5. Move terminal reconciliation.
6. Move media coordination.
7. Reduce `VoiceCallRuntime` to orchestration.

## Rollout Strategy

- Keep old tests running.
- Add coordinator-specific tests.
- Use feature-equivalent behavior before deleting old methods.

## Test Plan

- PC-to-mobile call path simulated.
- Mobile-to-PC call path simulated.
- Stale lock repair.
- Permission denied.
- ICE candidate write failure.
- Terminal room beats late session frame.

Related: [[Architecture Stabilization Epic]], [[Target Architecture]], [[Refactoring Strategy]].
