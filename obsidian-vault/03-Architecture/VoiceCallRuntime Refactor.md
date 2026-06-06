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

## Current Extracted Boundaries

2026-06-05 Phase 3 first slice:

- `CallErrorClassifier` owns voice call failure reason codes, user-facing call failure messages, retry/failure taxonomy, Firebase signaling error snapshot classification, busy user extraction, and local audio/video permission failure classification.
- `call_media_session_coordinator.dart` owns the app-side `CallVoiceMediaConnection`, `VideoVoiceMediaConnection`, `VideoCallRendererException`, and media diagnostics mapping used by voice/video call runtime setup.
- `VoiceCallTerminalReconciler` owns the pure policy for late session states after terminal room latching, including the rule that a failed terminal state cannot be overwritten by local session `idle` emitted during cleanup.
- `VoiceCallRuntime` still owns command orchestration, room watches, room reconciliation, lock coordination, most state mutation, and terminal cleanup. Those responsibilities remain the next extraction targets.
- `RainRuntimeController` public call behavior stayed stable for this slice.

2026-06-06 Phase 3 combined slice:

- Peer UI status now flows through a unified `ConnectionDiagnostics` projection and `peerConnectionDiagnosticsProvider`.
- Projection precedence is explicit: failed/terminal call or session state, manual disconnect, recovering/reconnecting, superseded/out-of-sync, connected, data-lane-only/stale, then ready/offline.
- Stale presence plus an open data lane is no longer visually connected; it is `Data lane only` while `canSendData` can remain true.
- Video renderer failures are authoritative for live video calls. Local renderer failure throws/fails start; remote renderer failure writes terminal failed Firebase room state and keeps failed UI state through cleanup.
- Renderer errors after no current live video call are warning diagnostics named `stale_renderer_callback_ignored`.
- Split call/data-session truth records `peer_ui_state_split_detected`.

## Future Architecture

- [[CallStartCoordinator]] handles start eligibility and explicit phase transitions.
- [[CallLeaseManager]] owns Firebase room, inbox, user locks, pair locks, and repair.
- [[CallMediaCoordinator]] owns microphone/camera capture and WebRTC media session lifecycle.
- [[CallTerminalReconciler]] owns terminal Firebase room truth and cleanup.
- [[CallDiagnosticsRecorder]] owns event names, taxonomy, and safe diagnostics payloads.

## Migration Plan

1. Add interfaces beside current runtime.
2. Move diagnostics and pure error-classification helpers first. Status: partial complete through `CallErrorClassifier`.
3. Move start preflight next.
4. Move lease creation/repair.
5. Move terminal reconciliation. Status: pure terminal session-state decision extracted to `VoiceCallTerminalReconciler`; room watch/write orchestration remains in `VoiceCallRuntime`.
6. Move media coordination. Status: partial complete for app-side media adapters and renderer-failure target classification; full session orchestration remains.
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

## Validation Evidence

2026-06-05 first slice:

- `flutter test test\call_error_classifier_test.dart --reporter expanded` passed from `apps/rain`.
- `flutter test test\voice_call_runtime_media_path_test.dart test\voice_call_runtime_diagnostics_contract_test.dart --reporter expanded` passed from `apps/rain`.
- `flutter test test\rain_call_failure_messages_test.dart --reporter expanded` passed from `apps/rain`.
- `dart run melos run analyze` passed.
- `dart run melos run test` passed.

2026-06-06 combined slice focused evidence:

- `flutter test test\connection_diagnostics_test.dart test\chat_panel_connectivity_test.dart test\voice_call_terminal_reconciler_test.dart --reporter expanded` passed from `apps\rain`.
- `flutter test test\friend_flow_test.dart --plain-name "video renderer" --reporter expanded` passed from `apps\rain`.
- `dart pub get` passed.
- `dart run melos run analyze` passed.
- `dart run melos run test` passed.
- `.\scripts\check_obsidian_vault.ps1` passed.

Related: [[Architecture Stabilization Epic]], [[Target Architecture]], [[Refactoring Strategy]].
