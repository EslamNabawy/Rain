# Coverage Report

Current qualitative coverage score: 70/100.

## Strong Areas

- Core frame parsing.
- Peer media fake tests.
- Runtime guard decisions.
- UI widget tests for many surfaces.
- Firebase rule contract tests exist.

## Weak Areas

- Real device WebRTC behavior.
- End-to-end PC-to-mobile calls.
- Update system old-version behavior.
- Performance under large message/file load.
- Firebase permission-denied recovery behavior.

## Required Metrics

Future CI should publish:

- line coverage
- branch coverage for runtime decision logic
- Firebase emulator pass/fail summary
- release artifact smoke result
- Android QA harness smoke result

Related: [[Test Strategy]], [[QA Findings]].
