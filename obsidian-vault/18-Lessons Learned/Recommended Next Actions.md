# Recommended Next Actions

Last updated: 2026-06-03

## Purpose

This note continuously converts current project state, risks, debt, lessons, and metrics into recommended next actions.

Related: [[Project Metrics]], [[Improvement Backlog]], [[Optimization Opportunities]], [[Critical Path]], [[Recommended Next Actions]], [[Project Memory]].

## Current Recommendation Summary

Before Phase 9 automation, continue hardening the engineering system foundations that automation will rely on. Duplicate title ambiguity is fixed; the next gap is parseable status/evidence.

## Top Recommended Actions

| Rank | Action | Why Now | Dependencies | Success Criteria |
| --- | --- | --- | --- | --- |
| 1 | Execute [[Engineering System Flaw Remediation Plan]] Phase 02. | Semantic validation needs parseable source fields before scripts can enforce status truth. | Completed Phase 00/01 | Task, risk, debt, blocker, improvement, and lesson notes have documented machine-readable fields. |
| 2 | Execute [[Engineering System Flaw Remediation Plan]] Phase 03 and Phase 04. | Completed work needs evidence links, and the checker should enforce the next governance layer. | Phase 02 | Evidence ledger exists and `check_obsidian_vault.ps1` validates the first semantic rules. |
| 3 | Execute TASK-001 using [[VoiceCallRuntime Refactor Plan]]. | It unlocks call lease, media, terminal, and diagnostics isolation. | [[Architecture Refactor Plan Index]], [[ADR-004]] | Coordinator contracts and characterization tests exist. |
| 4 | Execute TASK-004 diagnostics taxonomy early. | Fixes must stop guessing whether failures are Firebase, permission, ICE, TURN, media, or UI. | [[CallDiagnosticsRecorder]] | Failed calls export categorized timeline. |
| 5 | Execute TASK-002 using [[Firebase Lease Management Refactor Plan]]. | False busy blocks core call reliability. | TASK-001, [[ADR-005]] | Stale locks repair once; live locks stay protected. |
| 6 | Execute TASK-012 update validation tests. | Old builds must not survive incompatible backend changes. | [[Version And Updates]], [[Release Gates]] | Old/current/newer tests pass. |

## Do Not Prioritize Yet

- Broad visual redesign before call state ownership is stable.
- Making Appium a hard gate before the smoke flow is repeatable.
- Adding new Firebase paid services because Spark/free-tier remains a hard constraint.
- Deleting old runtime paths before characterization tests exist.

## Next-Action Generation Rule

After every completed task:

1. Update [[Lessons Learned]].
2. Update [[Project Metrics]] if counts or readiness changed.
3. Update [[Improvement Backlog]] if a recurring pattern appears.
4. Update this note with the next three most valuable actions.
5. Update [[Project Memory]] only when durable project facts change.
