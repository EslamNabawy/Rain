# Recommended Next Actions

Last updated: 2026-06-03

## Purpose

This note continuously converts current project state, risks, debt, lessons, and metrics into recommended next actions.

Related: [[Project Metrics]], [[Improvement Backlog]], [[Optimization Opportunities]], [[Critical Path]], [[Recommended Next Actions]], [[Project Memory]].

## Current Recommendation Summary

Use [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) as the current evidence lock for the call/presence/update/diagnostics failure cluster. Three mitigations are complete: late voice signaling frames after terminal rooms no longer become crash records, Firebase terminal room writes no longer depend on callee inbox rows, and Android SAF document handles no longer break diagnostics export. The next app work should complete terminal-state ownership, presence freshness unification, and update metadata validation before more release builds are trusted.

## Top Recommended Actions

| Rank | Action | Why Now | Dependencies | Success Criteria |
| --- | --- | --- | --- | --- |
| 1 | Enforce Firebase terminal room state as the call terminal source of truth across every runtime path. | Late-frame crash pollution and one `endCall` permission-denied path are mitigated, but terminal ownership still needs full reconciliation hardening. | TASK-003, [[Call State Machine]], [[CallTerminalReconciler]] | Remote terminal room ends local voice calls; late frames stay diagnostic-only; no peer remains active after terminal room state. |
| 2 | Unify presence decisions through one availability snapshot. | The JSON proves `fetchIdentity` can report online within milliseconds of watcher expiry reporting offline. | [[Presence Management]], TASK-006 | Connect, call, and request notification guards cannot disagree for the same peer/action. |
| 3 | Execute TASK-004 diagnostics taxonomy early. | The export has empty failure taxonomy, zero Firebase counters, and no call room/media timeline. | [[CallDiagnosticsRecorder]] | Failed calls export categorized timeline and non-zero operation summaries. |
| 4 | Execute TASK-012 update validation tests with real platform build numbers. | The evidence shows Windows build 7 and Android build 1007 while Remote Config template says Android latest build 7. | [[Version And Updates]], [[Release Gates]] | Old/current/newer tests pass for Android and Windows artifact numbering. |

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
