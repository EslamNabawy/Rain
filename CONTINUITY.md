# Rain Continuity

This file must survive across future AI sessions.

Every future session must read this file before starting non-trivial work.

## Current Goal

Execute the auth/account/startup/splash/navigation remediation roadmap phase by phase without another audit. The current evidence source is `ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md` plus its linked investigation documents.

## Current Phase

Auth/startup remediation - Phase 6 complete. Next auth/startup work is Phase 5 from the root roadmap: account deletion workflow, or Phase 09 release-gate integration after account deletion is accepted/deferred.

## Completed Phases

- [x] Phase 0 - Operating Model Foundation
- [x] Phase 1 - Obsidian Vault Bootstrap
- [x] Phase 2 - Repository Discovery
- [x] Phase 3 - Project Memory Generation
- [x] Phase 4 - Audit to Roadmap Conversion
- [x] Phase 5 - Technical Debt System
- [x] Phase 6 - Risk and Blocker Intelligence
- [x] Phase 7 - Architecture Refactor Planning
- [x] Phase 8 - Self-Improvement Engine
- [ ] Phase 9 - Codex Automation Layer
- [ ] Phase 10 - Continuous Project Evolution

## Completed Auth/Startup Remediation Phases

- [x] Phase 1 - Authentication source of truth: cached Drift identity is backend-validated before signed-in restoration; deleted backend accounts and uid mismatches clear local session; login/register write backend identity/presence before local identity cache.
- [x] Phase 2 - Deterministic logout/reset: runtime logout clears local session before best-effort backend sign-out; failed Firebase sign-out no longer preserves cached identity; logout after a prior app-exit shutdown still clears local session; authenticated session teardown runs from a `finally` path.
- [x] Phase 3 - Startup State Machine: app startup now has a typed `AppStartupState`/`AppStartupPhase` provider composing update check, identity validation, runtime startup, session-expired reset, and router readiness; `RootScreen` and shell navigation consume that one state; protected sibling routes redirect to root while startup is unresolved.
- [x] Phase 4 - Global Splash Architecture
- [x] Phase 5 - Navigation Readiness
- [x] Phase 6 - State Lifecycle Hardening

## Active Work

- 2026-06-04 registration permission-denied investigation is complete for the supplied create-account screenshot. Live Firebase checks showed current rules allow fresh random registration, while `/users/eslam` already exists. The app now maps RTDB permission-denied during registration to an account conflict message, rolls back the just-created Auth user only before the durable user row exists, signs out without caching Drift identity on backend-save failures, and includes targeted auth/onboarding regression tests.
- 2026-06-04 terminal/media-write and diagnostics-export follow-up is implemented and awaiting validation. The supplied Windows diagnostic showed `signaling.writeVoiceOffer` throwing after the Firebase room was already `ended`; runtime now preflights terminal-sensitive media signaling sends before `accept`, `offer`, `answer`, and `mute` writes. Firebase rules contract tests now assert voice terminal fields are writable by either participant. Diagnostics export now reports a real fallback JSON file when Android returns a content URI or `/document/...` picker handle. File-transfer views now reset speed samples when the peer lane is not connected.
- `ROOT_CAUSE_ANALYSIS.md` was created on 2026-06-03 from the supplied Windows diagnostics JSON, Android screenshot, and manual failure report. It is the current evidence lock for call/presence/update/diagnostics failures.
- The RCA confirmed these root-cause clusters: split call terminal authority, Android `signaling.endCall` permission denial, presence freshness races, terminal inbox exposure before cleanup, Android diagnostics export path failure, and update build-number inconsistency.
- First mitigation from the RCA execution is complete: late voice signaling states after terminal Firebase rooms are recorded as `late_frame_ignored` events only and no longer overwrite crash diagnostics as `lastCrash`.
- Second mitigation from the RCA execution is complete: Firebase `endCall` now writes the terminal `voiceCalls/{callId}` room state before any best-effort inbox mirror update, so an already-cleaned `voiceCallInboxes/{callee}/{callId}` row can no longer cause a permission-denied terminal cleanup failure.
- Third mitigation from the RCA execution is complete: diagnostics export treats Android SAF `/document/...` and `/tree/...` handles as platform-managed picker outputs and no longer opens them as raw filesystem paths.
- Fourth mitigation from the RCA execution is complete: backend presence is resolved from `online + lastHeartbeat` with a shared 30 second runtime freshness window before local friend seeding, direct connect, connection-request routing, or voice/video call start. Stale raw-online records are treated as offline and logged as `backend_presence_stale_resolved_offline`.
- Fifth mitigation from the RCA execution is complete: call setup diagnostics now retain a per-call Firebase room status timeline and terminal-room failure reconciliation emits `VoiceCallDiagnostics`, so failed setup exports can show ringing/accepted/failed transitions instead of an empty room timeline.
- Sixth mitigation from the RCA execution is complete: update checks now classify stale Remote Config release policy as `remotePolicyOutdated` instead of `current`, same-version minimum build upgrades become required updates, and optional update prompts render from the root app surface before login/home.
- Seventh mitigation from the RCA execution is complete: Phase 05 presence/session freshness now carries session metadata through backend identity snapshots, treats `presence.state != online` as offline, blocks UI Connect and auto-recovery through the shared fresh-presence resolver, and preserves `presenceExpired` as a terminal peer intent until a later successful explicit reconnect.
- Phase 08 Regression Test Expansion is complete: targeted local tests now cover stable failure messages for WebRTC/Firebase/network call failures, failed call suite state and compact video dock behavior, terminal-room-before-session-hangup ordering, failed-media terminal write before session disposal, already-terminal cleanup classification, and session-owned Firebase presence contracts.
- Phase 09 local pre-artifact release gate evidence is recorded: `dart pub get`, analyze, full Melos tests, Firebase JSON parsing, Firebase Functions tests, Firebase emulator integration tests, and Obsidian vault validation all passed on 2026-06-03. Cloud artifact build and release-page proof remain the hard-gate completion step.
- Auth/startup remediation Phase 1 is complete on 2026-06-03. `apps/rain/lib/application/state/identity_providers.dart` validates cached identity through backend account existence and current auth uid before publishing signed-in state, clears local session on missing/deleted/mismatched backend identity, and saves local identity only after backend identity/presence writes during login/register. `apps/rain/test/auth_identity_source_of_truth_test.dart` covers backend deletion, uid mismatch, and backend profile refresh.
- Auth/startup remediation Phase 2 is complete on 2026-06-03. `RainRuntimeController.logOut()` now guarantees local Drift session clearing before best-effort backend sign-out, even if `adapter.signOut()` fails or a previous app-exit shutdown already owns `_shutdownFuture`. `RuntimeController.logOut()` now ends the authenticated session from `finally`; Phase 6 replaced the earlier broad provider invalidation list with generation-scoped providers. `apps/rain/test/runtime_startup_test.dart` covers failed sign-out and logout-after-app-exit shutdown.
- Auth/startup remediation Phase 3 is complete on 2026-06-03. `apps/rain/lib/application/state/app_startup_state.dart` centralizes startup phases, `RootScreen` and `appShellReadinessProvider` now derive readiness from it, router refresh listens to startup state, and `apps/rain/test/app_routes_test.dart` covers update loading, required update, session validation, signed-out, runtime loading, ready, and session-expired phases.
- Auth/startup remediation Phase 4 is complete on 2026-06-03. `RainApp` now places `RainStartupSurface` above the routed child through `MaterialApp.router.builder` whenever `AppStartupState.blocksRoutedSurface` is true, so loading, required-update, failed, and session-expired states do not insert `RainNavigationShell` or normal app chrome. `RootScreen` reuses the same startup surface for route-local consistency, and route tests prove no shell/navigation exists while startup is blocked.
- Auth/startup remediation Phase 5 is complete on 2026-06-03. `AppStartupState.canRenderProtectedRoutes` and `usesRoutedAppShell` now make the protected route contract explicit; `RainApp` renders signed-out auth through a standalone Navigator/Overlay instead of the app shell; settings/search/friend pages use `_ProtectedRouteGate`; router redirects unresolved protected paths to `/`; tests prove protected routes do not render while runtime is loading or signed out.
- Auth/startup remediation Phase 6 is complete on 2026-06-03. `AuthenticatedSession.sessionGeneration` is the account-scope boundary, runtime reuse requires matching username and generation, account-owned providers watch the active generation, logout ends the authenticated session instead of relying on a broad manual invalidation list, and regression tests cover generation changes plus recent/search/message state reset.
- Local Windows Drift/sqlite app-test invocation is repaired for isolated Rain app tests: `scripts/run_rain_app_test.ps1` runs tests from `apps/rain`, the targeted stale-presence friend-flow case passed, and full `friend_flow_test.dart` passed with 120 passing tests and 10 skipped legacy control-channel cases.
- Phase 0 deliverables are complete.
- Phase 1 vault structure is complete.
- Phase 2 repository discovery is documented in `obsidian-vault/03-Architecture/Current Architecture.md`.
- Phase 3 primary AI memory is documented in `obsidian-vault/AI-Memory/Project Memory.md`.
- Phase 4 roadmap artifacts are documented in `obsidian-vault/01-Roadmap/`.
- Phase 5 technical debt artifacts are documented in `obsidian-vault/11-Technical Debt/`.
- Phase 6 risk and blocker artifacts are documented in `obsidian-vault/12-Risks/` and `obsidian-vault/14-Blockers/`.
- Phase 7 architecture refactor plans are documented in `obsidian-vault/03-Architecture/`.
- Phase 8 self-improvement artifacts are documented in `obsidian-vault/18-Lessons Learned/`.
- Repository-wide `AGENTS.md` now requires pre-implementation reading of project memory, roadmap, debt, risk, and blockers, plus a post-code Obsidian update gate.
- `obsidian-vault/01-Roadmap/Engineering System Flaw Remediation Plan.md` has been created to fix flaws in the current documentation operating system before Phase 9 automation.
- Engineering System Flaw Remediation Phase 00 and Phase 01 are complete: canonical source views are documented, duplicate note titles were removed, and the vault checker now fails on uncontrolled duplicate note titles.
- Continue remediation with one logical phase per commit. Do not perform another audit unless explicitly requested.

## Known Risks

- The repository already contains prior documentation and an expanded Obsidian vault; future phases must avoid duplicating or contradicting it.
- The active maintained repo must remain separate from `D:\old project\Rain`.
- The project has high-risk runtime areas: Firebase signaling, WebRTC calls, presence, update checks, diagnostics, and release workflows.
- Future phases must avoid overbuilding before discovery.
- The vault still has manual-only governance gaps around status schemas, validation evidence, stale notes, and generated metrics; full Phase 9 automation should wait until those are structured.

## Known Blockers

- BLK-010 remains open only for the account deletion workflow and any explicit release-gate acceptance, because authentication source of truth, deterministic logout, startup state, global splash, protected navigation, and session lifecycle hardening are implemented and validated.

## Next Recommended Action

Run validation for the 2026-06-04 terminal/media-write, diagnostics-export, rules-contract, and file-transfer-view fixes. After that, implement or explicitly defer the remaining account deletion workflow from `ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md`, then add the auth/startup regression set to the hard release gate.

## Future Population Areas

Future phases will populate:

- Architecture
- Risks
- Roadmaps
- Tasks
- Metrics
- Knowledge graph
- Self-improvement data
- Lessons learned
- Technical debt
- Blockers
- ADRs
