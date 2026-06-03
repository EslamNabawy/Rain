# Test Strategy

## Production Test Strategy

1. Unit tests for pure state and protocol logic.
2. Widget tests for UI layout and safe area.
3. Runtime tests with fakes for call/file/connection.
4. Firebase emulator tests for rules and signaling contracts.
5. Release artifact smoke tests.
6. Manual Android/Windows WebRTC smoke checks.

Related: [[Coverage Dashboard]], [[Emulator Test Matrix]], [[Production Validation Epic]].

## Regression Expansion - 2026-06-03

Phase 08 added low-dependency regression tests around the current RCA failure cluster:

- `apps/rain/test/rain_call_failure_messages_test.dart` locks stable user-facing messages for WebRTC transceiver/SDP native failures, Firebase permission-denied setup failures, and network-loss terminal failures.
- `apps/rain/test/rain_call_suite_models_test.dart` now covers failed outgoing video state, failed incoming network-loss dismissal, and narrow-phone video dock overflow so compact controls keep mic/camera/hangup visible.
- `apps/rain/test/voice_call_runtime_diagnostics_contract_test.dart` now locks terminal-room-before-session-hangup ordering, failed-media terminal write before session disposal, and already-terminal Firebase cleanup classification.
- `packages/protocol_brain/test/firebase_contract_test.dart` now locks session-owned presence shape, `onDisconnect` offline state, and state-aware presence reads.

Validation run:

- `flutter test apps/rain/test/rain_call_failure_messages_test.dart apps/rain/test/rain_call_suite_models_test.dart apps/rain/test/voice_call_runtime_diagnostics_contract_test.dart --reporter expanded`
- `flutter test apps/rain/test/crash_diagnostics_service_test.dart apps/rain/test/call_retry_policy_test.dart apps/rain/test/runtime_interaction_guard_test.dart --reporter expanded`
- `flutter test --reporter expanded` from `packages/protocol_brain`
- `dart run melos run analyze`

Known remaining test gap: local Windows `apps/rain/test/friend_flow_test.dart` still fails before runtime assertions because sqlite native assets are not resolved by the local Flutter test process. Full app-close/session-owned presence proof still needs a repaired Drift/sqlite harness or equivalent CI evidence.
