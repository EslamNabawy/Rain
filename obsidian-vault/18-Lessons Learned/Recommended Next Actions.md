# Recommended Next Actions

Last updated: 2026-06-03

## Purpose

This note continuously converts current project state, risks, debt, lessons, and metrics into recommended next actions.

Related: [[Project Metrics]], [[Improvement Backlog]], [[Optimization Opportunities]], [[Critical Path]], [[Recommended Next Actions]], [[Project Memory]].

## Current Recommendation Summary

Use [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) as the current evidence lock for the call/presence/update/diagnostics failure cluster. Seven mitigations are complete: late voice signaling frames after terminal rooms no longer become crash records, Firebase terminal room writes no longer depend on callee inbox rows, Android SAF document handles no longer break diagnostics export, stale raw-online backend presence no longer seeds or starts user-facing actions, failed call setup diagnostics now include Firebase room status timelines, update checks no longer report stale Remote Config policy as "up to date," and Phase 05 presence routing now uses shared `online + heartbeat + state` freshness for UI Connect and auto-recovery. Phase 08 added targeted local regression coverage around call failure messages, failed call surfaces, compact video dock behavior, terminal write ordering, already-terminal cleanup, and session-owned Firebase presence.

Use [AUTHENTICATION_AUDIT.md](../../AUTHENTICATION_AUDIT.md) and [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md) as the current evidence lock for logout/account lifecycle/splash/navigation failures. Phase 1, Phase 2, Phase 3, and Phase 4 have reduced stale cached identity, logout/reset, split startup-readiness, and route-local splash risk; the next app work should harden protected route readiness so settings/search/friend routes cannot render protected content while auth/runtime startup is unresolved.

Auth Phase 1 progress 2026-06-03: cached Drift identity is now backend-validated before signed-in restoration. Deleted backend accounts and uid mismatches clear local session, and login/register save local identity only after backend identity/presence writes. Auth Phase 2 progress 2026-06-03: logout clears local session before best-effort backend sign-out, including failed sign-out and logout-after-app-exit shutdown cases. Auth Phase 3 progress 2026-06-03: `AppStartupState` centralizes update/session/runtime/router readiness and tests cover every startup phase. Auth Phase 4 progress 2026-06-03: `RainApp` globally replaces routed content with `RainStartupSurface` during blocked startup phases, and tests prove the navigation shell is absent. The next auth/startup work is navigation readiness.

## Top Recommended Actions

| Rank | Action | Why Now | Dependencies | Success Criteria |
| --- | --- | --- | --- | --- |
| 1 | Implement protected navigation readiness. | The global visual startup gate now blocks app chrome, but protected sibling route readiness still needs hardening so stale route state cannot surface protected content during unresolved auth/runtime phases. | Phase 4 global splash architecture, [NAVIGATION_INITIALIZATION_AUDIT.md](../../NAVIGATION_INITIALIZATION_AUDIT.md), TD-022 | Settings/search/friend routes cannot render protected content while startup is loading, failed, session-expired, or update-blocked. |
| 2 | Enforce Firebase terminal room state as the call terminal source of truth across every runtime path. | Late-frame crash pollution and one `endCall` permission-denied path are mitigated, but terminal ownership still needs full reconciliation hardening. | TASK-003, [[Call State Machine]], [[CallTerminalReconciler]] | Remote terminal room ends local voice calls; late frames stay diagnostic-only; no peer remains active after terminal room state. |
| 3 | Continue TASK-004 diagnostics taxonomy for ICE, route, and media lifecycle. | Room status timelines are now captured, but failed call exports still need stronger ICE candidate, selected route, track, renderer, and first-frame evidence. | [[CallDiagnosticsRecorder]] | Failed calls export categorized ICE/media lifecycle evidence without raw SDP or candidate strings. |
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
