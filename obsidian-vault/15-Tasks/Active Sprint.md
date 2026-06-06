# Active Sprint

Last updated: 2026-06-03

## Sprint Goal

Stabilize the highest-risk auth/startup, call, and release-readiness foundations from [[Critical Path]] without changing unrelated working features.

## Sprint Scope

- [/] TASK-001: [[VoiceCallRuntime Refactor]]
- [ ] TASK-002: [[CallLeaseManager]]
- [ ] TASK-003: [[Call State Machine]]
- [ ] TASK-005: [[Rules Strategy]]
- [/] TASK-012: [[Version And Updates]]
- [x] Auth/startup remediation Phase 1: [[Authentication]]
- [x] Auth/startup remediation Phase 2: deterministic logout/reset
- [ ] Auth/startup remediation Phase 3: startup state machine

## Out Of Scope

- Full UI redesign.
- New backend paid services.
- Closed-app push notifications.
- New Firebase schema unless explicitly required by [[Rules Strategy]].

## Sprint Acceptance

- Call start/end behavior is easier to reason about.
- Cached identity cannot restore a deleted or wrong-owner backend account.
- Logout cannot preserve cached identity because backend sign-out failed or because app-exit shutdown started first.
- Stale locks are tested.
- Update prompt version comparison is tested; `rain-test-118-1` and live Remote Config version 9 prove artifact plus deployed policy for `1.0.8+9`; installed old/current app verification is still required.
- Release gate does not publish without critical tests.

Related: [[Sprint Planning]], [[Backlog]], [[Weekly Progress]].
