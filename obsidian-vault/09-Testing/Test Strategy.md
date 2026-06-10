# Test Strategy

## Production Test Strategy

1. Unit tests for pure state and protocol logic.
2. Widget tests for UI layout and safe area.
3. Runtime tests with fakes for call/file/connection.
4. Firebase emulator tests for rules and signaling contracts.
5. Release artifact smoke tests.
6. Manual Android/Windows WebRTC smoke checks.

Related: [[Coverage Dashboard]], [[Emulator Test Matrix]], [[Production Validation Epic]], [[Scenario Intelligence Agent]], [[Failure Graph]], [[Assumption Register]].

## Scenario Intelligence Testing

Testing and release-gate planning should be derived from the graph set:

- [[System Model]]
- [[Feature Map]]
- [[Dependency Map]]
- [[State Graph]]
- [[Business Rule Graph]]
- [[Assumption Register]]
- [[Failure Graph]]
- [[Scenario Coverage Matrix]]

For each target flow, generate scenarios by violating relevant assumptions and tracing the downstream failure chain. Promote high-impact uncovered chains into deterministic tests, release-gate checks, risks, debt, or blockers.

Minimum scenario batch output:

- target flow,
- state path,
- violated assumption,
- critical assets touched,
- expected fail-closed or recovery behavior,
- existing test evidence,
- missing test or risk record,
- scenario coverage status.

The [[Scenario Coverage Matrix]] is the source for scenario IDs, covered status, and release-gate gaps.

## Phase 10 Device And Media Proof

Phase 10 separates three proof levels:

- Single-device media capture through the real WebRTC plugin and Rain call media stack.
- Cross-peer voice/video call setup across Android/Windows target directions.
- Appium black-box smoke, which remains optional development evidence until it is repeatable and call-aware.

Opt-in media capture command from `apps\rain`:

```powershell
flutter test integration_test\device_media_reality_proof_test.dart -d emulator-5554 --dart-define=RAIN_DEVICE_MEDIA_PROOF=true
```

Use `--dart-define=RAIN_DEVICE_MEDIA_REQUIRE_VIDEO=false` only for an explicitly scoped audio-only proof. A public voice/video release cannot use the audio-only run as video proof.

2026-06-05 evidence status: `C:\android-flutter-qa-toolkit\scripts\test-env.ps1` passed and `QA_Medium_API_36_1` exists, but no Android device/emulator was attached. Existing Rain Appium artifacts timed out in WebDriver and cover only auth toggle smoke. No call/media device proof passed in that session.

## Regression Expansion - 2026-06-03

Phase 08 added low-dependency regression tests around the current RCA failure cluster:

- `apps/rain/test/rain_call_failure_messages_test.dart` locks stable user-facing messages for WebRTC transceiver/SDP native failures, Firebase permission-denied setup failures, and network-loss terminal failures.
- `apps/rain/test/rain_call_suite_models_test.dart` now covers failed outgoing video state, failed incoming network-loss dismissal, and narrow-phone video dock overflow so compact controls keep mic/camera/hangup visible.
- `apps/rain/test/voice_call_runtime_diagnostics_contract_test.dart` now locks terminal-room-before-session-hangup ordering, failed-media terminal write before session disposal, and already-terminal Firebase cleanup classification.
- `packages/protocol_brain/test/firebase_contract_test.dart` now locks session-owned presence shape, `onDisconnect` offline state, and state-aware presence reads.
- 2026-06-05 Phase 2 extends Firebase proof: `apps/rain/test/integration_voice_signaling_emulator_test.dart` covers terminal leftover voice locks, missing inbox cleanup, malformed voice lock/inbox denial, unauthorized transition denial, oversized terminal reason denial, and denied-write state preservation. `packages/protocol_brain/test/firebase_contract_test.dart` locks server-authoritative voice lock transactions and compare-delete fallback behavior.

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
