# Current Status

Last updated: 2026-06-03

## Repository State

- Active working repo: `C:\Users\eslam\OneDrive\Desktop\GoodStuff\Rain`
- Current branch observed during audit: `dev`
- Branch state observed: ahead of `origin/dev` by local commits
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
- 2026-06-03 Phase 09 local pre-artifact release gate passed `dart pub get`, analyze, full Melos tests, Firebase JSON parsing, Firebase Functions tests, Firebase emulator integration tests, and Obsidian vault validation. Cloud artifacts and release-page proof are still required for the hard release gate.
- 2026-06-03 auth/startup investigation is captured in [AUTHENTICATION_AUDIT.md](../../AUTHENTICATION_AUDIT.md), [ACCOUNT_LIFECYCLE_ANALYSIS.md](../../ACCOUNT_LIFECYCLE_ANALYSIS.md), [STARTUP_SEQUENCE_ANALYSIS.md](../../STARTUP_SEQUENCE_ANALYSIS.md), [SPLASH_SCREEN_INVESTIGATION.md](../../SPLASH_SCREEN_INVESTIGATION.md), [NAVIGATION_INITIALIZATION_AUDIT.md](../../NAVIGATION_INITIALIZATION_AUDIT.md), and [STATE_MANAGEMENT_FAILURE_ANALYSIS.md](../../STATE_MANAGEMENT_FAILURE_ANALYSIS.md). Correlated finding: local Drift identity, Firebase Auth, RTDB user profile, runtime state, and router state are separate truths; deleted backend account data can be recreated from local identity during runtime startup.
- 2026-06-03 auth Phase 1 mitigation: Drift identity is now restored only after backend validation confirms the cached username still exists and belongs to the current auth uid. Deleted backend accounts and uid mismatches clear local session data before signed-in state is published; register/login save local identity only after backend identity/presence writes succeed.
- 2026-06-03 auth Phase 2 mitigation: logout now clears local Drift session data before best-effort backend sign-out, ignores backend sign-out failure after local clear, handles logout after a previous app-exit shutdown, and invalidates session-scoped Riverpod providers from a `finally` path. Global startup gate, protected-route readiness, and session-scoped provider architecture remain open.

## Documentation Status

This vault is now the main knowledge base. Older docs remain in `docs/`, but future source-of-truth updates should be mirrored here.

Phase 1 vault bootstrap, Phase 2 repository discovery, Phase 3 project memory generation, Phase 4 audit-to-roadmap conversion, Phase 5 technical debt system, Phase 6 risk/blocker intelligence, Phase 7 architecture refactor planning, and Phase 8 self-improvement engine are complete at the documentation level. The current execution roadmap is [[Master Roadmap]].

[[Engineering System Flaw Remediation Plan]] Phase 00 and Phase 01 are complete. Canonical source views are documented, secondary duplicate notes have unique names, and the vault checker now fails on uncontrolled duplicate note titles.

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
