# 30 Day Plan

Last updated: 2026-06-03

## Goal

Stabilize release-blocking foundations: call runtime ownership, call leases, terminal call state, media setup, Firebase rules coverage, update prompts, and diagnostics privacy.

Related: [[Master Roadmap]], [[Critical Path]], [[Launch Blockers]], [[High-Risk Work]], [[Active Sprint]].

## Day 1-7: Call Runtime Contracts

| Item | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| TASK-001: [[VoiceCallRuntime Refactor]] coordinator boundaries | P0 | [[Current Architecture]], [[CallStartCoordinator]], [[CallDiagnosticsRecorder]] | 5 days | Coordinator contracts exist and current behavior is testable. | Interfaces, tests, and docs are updated without behavior regression. |
| TASK-012: [[Version And Updates]] comparison tests | P0 | [[Release Gates]] | 2 days | Old/current/newer version cases are deterministic. | Required/optional/check-unavailable tests pass. |

## Day 8-14: Lease And Terminal Reliability

| Item | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| TASK-002: [[CallLeaseManager]] stale lock repair | P0 | TASK-001, [[Lease Management]] | 4 days | Stale locks repair once before busy. | Fake/emulator tests prove stale, corrupt, missing, terminal, and live lock behavior. |
| TASK-003: [[Call State Machine]] terminal ownership | P0 | TASK-001, TASK-002 | 4 days | Terminal room state always clears local/remote state. | Runtime tests prove no stuck connecting or late-frame reversal. |

## Day 15-21: Firebase And Diagnostics Gate

| Item | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| TASK-005: [[Rules Strategy]] emulator expansion | P0 | [[Firebase Architecture]], [[Emulator Coverage]] | 4 days | Critical RTDB allow/deny branches are tested. | Rules tests cover auth, presence, rooms, calls, locks, inboxes, requests. |
| TASK-014: [[Diagnostics Sanitization]] hardening | P1 | [[Privacy Review]] | 2 days | Sensitive payloads are recursively redacted. | Sanitizer tests pass for nested sensitive data. |
| TASK-017: Firebase cost counters | P1 | [[Firebase Architecture]] | 2 days | Firebase usage categories are tracked. | Diagnostics export includes cost/counter summaries. |

## Day 22-30: Media Setup And Release Gate

| Item | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| TASK-013: [[CallMediaCoordinator]] capture ordering | P0 | TASK-003 | 4 days | Permission/media failures terminate and release locks. | Tests cover denied mic/camera, disposed renderer/transceiver, media timeout. |
| TASK-015: [[Release Gates]] hard gate parity | P1 | [[CI-CD Roadmap]], TASK-005, TASK-012 | 2 days | Artifact publication cannot bypass critical gates. | Workflows document and enforce analyze/test/rules/vault gates. |

## 30 Day Exit Criteria

- P0 call setup/terminal tasks are testable.
- Stale locks no longer directly produce unverified busy state.
- Update prompt regression tests exist.
- Firebase rules test matrix covers critical signaling paths.
- Diagnostics privacy tests exist.

## 30 Day Definition Of Done

- [[Audit Resolution Tracker]] updated for completed tasks.
- [[Risk Register]] updated for any remaining blockers.
- [[Project Memory]] updated with durable lessons.
- `.\scripts\check_obsidian_vault.ps1` passes.
