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

## No-Go Conditions

- Critical call bugs open.
- Update required prompt unverified.
- Firebase permission denied regression.
- Documentation vault check fails.

Related: [[CI-CD Roadmap]], [[Production Readiness]].
