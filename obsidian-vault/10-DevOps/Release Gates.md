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
