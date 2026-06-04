# Release Gates

## Required Gates

- `dart pub get`
- `dart run melos run analyze`
- `dart run melos run test`
- Firebase JSON/rules validation.
- Firebase emulator tests.
- Documentation vault validation.
- Android v7a artifact.
- Android v8/v9 artifact.
- Windows artifact.
- Version/channel/commit artifact proof.

## Latest Local Gate Evidence

### 2026-06-04 Cloud Update Warning Gate And Artifact Proof

- Workflow: `Build Rain Apps`
- Run: https://github.com/EslamNabawy/Rain/actions/runs/26963049075
- Trigger: `workflow_dispatch`
- Inputs: `platform=all`, `build_profile=demo`, `publish_test_release=true`
- Branch/SHA validated: `dev` / `f1904e72f1c16773700f0bfa6bcc8ac0fcd7706d`
- Passed: Hard Release Gate in 4m18s.
- Passed: workspace dependency restore, lock drift check, Dart formatting, generated artifact presence, analyzer, full Melos tests, explicit auth lifecycle scenario tests, Firebase JSON parsing, Firebase Functions install/lint/audit/tests, Firebase emulator integration tests, and Obsidian vault validation.
- Passed: Windows demo portable artifact build and native runtime verification.
- Passed: Android APK artifact build and ABI verification.
- Passed: GitHub pre-release publication.
- Published release: https://github.com/EslamNabawy/Rain/releases/tag/rain-test-109-1
- Published assets: `Rain-Demo-Android-v7a.apk`, `Rain-Demo-Android-v8-v9.apk`, `Rain-Demo-Windows-x64.zip`.
- Scope: validates pushed `1.0.7+8` update-warning metadata, checked-in Remote Config template behavior, hard release gate, Android demo APKs, and Windows demo portable artifact at commit `f1904e7`.
- Remaining operational dependency: deploy Firebase Remote Config so already-installed `1.0.6+7` clients can read the newer `1.0.7+8` policy.

### 2026-06-04 Local Auth Scenario Gate Integration

- Added explicit hard-gate auth lifecycle scenario step for `SCN-AUTH-001` through `SCN-AUTH-004` in `build-artifacts.yml` and `validated-release.yml`.
- Added hard-gate vault validation through `./scripts/check_obsidian_vault.ps1` in `build-artifacts.yml` and `validated-release.yml`.
- Added Firebase emulator account deletion coverage in `apps/rain/test/integration_account_deletion_emulator_test.dart`.
- Added the account deletion emulator test to `scripts/ci_run_firebase_emulators.sh` and `scripts/ci_run_firebase_emulators.ps1`.
- Passed locally: `.\scripts\ci_run_firebase_emulators.ps1`, including account tombstone cleanup and surviving-Auth no-recreate proof.
- Cloud proof passed in `Build Rain Apps` run 26957834309 for pushed `dev` SHA `883886a2e81ee370e3641ddcefce8d62942a3566`.

### 2026-06-04 Cloud Auth Scenario Gate And Artifact Proof

- Workflow: `Build Rain Apps`
- Run: https://github.com/EslamNabawy/Rain/actions/runs/26957834309
- Trigger: `workflow_dispatch`
- Inputs: `platform=all`, `build_profile=demo`, `publish_test_release=true`
- Branch/SHA validated: `dev` / `883886a2e81ee370e3641ddcefce8d62942a3566`
- Passed: Hard Release Gate in 4m16s.
- Passed: workspace dependency restore, lock drift check, Dart formatting, generated artifact presence, analyzer, full Melos tests, explicit auth lifecycle scenario tests, Firebase JSON parsing, Firebase Functions install/lint/audit/tests, Firebase emulator integration tests, and Obsidian vault validation.
- Passed: Android APK artifact build and ABI verification in 14m4s.
- Passed: Windows demo portable artifact build and native runtime verification in 7m11s.
- Passed: GitHub pre-release publication.
- Published release: https://github.com/EslamNabawy/Rain/releases/tag/rain-test-108-1
- Published assets: `Rain-Demo-Android-v7a.apk`, `Rain-Demo-Android-v8-v9.apk`, `Rain-Demo-Windows-x64.zip`.
- Scope: validates the account-deletion workflow, scenario-gate integration, vault sync, Android demo APKs, and Windows demo portable artifact at commit `883886a`.

### 2026-06-04 Cloud Hard Gate And Artifact Proof

- Workflow: `Build Rain Apps`
- Run: https://github.com/EslamNabawy/Rain/actions/runs/26931788461
- Trigger: `workflow_dispatch`
- Inputs: `platform=all`, `build_profile=demo`, `publish_test_release=true`
- Branch/SHA validated: `dev` / `d58b7b51a7b1dab5fa57c6e541b38475fdda1a97`
- Passed: Hard Release Gate in 3m48s.
- Passed: workspace dependency restore, lock drift check, Dart formatting, generated artifact presence, analyzer, full Melos tests, Firebase JSON parsing, Firebase Functions install/lint/audit/tests, and Firebase emulator integration tests.
- Passed: Android APK artifact build and ABI verification in 13m34s.
- Passed: Windows demo portable artifact build and native runtime verification in 6m59s.
- Passed: GitHub pre-release publication.
- Published release: https://github.com/EslamNabawy/Rain/releases/tag/rain-test-107-1
- Published assets: `Rain-Demo-Android-v7a.apk`, `Rain-Demo-Android-v8-v9.apk`, `Rain-Demo-Windows-x64.zip`.
- Scope caveat: this cloud run validated the pushed `origin/dev` SHA `d58b7b5`. Account-deletion/scenario-intelligence changes were later validated by run 26957834309 at `883886a`.

### 2026-06-03 Phase 09 Pre-Artifact Gate

- Branch: `dev`
- Local state before push: `dev` was ahead of `origin/dev` by 5 commits.
- Passed: `dart pub get`
- Passed: `dart run melos run analyze`
- Passed: `dart run melos run test`
- Passed: Firebase JSON/rules/template parsing.
- Passed: Firebase Functions tests, 37/37.
- Passed: Firebase emulator integration tests for voice signaling contract, stale lock reclaim, already-cleaned inbox cleanup, and signaling rule bypass rejection.
- Passed: Obsidian vault validation, 188 markdown files.
- Not completed locally: Android v7a artifact, Android v8/v9 artifact, Windows artifact, and release-page proof. These must be produced by the cloud validated release workflow before the hard gate can be considered complete.

## No-Go Conditions

- Critical call bugs open.
- Update required prompt unverified.
- Firebase permission denied regression.
- Documentation vault check fails.

Related: [[CI-CD Roadmap]], [[Production Readiness]].
