# Emulator Test Matrix

Last updated: 2026-06-05

## Priority Scenarios

- Offline call creation denied before locks.
- Live call lock returns busy.
- Terminal call lock can be cleaned.
- Corrupt call room does not crash watcher.
- Connection request only allowed for offline/stale peer.
- Future-dated timestamps denied.
- Blocked peers denied.
- Tombstoned account cannot re-add `userSearch` or upsert profile data. Covered by `integration_account_deletion_emulator_test.dart`; cloud proof passed in `Build Rain Apps` run 26957834309.
- Account deletion cleanup preserves tombstone and denies post-delete restoration paths. Covered by `integration_account_deletion_emulator_test.dart`; cloud proof passed in `Build Rain Apps` run 26957834309.
- Online receiver connection request denial does not mutate quota.
- Newer live call locks are never repaired away.

## 2026-06-05 Senior Audit Emulator Proof Addendum

Source: [[2026-06-05 Senior Audit Remediation Plan]]

| SAR ID | Required Emulator Or Contract Proof | Status |
| --- | --- | --- |
| SAR-002 | Stale heartbeat, unknown local-only presence, backend presence session id propagation, and stale receiver request routing have local provider proof; app-close/offline state and device/emulator routing remain. | Partially Covered |
| SAR-004 | Caller/callee/pair lock behavior, terminal leftover locks, missing inbox cleanup, malformed lock/inbox writes, unauthorized transitions, oversized reason payloads, and denied-write state preservation are covered by `integration_voice_signaling_emulator_test.dart` and `firebase_contract_test.dart`. | Covered locally 2026-06-05 |
| SAR-008 | Diagnostics export/redaction proof can stay unit-level unless emulator payloads are needed to reproduce permission-denied or malformed data. Focused sanitizer/export and failure taxonomy tests passed locally on 2026-06-05. | Unit covered 2026-06-05 |
| SAR-009 | Hard release workflow must run emulator matrix before stable artifact publication. | Open |
| SAR-010 | Vault evidence ledger must record emulator command, branch, commit, date, and result. | Open |
| SAR-011 | Demo artifact workflow must label signing/channel clearly when emulator proof exists only for test builds. | Open |

## 2026-06-05 Phase 10 Device And Media Reality Proof Matrix

Source: [[Scenario Coverage Matrix]]

| Proof Surface | Command Or Evidence Path | 2026-06-05 Status | Release Meaning |
| --- | --- | --- | --- |
| Android QA environment readiness | `C:\android-flutter-qa-toolkit\scripts\test-env.ps1` | Passed: toolkit, Java, Android SDK, Flutter 3.44.0, Dart 3.12.0, Appium URL, and artifact root were detected. | Tooling exists, but this does not prove app media. |
| Attached Android endpoint | `flutter devices` and `adb devices` | Blocked: Flutter saw Windows, Chrome, and Edge only; `adb devices` listed no Android device. | No Android device/emulator proof can be claimed from this session. |
| Available emulator image | `flutter emulators` | Available but not running: `QA_Medium_API_36_1`. | Phase 10 can start from this emulator, but launching/running it still needs an actual smoke run. |
| Appium smoke harness | `C:\android-flutter-qa-toolkit\scripts\run-appium-smoke.ps1 -ProjectRoot "<repo>\apps\rain"` | Existing `apps\rain\qa.appium.json` targets only `qa.auth.mode.toggle`/`qa.auth.mode.title`; latest saved Rain Appium artifacts from 2026-05-30 timed out in WebDriver. | Appium remains non-blocking for development but cannot satisfy call/media release proof. |
| Single-device media capture | `flutter test integration_test\device_media_reality_proof_test.dart -d emulator-5554 --dart-define=RAIN_DEVICE_MEDIA_PROOF=true` from `apps\rain` | New opt-in test added; not passed locally because no Android endpoint was attached. | This is the first executable proof for real mic/camera capture through Rain's call media stack. |
| Cross-peer call direction matrix | Manual/device smoke with diagnostics and artifacts in `D:\android-test-artifacts` plus Windows diagnostics exports as needed. | Not run. | Public release remains blocked for BLK-001 until target directions are proven or explicitly scoped down. |

Related: [[Emulator Coverage]], [[Rules Strategy]], [[Signaling Reliability Epic]], [[Scenario Coverage Matrix]], [[Assumption Register]].
