# Recommended Next Actions

Last updated: 2026-06-03

## Purpose

This note continuously converts current project state, risks, debt, lessons, and metrics into recommended next actions.

Related: [[Project Metrics]], [[Improvement Backlog]], [[Optimization Opportunities]], [[Critical Path]], [[Recommended Next Actions]], [[Project Memory]].

## Current Recommendation Summary

Use [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) as the current evidence lock for the call/presence/update/diagnostics failure cluster. Seven mitigations are complete: late voice signaling frames after terminal rooms no longer become crash records, Firebase terminal room writes no longer depend on callee inbox rows, Android SAF document handles no longer break diagnostics export, stale raw-online backend presence no longer seeds or starts user-facing actions, failed call setup diagnostics now include Firebase room status timelines, update checks no longer report stale Remote Config policy as "up to date," and Phase 05 presence routing now uses shared `online + heartbeat + state` freshness for UI Connect and auto-recovery. Phase 08 added targeted local regression coverage around call failure messages, failed call surfaces, compact video dock behavior, terminal write ordering, already-terminal cleanup, and session-owned Firebase presence. The next app work should finish media lifecycle/ICE diagnostics, repair local Drift/sqlite test harness coverage for app-close runtime proof, and tie release artifacts to deployed Remote Config evidence before more release builds are trusted.

## Top Recommended Actions

| Rank | Action | Why Now | Dependencies | Success Criteria |
| --- | --- | --- | --- | --- |
| 1 | Enforce Firebase terminal room state as the call terminal source of truth across every runtime path. | Late-frame crash pollution and one `endCall` permission-denied path are mitigated, but terminal ownership still needs full reconciliation hardening. | TASK-003, [[Call State Machine]], [[CallTerminalReconciler]] | Remote terminal room ends local voice calls; late frames stay diagnostic-only; no peer remains active after terminal room state. |
| 2 | Continue TASK-004 diagnostics taxonomy for ICE, route, and media lifecycle. | Room status timelines are now captured, but failed call exports still need stronger ICE candidate, selected route, track, renderer, and first-frame evidence. | [[CallDiagnosticsRecorder]] | Failed calls export categorized ICE/media lifecycle evidence without raw SDP or candidate strings. |
| 3 | Repair or route around local Drift/sqlite native-asset test harness failures. | `friend_flow_test.dart` currently fails before runtime logic on local Windows, blocking full app-close/session-owned presence proof. | [[Test Strategy]], [[Presence Management]] | The full friend-flow runtime suite can run locally or equivalent CI evidence is attached to TASK-006. |
| 4 | Add release evidence for deployed Remote Config manifests. | Code now detects stale release policy, but old clients can only prompt after Remote Config actually advertises the new build. | [[Version And Updates]], [[Release Gates]] | Each release records artifact version/build/channel plus the deployed `rain_release_manifest_v1` value or an explicit skipped-deploy reason. |

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
