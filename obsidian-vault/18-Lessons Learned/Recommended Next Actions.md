# Recommended Next Actions

Last updated: 2026-06-03

## Purpose

This note continuously converts current project state, risks, debt, lessons, and metrics into recommended next actions.

Related: [[Project Metrics]], [[Improvement Backlog]], [[Optimization Opportunities]], [[Critical Path]], [[Recommended Next Actions]], [[Project Memory]].

## Current Recommendation Summary

Use [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) as the current evidence lock for the call/presence/update/diagnostics failure cluster. Seven mitigations are complete: late voice signaling frames after terminal rooms no longer become crash records, Firebase terminal room writes no longer depend on callee inbox rows, Android SAF document handles no longer break diagnostics export, stale raw-online backend presence no longer seeds or starts user-facing actions, failed call setup diagnostics now include Firebase room status timelines, update checks no longer report stale Remote Config policy as "up to date," and Phase 05 presence routing now uses shared `online + heartbeat + state` freshness for UI Connect and auto-recovery. Phase 08 added targeted local regression coverage around call failure messages, failed call surfaces, compact video dock behavior, terminal write ordering, already-terminal cleanup, and session-owned Firebase presence.

Use [AUTHENTICATION_AUDIT.md](../../AUTHENTICATION_AUDIT.md) and [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md) as the current evidence lock for logout/account lifecycle/splash/navigation failures. Phase 1 through Phase 5 have reduced stale cached identity, logout/reset, split startup-readiness, route-local splash risk, and protected-route readiness risk; the next app work should harden session-scoped provider lifecycle so account-owned state cannot leak across logout/login or session-expired cycles.

Auth Phase 1 progress 2026-06-03: cached Drift identity is now backend-validated before signed-in restoration. Deleted backend accounts and uid mismatches clear local session, and login/register save local identity only after backend identity/presence writes. Auth Phase 2 progress 2026-06-03: logout clears local session before best-effort backend sign-out, including failed sign-out and logout-after-app-exit shutdown cases. Auth Phase 3 progress 2026-06-03: `AppStartupState` centralizes update/session/runtime/router readiness and tests cover every startup phase. Auth Phase 4 progress 2026-06-03: `RainApp` globally replaces routed content with `RainStartupSurface` during blocked startup phases, and tests prove the navigation shell is absent. Auth Phase 5 progress 2026-06-03: protected routes use explicit readiness gates and signed-out auth renders outside the shell. The next auth/startup work is state lifecycle hardening.

## Top Recommended Actions

| Rank | Action | Why Now | Dependencies | Success Criteria |
| --- | --- | --- | --- | --- |
| 1 | Implement session lifecycle hardening. | Startup and protected-route gates now block app chrome/content, but account-owned providers still need scoped disposal/recreation proof across logout/login, session-expired reset, and user-switch cycles. | Phase 5 navigation readiness, [STATE_MANAGEMENT_FAILURE_ANALYSIS.md](../../STATE_MANAGEMENT_FAILURE_ANALYSIS.md), TD-021, TD-022 | Repeated login/logout and session-expired tests prove account state cannot leak between users or survive a reset. |
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
