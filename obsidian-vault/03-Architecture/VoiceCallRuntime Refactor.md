# VoiceCallRuntime Refactor

Last updated: 2026-06-08

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

2026-06-08 Phase 3a state/room coordinator layout slice:

- Extracted voice-call coordinator files are grouped under `apps/rain/lib/application/runtime/voice_call/`.
- `VoiceCallRoomCoordinator` owns room status transition recording, terminal room detail/failure mapping, reason-code mapping, and terminal room write error classification.
- `VoiceCallErrorCoordinator` owns app-runtime delegation to `CallErrorClassifier`.
- `VoiceCallStateCoordinator` owns pure start-block expiry checks, protocol session phase/detail/failure mapping, remote media permission mapping, terminal-write failure state, same-live-session guards, and local-end terminal state reset.
- `VoiceCallDiagnostics` and `VoiceCallTerminalReconciler` live beside the other voice-call coordinators in the same folder.
- `VoiceCallRuntime` still owns command orchestration, Firebase room watch/reconciliation, lock coordination, media/session orchestration, and cleanup.

2026-06-08 Phase 3b preflight/reconnect coordinator slice:

- `VoiceCallPreflightCoordinator` owns peer-connection availability assertions, accepted-friend validation with one relationship sync, backend presence fetch conversion into call-start guards, and stale retry replacement cleanup.
- `VoiceCallReconnectCoordinator` owns live peer failure mutation, reconnecting-state mutation, session reconnect markers, and reconnect grace timer arming/cancel guards.
- Both coordinators are stateless; `VoiceCallRuntime` passes mutable state, timers, sessions, and side-effect callbacks at the delegation boundary.
- `VoiceCallRuntime` still owns command orchestration, Firebase room watch/reconciliation, lock coordination, media/session orchestration, terminal cleanup, and full call-start conflict policy.

2026-06-08 Phase 3c media/session/signaling coordinator slice:

- `VoiceCallMediaCoordinator` owns app-side audio/video media connection creation, video renderer state/failure handling, app lifecycle video failure handling, camera-muted signaling, and video renderer/resource cleanup.
- `VoiceCallSessionStateCoordinator` owns protocol-session-to-runtime state projection, failed-session finalization, runtime/session/start failure diagnostics, diagnostics payload construction, and peer UI split diagnostics.
- `VoiceCallSignalingCleanupCoordinator` owns Firebase voice room watch setup, room/envelope/frame handling, terminal-sensitive send preflight, ICE candidate queue/batch/write diagnostics, stale artifact cleanup, signaling subscription cancellation, terminal room writes, bounded cleanup, room status timelines, and terminal-already-closed classification.
- These coordinators remain stateless; `VoiceCallRuntime` passes maps, sessions, subscriptions, timers, diagnostics callbacks, and signaling/media side effects through narrow method parameters.
- `voice_call_runtime.dart` is now 2,917 lines. `VoiceCallRuntime` still owns public command orchestration, call/file conflict policy, lock/lease orchestration, and some local end-state sequencing.

## Future Architecture

- [[CallStartCoordinator]] handles start eligibility and explicit phase transitions.
- [[CallLeaseManager]] owns Firebase room, inbox, user locks, pair locks, and repair.
- [[CallMediaCoordinator]] owns microphone/camera capture and WebRTC media session lifecycle.
- [[CallTerminalReconciler]] owns terminal Firebase room truth and cleanup.
- [[CallDiagnosticsRecorder]] owns event names, taxonomy, and safe diagnostics payloads.

## Migration Plan

1. Add interfaces beside current runtime.
2. Move diagnostics and pure error-classification helpers first. Status: partial complete through `CallErrorClassifier`.
3. Move start preflight next. Status: partial complete for pure local start-block expiry mapping through `VoiceCallStateCoordinator` and friend/presence availability plus stale retry replacement through `VoiceCallPreflightCoordinator`; file/call conflict policy and command orchestration remain in `VoiceCallRuntime`.
4. Move lease creation/repair.
5. Move terminal reconciliation. Status: pure terminal session-state decision extracted to `VoiceCallTerminalReconciler`; Phase 3c also moved terminal room writes, room status timelines, terminal-already-closed classification, and bounded cleanup helpers to `VoiceCallSignalingCleanupCoordinator`; lock/lease ownership remains.
6. Move media coordination. Status: partial complete for app-side media adapters, renderer-failure target classification, media connection creation, renderer lifecycle, app lifecycle video failure handling, camera mute signaling, and video resource cleanup; command-level media start/end orchestration remains.
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

2026-06-08 Phase 3a focused/local evidence:

- `dart analyze` passed from `apps\rain`.
- `flutter test test\voice_call_state_coordinator_test.dart test\voice_call_room_coordinator_test.dart test\voice_call_terminal_reconciler_test.dart --reporter expanded` passed from `apps\rain`.
- `dart pub get` passed.
- `dart run melos run analyze` passed.
- `dart run melos run test` passed.

2026-06-08 Phase 3b focused/local evidence:

- `dart analyze lib\application\runtime\voice_call_runtime.dart lib\application\runtime\rain_runtime_controller.dart lib\application\runtime\voice_call\voice_call_reconnect_coordinator.dart lib\application\runtime\voice_call\voice_call_preflight_coordinator.dart test\voice_call_reconnect_coordinator_test.dart test\voice_call_preflight_coordinator_test.dart` passed from `apps\rain`.
- `flutter test test\voice_call_reconnect_coordinator_test.dart test\voice_call_preflight_coordinator_test.dart test\voice_call_state_coordinator_test.dart test\voice_call_room_coordinator_test.dart test\voice_call_terminal_reconciler_test.dart --reporter expanded` passed from `apps\rain`.

2026-06-08 Phase 3c focused/local evidence:

- `dart analyze` passed.
- `flutter test apps/rain/test/voice_call_runtime_diagnostics_contract_test.dart apps/rain/test/voice_call_runtime_media_path_test.dart` passed.
- `dart run melos run test` passed.
- `.\scripts\check_obsidian_vault.ps1` passed.
- `voice_call_runtime.dart` line count is 2,917.

Related: [[Architecture Stabilization Epic]], [[Target Architecture]], [[Refactoring Strategy]].
