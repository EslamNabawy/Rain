# High-Risk Work

Last updated: 2026-06-03

## Purpose

Identify audit-derived work most likely to break existing behavior or require careful validation.

Related: [[Master Roadmap]], [[Critical Path]], [[Risk Register]], [[Technical Debt Register]].

## High-Risk Items

| Item | Priority | Dependencies | Estimated Effort | Risk | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- | --- |
| TASK-001: [[VoiceCallRuntime Refactor]] | P0 | [[Current Architecture]] | 5 days | Splitting a working-but-fragile runtime can regress calls. | Responsibilities are split behind tested contracts. | Voice/video runtime tests pass. |
| TASK-002: [[CallLeaseManager]] repair | P0 | TASK-001 | 4 days | Incorrect repair can delete live locks. | Only matching stale locks are removed. | Emulator/fake tests cover newer/live locks. |
| TASK-003: [[Call State Machine]] | P0 | TASK-002 | 4 days | Bad transitions can leave UI/runtime contradictory. | Terminal state is authoritative. | No stuck connecting tests pass. |
| TASK-013: [[CallMediaCoordinator]] | P0 | TASK-003 | 4 days | Platform media APIs can fail differently on Android/Windows. | Permission/capture failures cleanly terminate. | Media failure tests pass. |
| TASK-005: [[Rules Strategy]] | P0 | [[Firebase Architecture]] | 4 days | Rule changes can lock out old or valid clients. | Allow/deny matrix is tested. | Emulator tests pass before deploy. |
| TASK-018: Adapter contract tests | P1 | TASK-005 | 5 days | Contract gaps can hide production-only failures. | Fake and Firebase behavior align. | Contract matrix passes. |
| TASK-019: Call surface unification | P1 | TASK-003 | 4 days | UI changes can duplicate controls or hide hangup/answer. | One surface source of truth. | Widget tests cover all modes. |

## High-Risk Work Rule

Each high-risk item must have:

- Pre-change tests or characterization tests.
- Explicit rollback or containment plan.
- Updated [[Risk Register]] entry if risk remains.
- Updated [[Project Memory]] only when durable facts change.
