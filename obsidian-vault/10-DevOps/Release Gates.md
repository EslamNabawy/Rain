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

### 2026-06-04 Local Auth Scenario Gate Integration

- Added explicit hard-gate auth lifecycle scenario step for `SCN-AUTH-001` through `SCN-AUTH-004` in `build-artifacts.yml` and `validated-release.yml`.
- Added hard-gate vault validation through `./scripts/check_obsidian_vault.ps1` in `build-artifacts.yml` and `validated-release.yml`.
- Added Firebase emulator account deletion coverage in `apps/rain/test/integration_account_deletion_emulator_test.dart`.
- Added the account deletion emulator test to `scripts/ci_run_firebase_emulators.sh` and `scripts/ci_run_firebase_emulators.ps1`.
- Passed locally: `.\scripts\ci_run_firebase_emulators.ps1`, including account tombstone cleanup and surviving-Auth no-recreate proof.
- Cloud proof on the new pushed commit is pending.

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
- Scope caveat: this cloud run validated the pushed `origin/dev` SHA `d58b7b5`. It did not validate the current dirty local worktree or unpushed account-deletion/scenario-intelligence changes.

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
