# Original Audit

Last updated: 2026-06-03

## Audit Basis

This note preserves the prior audit as the authoritative baseline for execution. It is not a new audit. It feeds [[Audit Resolution Tracker]], [[Backlog]], [[Risk Register]], and [[Technical Debt Register]].

## Score Baseline

- Technical debt score: 72/100 risk, higher is worse.
- Production readiness score: 48/100.
- Security score: 66/100.
- Scalability score: 45/100.
- Maintainability score: 50/100.
- Architecture score: 52/100.

## Top Findings

1. `VoiceCallRuntime` has too many responsibilities.
2. Call lease and terminal state handling can create false busy and stuck call states.
3. Presence freshness can lag behind app close or stale sessions.
4. Firebase rules need broader emulator coverage.
5. Watch streams must survive corrupt room or inbox data.
6. Update version validation has reported old-version prompt failures.
7. File transfer needs stronger streaming and backpressure.
8. Local database needs index and pagination validation.
9. Diagnostics must be useful without exposing sensitive data.
10. Release workflows need clearer hard gates and faster test artifact paths.
11. Call UI must use a single surface model.
12. ARMv7 and low-power device paths need performance budgets.
13. WebRTC ICE/TURN failure classification is incomplete.
14. Async cancellation and terminal cleanup need stricter ownership.
15. Security rules must prevent malformed or unauthorized signaling writes.
16. Connection request notification limits must be offline-only and message every blocked action.
17. Firebase cost counters should be tracked because Spark/free tier is a hard constraint.
18. Appium/local smoke tests need stable locators and repeatable setup.
19. Riverpod provider boundaries should avoid broad UI rebuilds.
20. Project knowledge must be maintained continuously in [[Project Memory]].

## Audit Resolution Rule

Every finding must have:

- An epic in [[Epic Index]].
- A task in [[Backlog]].
- A risk or debt entry where applicable.
- A row in [[Audit Resolution Tracker]].
- A definition of done before production release.

Related: [[Production Readiness]], [[Master Roadmap]], [[Critical Path]].
