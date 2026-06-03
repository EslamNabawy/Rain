# Audit Resolution Tracker

Last updated: 2026-06-03

## Purpose

Track every finding from [[Original Audit]] through roadmap, epic, task, and release readiness.

| Finding | Epic | Task | Risk/Debt | Status | Next Step |
| --- | --- | --- | --- | --- | --- |
| Oversized call runtime | [[Architecture Stabilization Epic]] | TASK-001 | TD-001 | [ ] Open | Define coordinator interfaces. |
| False busy and stale locks | [[Signaling Reliability Epic]] | TASK-002 | R-002 | [ ] Open | Add lease repair tests. |
| Implicit call phases | [[Signaling Reliability Epic]] | TASK-003 | TD-002 | [ ] Open | Add explicit state machine. |
| Missing ICE/TURN classification | [[Signaling Reliability Epic]] | TASK-004 | R-001 | [ ] Open | Add WebRTC stats timeline. |
| Rules coverage gaps | [[Security Hardening Epic]] | TASK-005 | R-005 | [ ] Open | Expand emulator matrix. |
| Presence stale after app close | [[Signaling Reliability Epic]] | TASK-006 | R-009 | [ ] Open | Session-owned presence. |
| Poisoned Firebase watches | [[Signaling Reliability Epic]] | TASK-007 | TD-003 | [ ] Open | Add corrupt entry handling. |
| Missing local indexes | [[Database Scalability Epic]] | TASK-008 | TD-007 | [ ] Open | Plan Drift migration. |
| Eager chat loading | [[Database Scalability Epic]] | TASK-009 | TD-007 | [ ] Open | Add pagination. |
| File receive memory pressure | [[File Transfer Optimization Epic]] | TASK-010 | R-006 | [ ] Open | Persistent sink. |
| File send buffer pressure | [[File Transfer Optimization Epic]] | TASK-011 | R-006 | [ ] Open | Data-channel backpressure. |
| Update version failures | [[Production Validation Epic]] | TASK-012 | R-004 | [ ] Open | Fix semantic/build compare. |
| Media capture order failures | [[Signaling Reliability Epic]] | TASK-013 | R-001 | [ ] Open | Create media coordinator. |
| Diagnostics privacy risk | [[Security Hardening Epic]] | TASK-014 | R-007 | [ ] Open | Strengthen sanitizer. |
| Weak release gate parity | [[CI-CD Modernization Epic]] | TASK-015 | R-008 | [ ] Open | Make hard gate fail early. |
| Workflow duplication | [[CI-CD Modernization Epic]] | TASK-016 | TD-008 | [ ] Open | Consolidate purposes. |
| Firebase cost exposure | [[Security Hardening Epic]] | TASK-017 | R-003 | [ ] Open | Add budgets and counters. |
| Adapter contracts under-tested | [[Production Validation Epic]] | TASK-018 | R-005 | [ ] Open | Add fake/emulator tests. |
| Fragmented call UI | [[Architecture Stabilization Epic]] | TASK-019 | TD-010 | [ ] Open | One call surface renderer. |
| Broad UI rebuilds | [[Architecture Stabilization Epic]] | TASK-020 | TD-006 | [ ] Open | Provider boundary cleanup. |

## Status Legend

- [ ] Open
- [/] In Progress
- [x] Done
- [-] Deferred

Related: [[Backlog]], [[Risk Register]], [[Technical Debt Register]], [[Production Readiness]].
