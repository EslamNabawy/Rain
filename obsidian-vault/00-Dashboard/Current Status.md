# Current Status

Last updated: 2026-06-04

## Repository State

- Active working repo: `C:\Users\eslam\OneDrive\Desktop\GoodStuff\Rain`
- Current branch observed during audit: `dev`
- Branch state observed: synced with `origin/dev` after pushing commits through `883886a2e81ee370e3641ddcefce8d62942a3566`; root `.obsidian/` remains local workspace metadata and is intentionally untracked.
- The old project folder `D:\old project\Rain` must not be edited.

## Working Areas

- Flutter app structure exists for Android and Windows.
- Riverpod state management is used.
- Firebase Auth, Realtime Database, and Remote Config are integrated.
- Drift local database exists.
- WebRTC data and media layers exist through `peer_core`.
- Automated tests exist across app, `rain_core`, `protocol_brain`, and `peer_core`.
- GitHub workflows exist for CI, merge gates, release builds, and direct test downloads.

## Unstable Areas

- Voice/video calls still have reported PC-to-mobile failures.
- Call state can be misleading because signaling, lock, and media failures collapse into similar UI messages.
- Presence can be stale after app close or network loss.
- Update checks require Remote Config to be deployed after each release; stale policy is now visible but still blocks reliable old-client discovery if not deployed.
- File transfer implementation can cause allocation and I/O pressure for large files.
- 2026-06-03 evidence review is captured in [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md). It confirms call terminal authority conflicts, Android `signaling.endCall` permission denial, presence freshness races, stale terminal inbox exposure, Android diagnostics export failure, and update build-number inconsistency.
- 2026-06-03 mitigation: late voice signaling frames after terminal room cleanup no longer write to crash diagnostics; they remain structured call events only. This improves report quality but does not yet fix the remaining call/presence/update failures.
- 2026-06-03 mitigation: Firebase `endCall` now writes terminal room state independently from callee inbox mirror cleanup. Emulator regression coverage proves an already-cleaned `voiceCallInboxes` row no longer blocks room terminal status or lock release.
- 2026-06-03 mitigation: Android diagnostics export now treats SAF `/document/...` and `/tree/...` picker handles as platform-managed outputs, preventing the reported `PathNotFoundException` path from being opened through `dart:io`.
- 2026-06-03 mitigation: runtime action gates now resolve backend presence with one 30 second `online + lastHeartbeat` freshness window before friend seeding, direct Connect, connection-request routing, or voice/video call start.
- 2026-06-03 mitigation: failed voice/video setup diagnostics now preserve Firebase room status timelines and emit diagnostics from terminal-room failure reconciliation.
- 2026-06-03 mitigation: update checks now report stale Remote Config policy as `remotePolicyOutdated`, same-version minimum-build upgrades are required updates, and optional update prompts render from the root app surface before login/home.
- 2026-06-03 Phase 09 local pre-artifact release gate passed `dart pub get`, analyze, full Melos tests, Firebase JSON parsing, Firebase Functions tests, Firebase emulator integration tests, and Obsidian vault validation.
- 2026-06-04 cloud hard-gate/artifact proof passed for pushed `origin/dev` SHA `d58b7b5` in `Build Rain Apps` run 26931788461. The run passed the hard release gate, Android v7/v8-v9 APK builds, Windows demo portable build, and published pre-release `rain-test-107-1`. This earlier proof was superseded for account-deletion/scenario-gate work by run 26957834309 at `883886a`.
- 2026-06-04 auth scenario gate integration: hard release workflows now run explicit `SCN-AUTH-001` through `SCN-AUTH-004` tests, run Obsidian vault validation, and the Firebase emulator runner includes account-deletion tombstone/no-recreate proof. Local emulator integration passed, and cloud proof passed in `Build Rain Apps` run 26957834309 for pushed `dev` SHA `883886a2e81ee370e3641ddcefce8d62942a3566`.
- 2026-06-03 auth/startup investigation is captured in [AUTHENTICATION_AUDIT.md](../../AUTHENTICATION_AUDIT.md), [ACCOUNT_LIFECYCLE_ANALYSIS.md](../../ACCOUNT_LIFECYCLE_ANALYSIS.md), [STARTUP_SEQUENCE_ANALYSIS.md](../../STARTUP_SEQUENCE_ANALYSIS.md), [SPLASH_SCREEN_INVESTIGATION.md](../../SPLASH_SCREEN_INVESTIGATION.md), [NAVIGATION_INITIALIZATION_AUDIT.md](../../NAVIGATION_INITIALIZATION_AUDIT.md), and [STATE_MANAGEMENT_FAILURE_ANALYSIS.md](../../STATE_MANAGEMENT_FAILURE_ANALYSIS.md). Correlated finding: local Drift identity, Firebase Auth, RTDB user profile, runtime state, and router state are separate truths; deleted backend account data can be recreated from local identity during runtime startup.
- 2026-06-03 auth Phase 1 mitigation: Drift identity is now restored only after backend validation confirms the cached username still exists and belongs to the current auth uid. Deleted backend accounts and uid mismatches clear local session data before signed-in state is published; register/login save local identity only after backend identity/presence writes succeed.
- 2026-06-03 auth Phase 2 mitigation: logout now clears local Drift session data before best-effort backend sign-out, ignores backend sign-out failure after local clear, handles logout after a previous app-exit shutdown, and ends authenticated session state from a `finally` path. Protected-route readiness and session-scoped provider architecture were completed in later phases.
- 2026-06-03 auth Phase 3 mitigation: startup readiness now has one typed state machine. `AppStartupState` drives root screen rendering, shell navigation visibility, and router refresh/redirect logic for update loading, required update, session validation, signed-out, runtime loading, ready, session-expired, and failed states.
- 2026-06-03 auth Phase 4 mitigation: `RainApp` now owns a global `RainStartupSurface` above routed content. Loading, required-update, failed, and session-expired phases do not insert `RainNavigationShell`, bottom navigation, or rail, and `RootScreen` reuses the same surface for route-local consistency. Protected-route hardening and session-scoped provider architecture were completed in later phases.
- 2026-06-03 auth Phase 5 mitigation: protected navigation readiness is now explicit. Settings/search/friend routes cannot render protected content until startup is ready, stale protected paths redirect to `/`, signed-out auth renders outside the app shell with a standalone Navigator/Overlay, and route tests cover runtime-loading and signed-out protected-route attempts.
- 2026-06-03 auth Phase 6 mitigation: state lifecycle hardening is complete. `AuthenticatedSession.sessionGeneration` is the account-scope boundary, runtime/controller reuse requires matching username and generation, account-scoped providers reset on session end/change, and tests cover generation changes plus recent/search/message state reset.
- 2026-06-04 auth account deletion mitigation: Settings now exposes first-class delete account behind confirmation and password reauth. Backend cleanup tombstones identity, removes search/mirror data where authorized, deletes Firebase Auth last, and clears local session after destructive work starts. Bad-password reauth does not clear the active session. Login/upsert/search writes cannot recreate missing or tombstoned backend identity after Auth succeeds. Full Melos analyze/test passed locally; hard release-gate integration and Firebase emulator account-deletion proof passed in `Build Rain Apps` run 26957834309, which published `rain-test-108-1`.

## Documentation Status

This vault is now the main knowledge base. Older docs remain in `docs/`, but future source-of-truth updates should be mirrored here.

Phase 1 vault bootstrap, Phase 2 repository discovery, Phase 3 project memory generation, Phase 4 audit-to-roadmap conversion, Phase 5 technical debt system, Phase 6 risk/blocker intelligence, Phase 7 architecture refactor planning, and Phase 8 self-improvement engine are complete at the documentation level. The current execution roadmap is [[Master Roadmap]].

[[Engineering System Flaw Remediation Plan]] Phase 00 and Phase 01 are complete. Canonical source views are documented, secondary duplicate notes have unique names, and the vault checker now fails on uncontrolled duplicate note titles.

Scenario-intelligence documentation was added and hardened on 2026-06-04. Future testing/intelligence agents should use [[Scenario Intelligence Agent]], [[System Model]], [[State Graph]], [[Business Rule Graph]], [[Assumption Register]], [[Failure Graph]], and [[Scenario Coverage Matrix]] to generate scenario tests from assumptions and failure chains, then track coverage status.

## Execution Status

- Current production-readiness plan: [[Master Roadmap]]
- Architecture refactor planning: [[Architecture Refactor Plan Index]]
- 30/60/90 execution plan: [[30 Day Plan]], [[60 Day Plan]], [[90 Day Plan]]
- Parallel work streams: [[Parallel Work Streams]]
- Launch blockers: [[Launch Blockers]]
- Quick wins: [[Quick Wins]]
- High-risk work: [[High-Risk Work]]
- Active sprint: [[Active Sprint]]
- Audit tracker: [[Audit Resolution Tracker]]
- Current blockers: [[BLOCKERS]]
- Open risk register: [[Risk Register]]
- Risk model: [[Risk Categories]], [[Risk Matrix]]
- Blocker resolution: [[Blocker Resolution Plan]]
- Technical debt register: [[Technical Debt Register]]
- Technical debt prioritization: [[Debt Prioritization]]
- Technical debt categories: [[Debt Categories]]
- Lessons learned: [[Lessons Learned Index]]
- Self-improvement system: [[Lessons Learned]], [[Engineering Insights]], [[Continuous Learning Rules]], [[Improvement Backlog]], [[Optimization Opportunities]], [[Project Metrics]], [[Recommended Next Actions]]
- Engineering system remediation: [[Engineering System Flaw Remediation Plan]]
- Auth/startup remediation: [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md)
- AI memory: [[Project Memory]], [[AI Memory Index]]
- Knowledge graph: [[Knowledge Graph Index]]
- Templates: [[Templates Index]]
