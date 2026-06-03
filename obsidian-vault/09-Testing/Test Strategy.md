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

Known invocation rule: local Windows app tests that touch Drift/SQLite must run from `apps/rain` or through `scripts/run_rain_app_test.ps1`. Running a root-relative app test directly from the repository root can fail before runtime assertions because sqlite native assets are not resolved for the app package.

## Rain App Isolated Test Invocation

Do not run app tests that touch Drift/SQLite from the repository root with a root-relative test path, for example:

```powershell
flutter test apps\rain\test\friend_flow_test.dart
```

That invocation can fail on Windows before test logic with `Couldn't resolve native function 'sqlite3_initialize'` because native assets are not resolved for the app package.

Use the wrapper instead:

```powershell
.\scripts\run_rain_app_test.ps1 apps\rain\test\friend_flow_test.dart
```

For a targeted test:

```powershell
.\scripts\run_rain_app_test.ps1 apps\rain\test\friend_flow_test.dart -PlainName "relationship sync does not seed stale backend presence as online"
```

The wrapper always runs `flutter test` from `apps/rain`, accepts either root-relative or app-relative test paths, and keeps isolated app tests aligned with the Melos package context.

Validation evidence:

- `.\scripts\run_rain_app_test.ps1 apps\rain\test\friend_flow_test.dart -PlainName "relationship sync does not seed stale backend presence as online"` passed on 2026-06-03.
- `.\scripts\run_rain_app_test.ps1 apps\rain\test\friend_flow_test.dart -NoPubGet` passed on 2026-06-03 with 120 tests passing and 10 skipped legacy control-channel cases.
