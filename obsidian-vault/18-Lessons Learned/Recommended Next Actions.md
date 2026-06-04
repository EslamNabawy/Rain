# Recommended Next Actions

Last updated: 2026-06-04

## Purpose

This note continuously converts current project state, risks, debt, lessons, and metrics into recommended next actions.

Related: [[Project Metrics]], [[Improvement Backlog]], [[Optimization Opportunities]], [[Critical Path]], [[Recommended Next Actions]], [[Project Memory]].

## Current Recommendation Summary

Governance update 2026-06-04: the root operating manual and Obsidian AI operating notes now encode the Rain Autonomous Engineering System source-of-truth priority order, reality-enforcement rule, and workflow node state machine. The vault now also has [[Scenario Intelligence Agent]], [[System Model]], [[State Graph]], [[Business Rule Graph]], [[Assumption Register]], [[Failure Graph]], and [[Scenario Coverage Matrix]] so testing/intelligence agents can generate scenarios from explicit models and track coverage status instead of ad hoc test ideas. The next governance improvement remains [[Engineering System Flaw Remediation Plan]] Phase 02: machine-readable status schemas, followed by a validation evidence ledger.

Use [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) as the current evidence lock for the call/presence/update/diagnostics failure cluster. Mitigations completed so far: late received voice signaling frames after terminal rooms no longer become crash records, Firebase terminal room writes no longer depend on callee inbox rows, Android SAF document handles no longer get opened as raw filesystem paths, stale raw-online backend presence no longer seeds or starts user-facing actions, failed call setup diagnostics now include Firebase room status timelines, update checks no longer report stale Remote Config policy as "up to date," Phase 05 presence routing now uses shared `online + heartbeat + state` freshness for UI Connect and auto-recovery, 2026-06-04 terminal-sensitive local media signaling writes now preflight terminal rooms before `writeVoiceOffer`/`writeVoiceAnswer`, and 2026-06-04 terminal call cleanup now publishes failed/idle UI state before bounded WebRTC/session cleanup. Diagnostics export now also creates a real fallback JSON file for Android content URI or `/document/...` picker handles. Phase 08 plus the terminal cleanup pass added targeted local regression coverage around call failure messages, failed call surfaces, compact video dock behavior, terminal write ordering, already-terminal cleanup, state-before-cleanup, bounded cleanup, file-transfer guard recovery after failed calls, and session-owned Firebase presence.

Use [AUTHENTICATION_AUDIT.md](../../AUTHENTICATION_AUDIT.md) and [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md) as the current evidence lock for logout/account lifecycle/splash/navigation failures. Phase 1 through Phase 6 have reduced stale cached identity, logout/reset, split startup-readiness, route-local splash risk, protected-route readiness risk, and account-scoped provider lifecycle leakage. 2026-06-04 account deletion is now implemented and release-gate proven: Settings prompts for confirmation and password reauth; backend deletion tombstones identity and deletes Firebase Auth last; bad-password reauth preserves the active session; destructive partial failures clear local session; login/upsert/search writes cannot recreate missing or tombstoned backend accounts after Auth succeeds. Auth lifecycle release-gate integration and Firebase emulator account-deletion proof passed in `Build Rain Apps` run 26957834309 at `883886a`.

Auth Phase 1 progress 2026-06-03: cached Drift identity is now backend-validated before signed-in restoration. Deleted backend accounts and uid mismatches clear local session, and login/register save local identity only after backend identity/presence writes. Auth Phase 2 progress 2026-06-03: logout clears local session before best-effort backend sign-out, including failed sign-out and logout-after-app-exit shutdown cases. Auth Phase 3 progress 2026-06-03: `AppStartupState` centralizes update/session/runtime/router readiness and tests cover every startup phase. Auth Phase 4 progress 2026-06-03: `RainApp` globally replaces routed content with `RainStartupSurface` during blocked startup phases, and tests prove the navigation shell is absent. Auth Phase 5 progress 2026-06-03: protected routes use explicit readiness gates and signed-out auth renders outside the shell. Auth Phase 6 progress 2026-06-03: `AuthenticatedSession.sessionGeneration` scopes runtime/provider ownership and tests prove account state resets at session boundaries.

Auth account deletion progress 2026-06-04: `SignalingAdapter` and `FirebaseSignalingAdapter` now expose reauthentication and deletion, Settings exposes the delete flow, runtime/provider teardown handles destructive and non-destructive failures separately, login refuses missing/tombstoned backend identity after Auth succeeds, and local targeted plus full Melos validation passed.

Registration conflict progress 2026-06-04: live Firebase rules allowed fresh random account creation, while the reported `eslam` username already existed in RTDB. Registration now converts RTDB permission-denied on account-data creation into a friendly username/account conflict, avoids caching local identity on backend-save failure, and limits Auth rollback to failures before the durable user row exists.

Terminal cleanup progress 2026-06-04: `rain-diagnostics-2026-06-04T144952-237539Z.json` showed mobile-to-PC media reached `connected`, Firebase ended as `busy`, local call cleanup stalled, file transfer was blocked by stale active-call state, and Windows shutdown did not complete. Runtime now publishes terminal state before bounded cleanup, and desktop close has bounded close/destroy plus a Windows exit fallback. The next proof is real Android-to-Windows smoke on a fresh build.

Update warning progress 2026-06-04: the missing warning was traced to release metadata equality. Installed `1.0.6+7` apps saw a `1.0.6+7` Remote Config policy, so they correctly reported `current`. The app and release manifests are now `1.0.7+8`, and `version_metadata_test.dart` proves checked-in Remote Config requires update for previous `1.0.6+7` stable/demo Android/Windows installs. The next proof is deploying Remote Config and publishing/installing fresh `1.0.7+8` artifacts.

## Top Recommended Actions

| Rank | Action | Why Now | Dependencies | Success Criteria |
| --- | --- | --- | --- | --- |
| 1 | Deploy Remote Config and publish fresh `1.0.7+8` artifacts. | The update warning fix is repository-complete, but installed apps cannot see it until Firebase Remote Config is deployed and fresh artifacts exist. | [[Version And Updates]], [[Release Gates]], BLK-004, BLK-006 | A deployed `rain_release_manifest_v1` advertises `1.0.7+8`, old `1.0.6+7` installs show the required update warning, and release evidence records commit/version/channel. |
| 2 | Run fresh Android-to-Windows device smoke for SCN-CALL-004. | The reported call/file/close regression is locally mitigated, but real WebRTC/device proof is still required. | [[Scenario Coverage Matrix]], BLK-001, BLK-002 | Mobile-to-PC voice call no longer shows stale unavailable session state, file transfer is allowed after terminal call state, Windows closes without a resident process, and diagnostics are exported if any step fails. |
| 3 | Finish Firebase terminal room source-of-truth coverage across every runtime path. | Late received frames, state-before-cleanup, bounded cleanup, and late local media signaling writes are mitigated, but full `VoiceCallRuntime` split and device-direction proof are still open. | TASK-003, [[Call State Machine]], [[CallTerminalReconciler]] | Remote terminal room ends local voice calls; late frames/writes stay diagnostic-only; no peer remains active after terminal room state. |
| 4 | Continue TASK-004 diagnostics taxonomy for ICE, route, and media lifecycle. | Room status timelines are now captured, but failed call exports still need stronger ICE candidate, selected route, track, renderer, first-frame, and cleanup-lifecycle evidence. | [[CallDiagnosticsRecorder]] | Failed calls export categorized ICE/media lifecycle evidence without raw SDP or candidate strings. |
| 5 | Add Firebase emulator proof for registration conflict cleanup if adapter seams allow it. | Account-deletion tombstone/no-recreate proof now exists in the hard gate, but registration conflict partial-write cases still need stronger release proof. | [[Authentication]], [[Rules Strategy]], TD-021 | Existing username, pre-user-row denial, and post-user-row secondary failure behavior are covered without requiring live Firebase probes. |
| 6 | Add Firebase emulator proof for online receiver request denial and quota non-consumption. | Scenario coverage still has a partially covered connection-request quota path that can burn quota or notify incorrectly if presence is stale. | [[Scenario Coverage Matrix]], [[Emulator Test Matrix]], BLK-009, BLK-003 | Online receiver denial is proven at runtime/rules level and request quota remains unchanged. |
| 7 | Close the Gap rows in [[Scenario Coverage Matrix]]. | The first applied pass found concrete gaps around newer live call locks and recursive diagnostics sanitization. | [[Scenario Coverage Matrix]], [[Emulator Test Matrix]], [[Diagnostics Sanitization]] | Gap rows are either covered by named tests or explicitly accepted with owner rationale. |
| 8 | Execute [[Engineering System Flaw Remediation Plan]] Phase 02. | Governance rules now have one written workflow, but task/risk/debt/blocker status is still prose-heavy and not machine-readable. | Completed Phase 00/01 duplicate-title cleanup, [[AI Operating Notes]] | Critical operational notes expose parseable status fields that a future validator can check. |

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
