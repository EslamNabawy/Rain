# Coverage Dashboard

## Target Coverage Signals

- Unit test pass rate.
- Widget test pass rate.
- Firebase emulator pass rate.
- Release artifact smoke pass rate.
- Documentation vault check pass rate.
- Scenario coverage status from [[Scenario Coverage Matrix]].

## Missing Signal

Line coverage alone is not enough. The real target is critical workflow coverage.

## Scenario Coverage Signal

Critical workflow coverage should track:

- Covered scenario IDs.
- Partially covered scenario IDs.
- Gap scenario IDs.
- Release-gate scenario IDs executed for a build.
- Explicitly skipped scenario IDs and reason.

Current auth gate update 2026-06-04: `SCN-AUTH-001` through `SCN-AUTH-004` have explicit hard-gate workflow commands, and `SCN-AUTH-002`/`SCN-AUTH-004` have Firebase emulator proof through `integration_account_deletion_emulator_test.dart`. Cloud proof passed in `Build Rain Apps` run 26957834309 at `883886a`.

Initial source: [[Scenario Coverage Matrix]].

Related: [[Test Strategy]], [[Release Gates]], [[Scenario Coverage Matrix]], [[Failure Graph]], [[Assumption Register]].
