# Audit Resolution Tracker

Last updated: 2026-06-05

## Purpose

Track every finding from [[Original Audit]] through epic, feature, task, subtasks, and release readiness.

Do not add new audit findings here unless [[Original Audit]] is updated. This tracker is the execution ledger for the existing audit baseline.

Related: [[Master Roadmap]], [[Backlog]], [[Epic Index]], [[Critical Path]], [[Risk Register]], [[Technical Debt Register]], [[2026-06-05 Senior Audit Remediation Plan]].

## Resolution Matrix

| # | Audit Finding | Epic | Feature | Task | Status | Next Step |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `VoiceCallRuntime` has too many responsibilities. | [[Architecture Stabilization Epic]] | Runtime Responsibility Split | TASK-001 | [ ] Partial 2026-06-05 | First slice extracted `CallErrorClassifier` and media adapters; next extract room reconciliation and lock coordination behind characterization tests. |
| 2 | Call lease and terminal state handling can create false busy and stuck call states. | [[Signaling Reliability Epic]] | Call Lease Repair | TASK-002 | [ ] Open | Add stale/live lock repair tests. |
| 3 | Presence freshness can lag behind app close or stale sessions. | [[Signaling Reliability Epic]] | Presence Freshness | TASK-006 | [ ] Open | Lock session-owned heartbeat and app-close tests. |
| 4 | Firebase rules need broader emulator coverage. | [[Security Hardening Epic]] | Firebase Rule Coverage | TASK-005 | [ ] Open | Expand RTDB allow/deny matrix. |
| 5 | Watch streams must survive corrupt room or inbox data. | [[Signaling Reliability Epic]] | Watch Stream Resilience | TASK-007 | [ ] Open | Add corrupt inbox/room stream tests. |
| 6 | Update version validation has reported old-version prompt failures. | [[Production Validation Epic]] | Update Version Validation | TASK-012 | [x] Mitigated | Same-version minimum-build required updates, stale-policy detection, root optional prompt, and settings manual-check tests added 2026-06-03. |
| 7 | File transfer needs stronger streaming and backpressure. | [[File Transfer Optimization Epic]] | Persistent Receive Streaming; Data Channel Backpressure | TASK-010, TASK-011 | [/] Mitigated locally 2026-06-05 | Add real-network/device-scale large-file proof if release closure requires more than local runtime tests. |
| 8 | Local database needs index and pagination validation. | [[Database Scalability Epic]] | Index Strategy; Conversation Pagination | TASK-008, TASK-009 | [/] Mitigated locally 2026-06-05 | Add device/frame-budget evidence for large conversations before closing release-scale risk. |
| 9 | Diagnostics must be useful without exposing sensitive data. | [[Security Hardening Epic]] | Diagnostics Privacy | TASK-014 | [/] Mitigated locally 2026-06-05 | Keep sanitizer regressions mandatory for new diagnostic fields and run workspace/vault gates before release claims. |
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

## 2026-06-05 Senior Audit SAR Overlay

Source: [[2026-06-05 Senior Audit Remediation Plan]]

This overlay maps the fresh senior audit issue IDs to the existing audit execution system. It does not mutate the original finding numbers.

| SAR ID | Existing Audit Rows | Primary Phase | Owner | Priority | Evidence Required | Release Impact | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SAR-001 | 1, 13, 14 | Phase 3 | Engineering | P0 | First slice: classifier/media adapter tests passed. Phase 10 added an opt-in real media capture proof hook. Remaining: terminal room, late Firebase update, room reconciliation, lock coordination, command/media ownership, and passed device-direction proof. | Blocks public launch while call setup reliability is unproven. | Partial 2026-06-05 |
| SAR-002 | 3, 16, 19 | Phase 1 | Engineering | P0 | Provider/runtime tests for stale heartbeat, backend presence session id, freshness, unknown local-only presence, and stale receiver routing. | Blocks safe connect/call/request action routing until Firebase emulator/device proof lands. | Mitigated locally 2026-06-05 |
| SAR-003 | 3, 16, 19 | Phase 1 | Engineering/Product | P0 | Chat action routing consumes `PeerConnectivitySnapshot.peerOnlineForAction`; focused provider tests cover stale/unknown/fresh routing. | Blocks safe user action behavior until Firebase emulator/device proof lands. | Mitigated locally 2026-06-05 |
| SAR-004 | 2, 4, 14, 15 | Phase 2 | Engineering/Security | P0 | Emulator/rules tests for terminal leftover locks, malformed lock/inbox writes, invalid transitions, denied-write state preservation, and server-authoritative transactions. Phase 10 device matrix is defined but not run. | Device media-direction proof remains open, but Firebase call lock/rule proof is complete locally. | Complete local emulator proof 2026-06-05 |
| SAR-005 | 9 | Phase 5 | Security/Product | P1 | Option A accepted 2026-06-05 in [[ADR-010]]; privacy/security/readiness docs state local Drift/SQLite storage is plaintext and no local encryption claim is allowed. | Blocks strong local privacy claims unless future encrypted-storage implementation lands. | Accepted/documented 2026-06-05 |
| SAR-006 | 8 | Phase 6 | Engineering | P1 | `rain_core` schema/index migration tests and app provider pagination tests passed locally on 2026-06-05. Remaining evidence: low-power/device frame-budget proof. | No longer blocks local query-structure confidence; still blocks device-scale performance confidence. | Mitigated locally 2026-06-05 |
| SAR-007 | 7 | Phase 7 | Engineering | P1 | Focused local tests passed for large transfer receive, scripted slow receiver/backpressure, cancel cleanup, hash failure cleanup, disk write failure, and temp cleanup. | Local runtime reliability is mitigated; device-scale real-network confidence remains follow-up evidence. | Mitigated locally 2026-06-05 |
| SAR-008 | 9, 13 | Phase 4 | Security/Engineering | P0/P1 | Recursive sanitizer/export tests and call failure taxonomy tests passed locally on 2026-06-05. | Safe local diagnostic export is mitigated for covered samples; new diagnostic fields still require sanitizer proof. | Mitigated locally 2026-06-05 |
| SAR-009 | 10 | Phase 8 | DevOps | P0/P1 | Local workflow contract tests require validation gates, metadata, and production Remote Config evidence before publish. | Fresh cloud workflow run remains required before promoting a specific artifact. | Mitigated locally 2026-06-05 |
| SAR-010 | 20 | Phase 9 | DevOps/Engineering | P1 | `scripts/check_obsidian_vault.ps1` now validates operational owner/priority/evidence fields, evidence ledger rows, stale review dates, closed-blocker evidence, and P0/P1 next-action coverage. | Trustworthy governance claims now have local semantic validation; generated metric reconciliation remains future hardening. | Mitigated locally 2026-06-05 |
| SAR-011 | 10 | Phase 8 | DevOps/Security | P2 | `rain-test-*` direct-download releases are labeled `TEST ARTIFACT ONLY`; metadata records artifact purpose/build profile. | Demo artifacts still cannot be represented as production-trust artifacts. | Mitigated locally 2026-06-05 |
| SAR-012 | 19 | Phase 1/6 | Engineering/UI | P2 | Chat panel now watches the selected immutable peer snapshot; rebuild isolation proof remains Phase 6. | Impacts performance and UI stability. | Partial 2026-06-05 |

## Auth/Startup Remediation Tracker

Source: [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md)

| Phase | Scope | Status | Evidence | Next Step |
| --- | --- | --- | --- | --- |
| Phase 1 | Authentication source of truth and cached identity validation. | [x] Complete | `IdentityController` validates cached identity against backend account existence and current auth uid before restoration; local identity saves after backend writes; tests cover deleted backend account, uid mismatch, and backend profile refresh. | Completed; see Phase 2. |
| Phase 2 | Deterministic logout/reset and full session destruction. | [x] Complete | `RainRuntimeController` clears local session before best-effort backend sign-out; existing shutdown futures still perform logout local clear; `RuntimeController.logOut()` invalidates session providers in `finally`; tests cover failed sign-out and logout-after-app-exit shutdown. | Completed; see Phase 3. |
| Phase 3 | Startup state machine. | [x] Complete | `AppStartupState`/`AppStartupPhase` centralizes update, session validation, signed-out, runtime loading, session-expired, failed, and ready phases; `RootScreen`, shell readiness, and router refresh/redirect consume it; tests cover every startup phase. | Completed; see Phase 4. |
| Phase 4 | Global splash architecture. | [x] Complete | `RainApp` uses `MaterialApp.router.builder` to replace the routed child with `RainStartupSurface` while startup is loading, update-blocked, failed, or session-expired; `RootScreen` reuses the same surface; route tests prove no `RainNavigationShell`, bottom navigation, or rail is inserted during blocked startup. | Completed; see Phase 5. |
| Phase 5 | Navigation readiness. | [x] Complete | `AppStartupState.canRenderProtectedRoutes` and `usesRoutedAppShell` define protected readiness; unresolved protected paths redirect to `/`; settings/search/friend pages are wrapped in `_ProtectedRouteGate`; signed-out auth uses a standalone Navigator/Overlay and never inserts `RainNavigationShell`; tests cover protected routes while runtime is loading and signed out. | Completed; see Phase 6. |
| Phase 6 | State lifecycle hardening. | [x] Complete | `AuthenticatedSession.sessionGeneration` scopes runtime ownership; `RainRuntimeController` reuse requires matching username and generation; runtime/brain/request/call/connection/message/file/search/recent providers reset on session end or user switch. Tests cover generation changes, recent/search reset, signed-out message streams, startup routes, and full Melos validation. | Completed; see account deletion. |
| Root Phase 05 | Account deletion workflow. | [x] Complete locally | Settings delete-account confirmation/password UI, signaling reauth/delete contract, Firebase cleanup/tombstone/Auth-delete-last path, runtime/provider destructive-session handling, no-recreate login/upsert/search guards, and targeted tests are implemented. `dart run melos run analyze` and `dart run melos run test` passed on 2026-06-04. | Add auth/startup/account-deletion regressions to the hard release gate and add Firebase emulator/device cleanup proof if required. |

## Status Legend

- [ ] Open
- [/] In Progress
- [x] Done
- [-] Deferred

## Tracker Definition Of Done

- Every row has an epic, feature, task, and next step.
- Completed tasks update [[Master Roadmap]], [[Backlog]], [[Risk Register]], [[Technical Debt Register]], and [[Project Memory]] where applicable.
- Public release cannot proceed while any P0 row remains open without explicit acceptance in [[Launch Readiness]].
