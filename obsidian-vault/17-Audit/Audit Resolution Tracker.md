# Audit Resolution Tracker

Last updated: 2026-06-03

## Purpose

Track every finding from [[Original Audit]] through epic, feature, task, subtasks, and release readiness.

Do not add new audit findings here unless [[Original Audit]] is updated. This tracker is the execution ledger for the existing audit baseline.

Related: [[Master Roadmap]], [[Backlog]], [[Epic Index]], [[Critical Path]], [[Risk Register]], [[Technical Debt Register]].

## Resolution Matrix

| # | Audit Finding | Epic | Feature | Task | Status | Next Step |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `VoiceCallRuntime` has too many responsibilities. | [[Architecture Stabilization Epic]] | Runtime Responsibility Split | TASK-001 | [ ] Open | Define coordinator interfaces and characterization tests. |
| 2 | Call lease and terminal state handling can create false busy and stuck call states. | [[Signaling Reliability Epic]] | Call Lease Repair | TASK-002 | [ ] Open | Add stale/live lock repair tests. |
| 3 | Presence freshness can lag behind app close or stale sessions. | [[Signaling Reliability Epic]] | Presence Freshness | TASK-006 | [ ] Open | Lock session-owned heartbeat and app-close tests. |
| 4 | Firebase rules need broader emulator coverage. | [[Security Hardening Epic]] | Firebase Rule Coverage | TASK-005 | [ ] Open | Expand RTDB allow/deny matrix. |
| 5 | Watch streams must survive corrupt room or inbox data. | [[Signaling Reliability Epic]] | Watch Stream Resilience | TASK-007 | [ ] Open | Add corrupt inbox/room stream tests. |
| 6 | Update version validation has reported old-version prompt failures. | [[Production Validation Epic]] | Update Version Validation | TASK-012 | [x] Mitigated | Same-version minimum-build required updates, stale-policy detection, root optional prompt, and settings manual-check tests added 2026-06-03. |
| 7 | File transfer needs stronger streaming and backpressure. | [[File Transfer Optimization Epic]] | Persistent Receive Streaming; Data Channel Backpressure | TASK-010, TASK-011 | [ ] Open | Define receive sink lifecycle and bufferedAmount budgets. |
| 8 | Local database needs index and pagination validation. | [[Database Scalability Epic]] | Index Strategy; Conversation Pagination | TASK-008, TASK-009 | [ ] Open | Plan Drift index migration and paginated query tests. |
| 9 | Diagnostics must be useful without exposing sensitive data. | [[Security Hardening Epic]] | Diagnostics Privacy | TASK-014 | [ ] Open | Strengthen recursive sanitizer tests. |
| 10 | Release workflows need clearer hard gates and faster test artifact paths. | [[CI-CD Modernization Epic]] | Release Gate Parity; Workflow Ownership | TASK-015, TASK-016 | [ ] Open | Define hard gate matrix and workflow ownership map. |
| 11 | Call UI must use a single surface model. | [[Architecture Stabilization Epic]] | Call Surface Single Source | TASK-019 | [ ] Open | Define call surface rendering contract. |
| 12 | ARMv7 and low-power device paths need performance budgets. | [[Production Validation Epic]] | Performance Tier Validation | TASK-021 | [ ] Open | Define low-power budget and static visual path tests. |
| 13 | WebRTC ICE/TURN failure classification is incomplete. | [[Signaling Reliability Epic]] | WebRTC Failure Classification | TASK-004 | [ ] Open | Add sanitized call setup timeline schema. |
| 14 | Async cancellation and terminal cleanup need stricter ownership. | [[Signaling Reliability Epic]] | Explicit Call State Machine; Media Capture Ordering | TASK-003, TASK-013 | [ ] Open | Define allowed transitions and timeout-to-terminal rules. |
| 15 | Security rules must prevent malformed or unauthorized signaling writes. | [[Security Hardening Epic]] | Firebase Rule Coverage | TASK-005 | [ ] Open | Add denied malformed signaling write tests. |
| 16 | Connection request notification limits must be offline-only and message every blocked action. | [[Security Hardening Epic]] | Offline Request Guardrails | TASK-023 | [ ] Open | Add confirmation, online-denial, and message-matrix tests. |
| 17 | Firebase cost counters should be tracked because Spark/free tier is a hard constraint. | [[Security Hardening Epic]] | Firebase Cost Guardrails | TASK-017 | [ ] Open | Define operation budgets and diagnostics counters. |
| 18 | Appium/local smoke tests need stable locators and repeatable setup. | [[Production Validation Epic]] | Adapter Contract Tests | TASK-018 | [ ] Open | Add fake/emulator adapter contract matrix and smoke checklist. |
| 19 | Riverpod provider boundaries should avoid broad UI rebuilds. | [[Architecture Stabilization Epic]] | Provider Boundary Cleanup | TASK-020 | [ ] Open | Identify broad Home/Chat watches. |
| 20 | Project knowledge must be maintained continuously in [[Project Memory]]. | [[Production Validation Epic]] | Continuous Knowledge Maintenance | TASK-022 | [ ] Open | Keep vault validation and memory updates in release workflow. |

## Auth/Startup Remediation Tracker

Source: [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md)

| Phase | Scope | Status | Evidence | Next Step |
| --- | --- | --- | --- | --- |
| Phase 1 | Authentication source of truth and cached identity validation. | [x] Complete | `IdentityController` validates cached identity against backend account existence and current auth uid before restoration; local identity saves after backend writes; tests cover deleted backend account, uid mismatch, and backend profile refresh. | Completed; see Phase 2. |
| Phase 2 | Deterministic logout/reset and full session destruction. | [x] Complete | `RainRuntimeController` clears local session before best-effort backend sign-out; existing shutdown futures still perform logout local clear; `RuntimeController.logOut()` invalidates session providers in `finally`; tests cover failed sign-out and logout-after-app-exit shutdown. | Completed; see Phase 3. |
| Phase 3 | Startup state machine. | [x] Complete | `AppStartupState`/`AppStartupPhase` centralizes update, session validation, signed-out, runtime loading, session-expired, failed, and ready phases; `RootScreen`, shell readiness, and router refresh/redirect consume it; tests cover every startup phase. | Completed; see Phase 4. |
| Phase 4 | Global splash architecture. | [x] Complete | `RainApp` uses `MaterialApp.router.builder` to replace the routed child with `RainStartupSurface` while startup is loading, update-blocked, failed, or session-expired; `RootScreen` reuses the same surface; route tests prove no `RainNavigationShell`, bottom navigation, or rail is inserted during blocked startup. | Start navigation readiness. |
| Phase 5 | Navigation readiness. | [ ] Open | Not implemented in this phase. | Ensure protected routes cannot render during auth/runtime loading. |
| Phase 6 | State lifecycle hardening. | [ ] Open | Not implemented in this phase. | Scope account providers by validated session generation. |

## Status Legend

- [ ] Open
- [/] In Progress
- [x] Done
- [-] Deferred

## Tracker Definition Of Done

- Every row has an epic, feature, task, and next step.
- Completed tasks update [[Master Roadmap]], [[Backlog]], [[Risk Register]], [[Technical Debt Register]], and [[Project Memory]] where applicable.
- Public release cannot proceed while any P0 row remains open without explicit acceptance in [[Launch Readiness]].
