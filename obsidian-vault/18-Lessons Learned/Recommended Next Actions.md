# Recommended Next Actions

Last updated: 2026-06-03

## Purpose

This note continuously converts current project state, risks, debt, lessons, and metrics into recommended next actions.

Related: [[Project Metrics]], [[Improvement Backlog]], [[Optimization Opportunities]], [[Critical Path]], [[Recommended Next Actions]], [[Project Memory]].

## Current Recommendation Summary

Use [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) as the current evidence lock for the call/presence/update/diagnostics failure cluster. The first diagnostic-quality mitigation is complete: late voice signaling frames after terminal rooms no longer become crash records. The next app work should reproduce and fix Firebase end-call permission denial, terminal-state ownership, presence freshness races, and Android diagnostics export before more release builds are trusted.

## Top Recommended Actions

| Rank | Action | Why Now | Dependencies | Success Criteria |
| --- | --- | --- | --- | --- |
| 1 | Reproduce Android `signaling.endCall` permission denial in Firebase emulator and fix the minimal denied rule path. | The screenshot proves valid end-call cleanup can be denied, which can leave remote peers active and stale locks behind. | [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md), [[Rules Strategy]], [[Emulator Coverage]] | Caller and callee can end ringing/accepted/negotiating/connected calls and matching locks are cleaned. |
| 2 | Enforce Firebase terminal room state as the call terminal source of truth. | Late-frame crash pollution is mitigated, but terminal ownership still needs full reconciliation hardening. | TASK-003, [[Call State Machine]], [[CallTerminalReconciler]] | Remote terminal room ends local voice calls; late frames stay diagnostic-only; no peer remains active after terminal room state. |
| 3 | Unify presence decisions through one availability snapshot. | The JSON proves `fetchIdentity` can report online within milliseconds of watcher expiry reporting offline. | [[Presence Management]], TASK-006 | Connect, call, and request notification guards cannot disagree for the same peer/action. |
| 4 | Fix Android diagnostics export path handling. | The screenshot proves `/document/1282` is treated as a filesystem path and blocks reports from the affected device. | [[Diagnostics Sanitization]], [[CallDiagnosticsRecorder]] | Android export succeeds and `/document/...` regression test passes. |
| 5 | Execute TASK-004 diagnostics taxonomy early. | The export has empty failure taxonomy, zero Firebase counters, and no call room/media timeline. | [[CallDiagnosticsRecorder]] | Failed calls export categorized timeline and non-zero operation summaries. |
| 6 | Execute TASK-012 update validation tests with real platform build numbers. | The evidence shows Windows build 7 and Android build 1007 while Remote Config template says Android latest build 7. | [[Version And Updates]], [[Release Gates]] | Old/current/newer tests pass for Android and Windows artifact numbering. |

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
