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
- [/] Auth/startup remediation Phase 1: [[Authentication]]

## Out Of Scope

- Full UI redesign.
- New backend paid services.
- Closed-app push notifications.
- New Firebase schema unless explicitly required by [[Rules Strategy]].

## Sprint Acceptance

- Call start/end behavior is easier to reason about.
- Cached identity cannot restore a deleted or wrong-owner backend account.
- Stale locks are tested.
- Update prompt version comparison is tested; release artifact plus deployed Remote Config verification still required.
- Release gate does not publish without critical tests.

Related: [[Sprint Planning]], [[Backlog]], [[Weekly Progress]].
