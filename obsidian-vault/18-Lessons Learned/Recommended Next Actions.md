# Recommended Next Actions

Last updated: 2026-06-03

## Purpose

This note continuously converts current project state, risks, debt, lessons, and metrics into recommended next actions.

Related: [[Project Metrics]], [[Improvement Backlog]], [[Optimization Opportunities]], [[Critical Path]], [[Recommended Next Actions]], [[Project Memory]].

## Current Recommendation Summary

The next implementation work should not be broad UI polish. The highest-leverage path is to stabilize call runtime ownership and diagnostics first.

## Top Recommended Actions

| Rank | Action | Why Now | Dependencies | Success Criteria |
| --- | --- | --- | --- | --- |
| 1 | Execute TASK-001 using [[VoiceCallRuntime Refactor Plan]]. | It unlocks call lease, media, terminal, and diagnostics isolation. | [[Architecture Refactor Plan Index]], [[ADR-004]] | Coordinator contracts and characterization tests exist. |
| 2 | Execute TASK-004 diagnostics taxonomy early. | Fixes must stop guessing whether failures are Firebase, permission, ICE, TURN, media, or UI. | [[CallDiagnosticsRecorder]] | Failed calls export categorized timeline. |
| 3 | Execute TASK-002 using [[Firebase Lease Management Refactor Plan]]. | False busy blocks core call reliability. | TASK-001, [[ADR-005]] | Stale locks repair once; live locks stay protected. |
| 4 | Execute TASK-012 update validation tests. | Old builds must not survive incompatible backend changes. | [[Version And Updates]], [[Release Gates]] | Old/current/newer tests pass. |
| 5 | Execute TASK-005 rules emulator coverage. | Permission denied regressions waste device-testing cycles. | [[Rules Strategy]], [[Emulator Coverage]] | Critical RTDB allow/deny matrix passes. |
| 6 | Execute TASK-023 offline request guardrails. | Online direct connect must not spend offline request quota. | [[Presence Management Refactor Plan]], [[ADR-006]] | Every blocked action shows deterministic message. |

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

