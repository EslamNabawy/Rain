# Lessons Learned

Last updated: 2026-06-04

## Purpose

This note is the operating log for learning after every completed task. It turns completed work, failures, delays, and regressions into durable process, architecture, testing, and automation improvements.

Related: [[Lessons Learned Index]], [[Engineering Insights]], [[Continuous Learning Rules]], [[Improvement Backlog]], [[Project Metrics]], [[Recommended Next Actions]], [[Project Memory]].

## Continuous Learning Rule

After every completed task, record:

- What was learned.
- What caused delays.
- What failed.
- What succeeded.
- What should change.
- Which recurring pattern this confirms or disproves.
- Which improvement item should be created or updated.

No task is fully complete until the lesson check is done or explicitly marked "no new lesson."

## Lesson Entry Template

```markdown
## LESSON-YYYYMMDD-###

- Date:
- Related task:
- Related system:
- Related risk/debt:
- What was learned:
- What caused delays:
- What failed:
- What succeeded:
- What should change:
- Pattern:
- Follow-up improvement:
- Owner:
- Status:
```

## Initial Lessons

### LESSON-20260603-001: Debugging Without Failure Taxonomy Causes Repeated Call Fix Attempts

- Related task: TASK-004, TASK-001, TASK-013
- Related system: [[Voice Calls]], [[Video Calls]], [[CallDiagnosticsRecorder]]
- Related risk/debt: R-001, R-004, TD-016
- What was learned: Generic "call failed" states are not enough to fix WebRTC failures reliably.
- What caused delays: Firebase, media permission, ICE/TURN, renderer, and terminal-state failures were often collapsed into similar UI messages.
- What failed: Repeated fixes that did not first isolate the failure source.
- What succeeded: Moving toward diagnostics taxonomy and call setup timeline planning.
- What should change: Require failure classification before call reliability fixes are declared complete.
- Pattern: Symptom-first debugging.
- Follow-up improvement: IMP-001 in [[Improvement Backlog]].
- Owner: Engineering
- Status: Open

### LESSON-20260603-002: Firebase Rules Must Be Tested Before APK Testing

- Related task: TASK-005, TASK-018
- Related system: [[Rules Strategy]], [[Emulator Coverage]], [[Firebase Architecture]]
- Related risk/debt: R-014, TD-009, TD-011
- What was learned: Permission-denied failures can make new APKs look broken even when app code is not the only cause.
- What caused delays: Rules/app payload drift reached device testing.
- What failed: Relying on manual Firebase rule confidence.
- What succeeded: Planning emulator allow/deny coverage and rule gates.
- What should change: Rules tests must run before release artifacts are treated as useful device builds.
- Pattern: Backend-contract drift.
- Follow-up improvement: IMP-002 in [[Improvement Backlog]].
- Owner: Security/Engineering
- Status: Open

### LESSON-20260603-003: Release Speed Without Gate Clarity Creates Tester Fatigue

- Related task: TASK-015, TASK-016
- Related system: [[Release Gates]], [[CI-CD Roadmap]]
- Related risk/debt: R-018, TD-017
- What was learned: Fast artifacts are useful only when their validation level is obvious.
- What caused delays: Testers installed many builds without knowing whether hard gates had passed.
- What failed: Treating all release artifacts as equally trustworthy.
- What succeeded: Separating fast test artifacts from hard release gates in the roadmap.
- What should change: Every artifact must state commit, channel, version, and gate status.
- Pattern: Artifact trust ambiguity.
- Follow-up improvement: IMP-006 in [[Improvement Backlog]].
- Owner: DevOps
- Status: Open

### LESSON-20260603-004: Documentation Must Be Required, Not Optional

- Related task: TASK-022
- Related system: [[Project Memory]], [[Knowledge Graph Index]], [[Technical Debt Register]], [[Risk Register]]
- Related risk/debt: TD-020
- What was learned: Future AI sessions need one durable source of project truth to avoid rediscovery.
- What caused delays: Context split across chat history, source, old docs, and generated plans.
- What failed: Relying on memory outside the repo.
- What succeeded: Obsidian vault validation and required-file checks.
- What should change: Every implementation cycle must update affected vault notes.
- Pattern: Knowledge loss between sessions.
- Follow-up improvement: IMP-010 in [[Improvement Backlog]].
- Owner: Engineering
- Status: Open

### LESSON-20260603-005: Governance Rules Need Enforcement, Not Just Good Intentions

- Related task: [[Engineering System Flaw Remediation Plan]]
- Related system: [[Project Memory]], [[Knowledge Graph Index]], [[Improvement Backlog]], [[Project Metrics]]
- Related risk/debt: IMP-013, IMP-014, IMP-015, IMP-016, IMP-017
- What was learned: A strong repository operating manual is not enough if validation cannot detect skipped evidence, stale metrics, duplicate source notes, or missing lessons.
- What caused delays: The vault checker validates structure and links, but not the semantic truth of the operating model.
- What failed: Treating "single source of truth" as a written rule while allowing duplicate note titles and manual-only status updates.
- What succeeded: The flaw analysis identified a dependency order: canonicalize source notes first, then add schema, evidence, metrics, and automation gates.
- What should change: Execute [[Engineering System Flaw Remediation Plan]] before building Phase 9 automation.
- Pattern: Manual governance drift and ambiguous knowledge graph sources.
- Follow-up improvement: IMP-013 through IMP-017 in [[Improvement Backlog]].
- Owner: Engineering
- Status: Open

### LESSON-20260603-006: Evidence Must Correlate Across Devices Before Call Fixes

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md)
- Related system: [[Voice Calls]], [[Video Calls]], [[Presence Management]], [[Rules Strategy]], [[Diagnostics Sanitization]], [[Version And Updates]]
- Related risk/debt: R-001, R-003, R-006, R-014, TD-003, TD-004, TD-016, TD-018
- What was learned: The 2026-06-03 evidence shows several visible failures share deeper causes: split call terminal authority, Firebase `signaling.endCall` permission denial, presence freshness races, terminal inbox exposure before cleanup, Android diagnostics export failure, and update build-number inconsistency.
- What caused delays: Prior debugging often treated voice failure, video failure, false busy, stale presence, update prompts, and diagnostics export as separate issues.
- What failed: Release-build retries without a correlated root-cause tree and without emulator proof for Firebase end-call rules.
- What succeeded: Correlating the Windows diagnostic JSON with the Android screenshot proved the failures are primarily signaling/presence/rules/cleanup issues before proven ICE or TURN failure.
- What should change: No more call reliability patch should be accepted until it maps to the RCA evidence and adds validation for the exact root-cause cluster it claims to fix.
- Pattern: Multi-device symptoms from one fragmented lifecycle.
- Follow-up improvement: Prioritize Firebase end-call emulator reproduction, terminal-state reconciliation, presence snapshot unification, and Android diagnostics export repair in [[Recommended Next Actions]].
- Owner: Engineering
- Status: Open

### LESSON-20260603-007: Canonical Sources Must Be Locked Before Automation

- Related task: [[Engineering System Flaw Remediation Plan]] Phase 00 and Phase 01
- Related system: [[Knowledge Graph Index]], [[Project Home]], [[Project Metrics]]
- Related risk/debt: IMP-013, IMP-014
- What was learned: Automation should not be added on top of ambiguous note titles because it would make the wrong structure harder to unwind.
- What caused delays: Several canonical domains had duplicate note titles even though one note was only a view or index.
- What failed: The previous validator allowed duplicate titles because its note-title map overwrote earlier paths.
- What succeeded: Secondary notes were renamed into unique view/index names, the canonical source map was documented, and the validator now fails on duplicate titles.
- What should change: Future vault bootstrapping must check duplicate titles before link validation.
- Pattern: Ambiguous knowledge graph sources.
- Follow-up improvement: IMP-013 completed; IMP-014 remains in progress for deeper semantic validation.
- Owner: Engineering
- Status: Open

### LESSON-20260603-008: Expected Terminal Races Must Not Be Crash Diagnostics

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) first mitigation
- Related system: [[Voice Calls]], [[CallDiagnosticsRecorder]], [[Diagnostics And Logging]]
- Related risk/debt: TD-004, TD-016
- What was learned: The latest diagnostic export showed a benign late voice signaling state after terminal cleanup being stored as `lastCrash`, which hid the real call failure evidence.
- What caused delays: The runtime treated an expected cleanup race as a non-fatal error instead of a structured diagnostic event.
- What failed: Exported diagnostics became misleading because the "last Flutter error" pointed to `Ignored late voice signaling...` rather than the deeper signaling/media failure.
- What succeeded: A regression now locks `_recordLateVoiceFrame` to emit `late_frame_ignored` without calling the crash/error recorder.
- What should change: Expected races, cleanup echoes, and already-terminal state must be warning/info events unless they break user-visible behavior.
- Pattern: Observability pollution from expected async races.
- Follow-up improvement: Continue with Firebase end-call permission reproduction and richer call failure taxonomy.
- Owner: Engineering
- Status: Open

### LESSON-20260603-009: Terminal Source Of Truth Must Not Depend On Mirror Rows

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) second mitigation
- Related system: [[Voice Calls]], [[Firebase Architecture]], [[Rules Strategy]], [[CallTerminalReconciler]]
- Related risk/debt: TD-003, TD-009, TD-011
- What was learned: `voiceCallInboxes` is a callee-facing invite mirror, not the authoritative terminal call record. When `endCall` wrote terminal room state and terminal inbox state in one multi-path update, a cleaned inbox row could make Firebase deny the whole terminal write.
- What caused delays: The app treated room state and inbox mirror state as one atomic artifact even though the rules intentionally allow new inbox rows only for `ringing`.
- What failed: A valid `endCall` could become `[firebase_database/unknown] Permission denied` when the callee inbox had already been removed by cleanup or watcher repair.
- What succeeded: A Firebase emulator regression reproduced the exact denied write, then the adapter was changed to write terminal `voiceCalls/{callId}` state first and update the inbox mirror only if it still exists.
- What should change: Authoritative state writes must be isolated from optional mirror cleanup. Mirror rows can be best-effort, but they must never block terminal state, lock release, or user-visible cleanup.
- Pattern: Authoritative state coupled to optional mirror row.
- Follow-up improvement: Continue terminal reconciliation hardening for every voice/video cleanup path and add more emulator cases for already-terminal/missing-room/idempotent cleanup.
- Owner: Engineering
- Status: Open

### LESSON-20260604-001: Registration Permission Denied Can Be A Username Conflict

- Related task: Create-account Firebase permission-denied investigation.
- Related system: [[Authentication]], [[Rules Strategy]], [[Firebase Architecture]]
- Related risk/debt: R-014, R-021, TD-021
- What was learned: Live Firebase rules can allow fresh registration while a specific username still fails with RTDB permission denied because `users/{username}` already exists or is locked by another uid.
- What caused delays: The raw Firebase message looked like a global rules failure, but a live random registration probe showed the rules were not broadly denying new users.
- What failed: The app exposed `[firebase_database/unknown] Permission denied` directly and did not make failed backend registration cleanup explicit enough.
- What succeeded: Checking live `/users/eslam` and a fresh random registration separated username-conflict evidence from rules-deployment evidence. Regression tests now cover backend-save failure sign-out/no-cache behavior and onboarding conflict copy.
- What should change: Registration fixes must distinguish primary user-row failure from secondary backend-write failure. Delete the just-created Auth user only before the durable RTDB user row exists; after that, sign out and preserve the recoverable account.
- Pattern: Raw backend errors hiding domain-specific conflicts.
- Follow-up improvement: Add emulator/adapter coverage for registration username conflicts and partial secondary-write failure if the Firebase adapter becomes easier to fake.
- Owner: Engineering
- Status: Open

### LESSON-20260603-010: Picker Return Values Are Not Always Filesystem Paths

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) Android diagnostics export mitigation
- Related system: [[Diagnostics And Logging]], [[Diagnostics Sanitization]]
- Related risk/debt: TD-010, TD-016
- What was learned: Android SAF picker outputs can look like `/document/1282` instead of a `content://...` URI. Treating that value as a `dart:io` file path caused `PathNotFoundException` and blocked diagnostic exports.
- What caused delays: The code already handled `content://` URIs but did not classify bare SAF handles as platform-managed outputs.
- What failed: Export fallback tried to open `/document/1282` directly even though the picker had already received the JSON bytes.
- What succeeded: A regression now locks `/document/...` handling so diagnostics export returns success without filesystem fallback.
- What should change: Any file picker/save picker integration must distinguish platform-managed handles from real filesystem paths before using `File`.
- Pattern: Platform handle mistaken for local path.
- Follow-up improvement: Extend file-transfer save/export flows with similar SAF-handle tests if they accept picker results.
- Owner: Engineering
- Status: Open

### LESSON-20260603-011: Presence Truth Requires Heartbeat Age, Not Raw Online

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) Phase 05
- Related system: [[Presence Management]], [[Presence And Direct Connect]], [[Voice Calls]], [[Connection Request Notifications]]
- Related risk/debt: R-003, R-016, R-020, TD-002
- What was learned: A backend identity with `online: true` is not enough to safely mark a peer reachable. The runtime must also evaluate `lastHeartbeat` age using the same freshness window before seeding UI state or allowing user actions.
- What caused delays: Friend sync, Connect, connection requests, and call start each trusted the collapsed `BackendIdentity.online` result instead of applying one local freshness contract at the action boundary.
- What failed: A stale raw-online backend record could mark a friend online, allow direct Connect, or create call setup state even though the heartbeat was expired.
- What succeeded: Runtime presence resolution now uses one 30 second freshness window for friend seeding, direct Connect, connection-request routing, and voice/video call start, and stale raw-online records produce `backend_presence_stale_resolved_offline` diagnostics.
- What should change: Any future action that depends on presence must consume the shared resolver or a typed presence snapshot with heartbeat age, not a raw bool.
- Pattern: Collapsed availability bool hides stale-state evidence.
- Follow-up improvement: Continue with session-owned presence/app-close recovery and remove or narrow internal auto-recovery stale-presence bypasses.
- Owner: Engineering
- Status: Open

### LESSON-20260603-012: Terminal Room Failures Need Diagnostics On The Observing Side

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) Phase 06
- Related system: [[Voice Calls]], [[Video Calls]], [[CallDiagnosticsRecorder]], [[Call State Machine]]
- Related risk/debt: R-001, R-004, R-009, TD-004, TD-016
- What was learned: A peer can fail only by observing a terminal Firebase room written by the other side. If diagnostics are emitted only by the side that threw the native media error, the observing side can export a failed call with an empty room timeline.
- What caused delays: Call diagnostics were coupled to local session failure events, while Firebase terminal reconciliation was treated mainly as state cleanup.
- What failed: Failed setup reports could say media failed without preserving the room transition path that proved whether the call reached ringing, accepted, connected, or terminal state.
- What succeeded: Runtime now records bounded room status timelines per call, includes them in `VoiceCallDiagnostics`, and emits diagnostics from remote terminal-room failure reconciliation.
- What should change: Any terminal-room reconciliation path that changes user-visible call state should also produce diagnostics if the call ends as failed.
- Pattern: Diagnostics owned by thrower instead of state observer.
- Follow-up improvement: Continue expanding failure taxonomy with ICE candidate counts, selected route, media track/renderer lifecycle, and first-frame evidence.
- Owner: Engineering
- Status: Open

### LESSON-20260603-013: UI Presence Checks Must Use The Runtime Resolver

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) Phase 05 continuation
- Related system: [[Presence Management]], [[Presence And Direct Connect]], [[Connection Request Notifications]]
- Related risk/debt: R-003, R-016, R-020, TD-002
- What was learned: Even after runtime Connect and call paths used heartbeat freshness, the chat Connect button still read raw `BackendIdentity.online` directly, which could route stale peers into direct Connect instead of offline request notification.
- What caused delays: Presence truth was improved in runtime code before every UI action surface was audited for direct backend reads.
- What failed: A widget-side online/offline split could bypass `lastHeartbeat` and `presence.state` checks.
- What succeeded: The chat Connect action now calls the runtime fresh-presence resolver, and auto-recovery also requires fresh backend presence before reconnecting.
- What should change: Any future UI action that branches on online/offline must call a shared resolver or typed presence snapshot, never raw `online`.
- Pattern: UI shortcut bypassed runtime truth.
- Follow-up improvement: Add a small widget/provider contract test once the local Drift/sqlite harness is fixed or run the full app runtime suite in CI.
- Owner: Engineering
- Status: Open

### LESSON-20260603-014: Current Is Not The Same As Trusted Update Policy

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) Phase 07
- Related system: [[Version And Updates]], [[Release Gates]]
- Related risk/debt: R-006, TD-018, BLK-004
- What was learned: An installed build can be newer than the Remote Config release policy. Reporting that as "Rain is up to date" hides stale release metadata and makes the settings text look contradictory.
- What caused delays: The update state machine had only current/optional/required/unavailable/invalid states, so it collapsed stale Remote Config policy into current.
- What failed: Manual update checks could show a lower latest-known version while still saying the app was up to date.
- What succeeded: Update checks now expose `remotePolicyOutdated`, same-version minimum-build upgrades are required updates, and optional prompts render from the root app surface before login/home.
- What should change: Each release must keep package metadata, release manifest, Remote Config template, and deployed Remote Config in sync.
- Pattern: Missing state for stale control-plane data.
- Follow-up improvement: Add release evidence that records the deployed Remote Config manifest for the artifact commit.
- Owner: Engineering/DevOps
- Status: Open

### LESSON-20260603-015: Small Regression Tests Keep Progress Moving When Heavy Harnesses Fail

- Related task: Phase 08 Regression Test Expansion, TASK-003, TASK-004, TASK-006, TASK-013, TASK-019
- Related system: [[Voice Calls]], [[Video Calls]], [[Presence Management]], [[CallDiagnosticsRecorder]], [[Test Strategy]]
- Related risk/debt: R-001, R-003, R-004, TD-004, TD-015, TD-016
- What was learned: The full `friend_flow_test.dart` runtime harness is still important, and it can run locally when invoked from the app package context through `scripts/run_rain_app_test.ps1`.
- What caused delays: The heaviest runtime tests cover the most important call and presence behavior, but the root-level isolated invocation made them look unreliable by failing SQLite native-asset loading before app logic.
- What failed: Treating only the heavy runtime harness as valid proof would block regression expansion.
- What succeeded: Phase 08 added low-dependency tests for call failure messages, failed call suite states, compact video dock behavior, terminal-room-before-session-hangup ordering, failed-media terminal writes, already-terminal cleanup classification, and session-owned Firebase presence.
- What should change: For every high-risk bug, add the smallest deterministic regression first, then add or restore full integration coverage once the harness is healthy.
- Pattern: Heavy harness dependency blocks targeted regression coverage.
- Follow-up improvement: Keep future isolated app-test instructions on `scripts/run_rain_app_test.ps1` and use it for full friend-flow regression runs.
- Owner: Engineering
- Status: Open

### LESSON-20260603-016: App Tests Must Run In Their Package Context

- Related task: TASK-006, TASK-018
- Related system: [[Test Strategy]], [[Presence Management]], [[Presence And Direct Connect]]
- Related risk/debt: R-003, R-019, TD-015
- What was learned: The SQLite native-asset failure came from invoking an app test from the repository root with a root-relative path. Running through `scripts/run_rain_app_test.ps1` keeps the test process in `apps/rain`, where native assets resolve correctly.
- What caused delays: The failing command looked like a runtime SQLite failure even though full Melos tests and the app-package context could resolve native assets.
- What failed: `flutter test apps\rain\test\friend_flow_test.dart` from the repository root is not a safe isolated app-test command on Windows.
- What succeeded: `.\scripts\run_rain_app_test.ps1 apps\rain\test\friend_flow_test.dart -PlainName "relationship sync does not seed stale backend presence as online"` passed, and full `friend_flow_test.dart` passed through the wrapper with 120 passing tests and 10 skipped legacy control-channel cases.
- What should change: Future isolated Rain app tests must use the wrapper or run from `apps/rain`.
- Pattern: Package-context mismatch masquerading as native runtime failure.
- Follow-up improvement: Use the wrapper for future app runtime regression expansion and avoid root-level isolated app-test commands.
- Owner: Engineering
- Status: Open

### LESSON-20260603-017: Startup Readiness Needs One Typed Contract Before UI Gating

- Related task: Auth/startup remediation Phase 3
- Related system: [[Authentication]], [[Frontend Architecture]], [[Project Memory]]
- Related risk/debt: R-022, TD-022, BLK-010
- What was learned: Root loading, update gates, identity validation, runtime startup, session-expired reset, and navigation visibility must be derived from one typed state before global splash or protected-route work is reliable.
- What caused delays: The previous logic split readiness between `RootScreen`, `appShellReadinessProvider`, identity, force-update, and runtime providers, which made it hard to prove the app could not show partial protected UI.
- What failed: Route-local readiness checks were individually reasonable but not strong enough as a production startup contract.
- What succeeded: `AppStartupState` now centralizes startup phases, and focused tests cover update loading, required update, session validation, signed-out, runtime loading, ready, and expired-session phases.
- What should change: Future startup/navigation work should consume `AppStartupState` instead of re-deriving readiness from raw providers.
- Pattern: Fragmented readiness logic creates impossible-to-prove startup behavior.
- Follow-up improvement: Phase 4 should lift the visual splash/readiness gate above normal app chrome using the typed startup contract.
- Owner: Engineering
- Status: Open

### LESSON-20260603-018: Global Visual Gates Must Sit Above Routed Shells

- Related task: Auth/startup remediation Phase 4
- Related system: [[Authentication]], [[Frontend Architecture]], [[Project Memory]]
- Related risk/debt: R-022, TD-022, BLK-010
- What was learned: Redirecting protected routes to `/` and hiding bottom navigation is not enough if the routed shell still wraps the loading/update/error child. The visual gate needs to replace the router child from the app root.
- What caused delays: `RootScreen` owned the startup surfaces, while `MaterialApp.router` and `ShellRoute` were already active after infrastructure bootstrap.
- What failed: A route-local splash could avoid visible nav controls but still leave normal shell/backdrop infrastructure in the widget tree.
- What succeeded: `RainApp` now uses `MaterialApp.router.builder` to render `RainStartupSurface` instead of the routed child whenever `AppStartupState.blocksRoutedSurface` is true, and tests prove blocked startup states do not insert `RainNavigationShell`.
- What should change: Future protected-route work should build on the global gate instead of adding more route-local splash checks.
- Pattern: Route-local loading screens cannot prove app-global readiness.
- Follow-up improvement: Phase 5 hardened protected route availability; Phase 6 should harden session-scoped provider lifecycle after the global visual gate.
- Owner: Engineering
- Status: Open

### LESSON-20260603-019: Protected Routes Need Both Redirects And Local Guards

- Related task: Auth/startup remediation Phase 5
- Related system: [[Authentication]], [[Frontend Architecture]], [[Project Memory]]
- Related risk/debt: R-022, TD-022, BLK-010
- What was learned: A router redirect is necessary but not sufficient for protected navigation readiness. Protected pages also need a route-local guard because stale route state or delayed refreshes can still build a page widget during startup transitions.
- What caused delays: Signed-out auth needed to render outside the normal shell, but rendering it directly from `MaterialApp.router.builder` removed the Navigator/Overlay subtree required by tooltips and other overlay-aware widgets.
- What failed: Treating signed-out auth exactly like a splash surface created an overlay boundary bug in tests.
- What succeeded: `AppStartupState.canRenderProtectedRoutes` makes the contract explicit, protected settings/search/friend pages use `_ProtectedRouteGate`, unresolved protected paths redirect to `/`, and signed-out auth gets a standalone Navigator/Overlay without inserting `RainNavigationShell`.
- What should change: Future protected features should expose one readiness predicate and use both router-level redirects and widget-level guards when stale navigation state can exist.
- Pattern: Navigation protection needs defense in depth.
- Follow-up improvement: Phase 6 should scope account-owned providers so guarded routes cannot retain stale provider state after logout/login or session reset.
- Owner: Engineering
- Status: Open

### LESSON-20260603-020: Account State Needs A Session Generation Boundary

- Related task: Auth/startup remediation Phase 6
- Related system: [[Authentication]], [[Frontend Architecture]], [[Project Memory]]
- Related risk/debt: R-021, TD-021, TD-022, BLK-010
- What was learned: Logout, startup gates, and protected routes do not fully clear account-owned provider state unless every account-scoped provider has an explicit session boundary.
- What caused delays: Runtime reuse and provider cleanup previously depended on username comparisons and broad manual invalidation lists, which are fragile with family providers and same-user relogin.
- What failed: Treating provider invalidation as the primary lifecycle mechanism left too much room for stale searches, messages, transfers, and runtime references to survive account transitions.
- What succeeded: `AuthenticatedSession.sessionGeneration` now scopes runtime ownership, account-owned providers watch the session boundary, stale runtimes are rejected, and focused tests cover session end, recent search reset, search reset, and message stream cleanup.
- What should change: Every new account-owned provider must watch authenticated session generation or prove it is device-global state.
- Pattern: State lifetime must be explicit, not inferred from route visibility or username equality.
- Follow-up improvement: Account deletion workflow was implemented on 2026-06-04; add auth/startup/account-deletion regression coverage to the hard release gate.
- Owner: Engineering
- Status: Open

### LESSON-20260604-021: Terminal Firebase Rooms Must Gate Late Media Writes Before Debug Instrumentation

- Related task: TASK-003, TASK-004
- Related system: [[Voice Calls]], [[Signaling Architecture]], [[Call State Machine]], [[Diagnostics And Logging]]
- Related risk/debt: R-001, R-009, TD-004
- What was learned: Catching an already-terminal call-room error after `writeVoiceOffer` is too late because `DebugSignalingAdapter` records the failed Firebase operation as `signaling.writeVoiceOffer` before runtime can classify it as a terminal race.
- What caused delays: Earlier mitigations handled late received frames and terminal cleanup, but local media negotiation could still start a fresh SDP write after the room had already ended.
- What failed: A PC runtime in `_createAndSendOffer` attempted to write an offer for a call that Firebase already marked `ended`, creating a false crash diagnostic.
- What succeeded: Runtime now preflights terminal-sensitive media signaling sends (`accept`, `offer`, `answer`, `mute`) with `fetchCall`; missing or terminal rooms are skipped and reconciled before write calls reach the debug adapter.
- What should change: Any future call signaling write that can happen after async media awaits must pass through the same terminal-room gate or an equivalent coordinator.
- Pattern: Expected terminal races must be classified before instrumentation layers that record operation failures.
- Follow-up improvement: Extract this into [[CallTerminalReconciler]] when `VoiceCallRuntime` is split.
- Owner: Engineering
- Status: Open

### LESSON-20260604-022: Android Picker Handles Need A Real Export Fallback

- Related task: TASK-014
- Related system: [[Diagnostics And Logging]], [[Diagnostics Sanitization]]
- Related risk/debt: R-015, TD-010
- What was learned: Avoiding `File('/document/...')` prevents the crash, but it does not guarantee the user has a real file path to share when Android returns a scoped-storage handle.
- What caused delays: The first mitigation treated SAF handles as non-files but still returned the handle as the export result.
- What failed: Users could still see export failures or unusable `/document/...` paths on OEM Android storage pickers.
- What succeeded: Diagnostics export now writes a real fallback JSON copy under Rain diagnostics exports whenever the picker returns a content URI or `/document/...` handle.
- What should change: Any export flow using Android storage access handles should either rely entirely on plugin-provided bytes or keep a real app-owned fallback file.
- Pattern: Platform-managed handles are not filesystem paths.
- Follow-up improvement: Consider a dedicated share action for diagnostics once release stability is higher.
- Owner: Engineering
- Status: Open

### LESSON-20260604-023: Governance Needs A Visible Workflow State

- Related task: Phase 1 governance and operating system synchronization.
- Related system: [[AI Operating Notes]], [[Project Memory]], [[Documentation Workflow]]
- Related risk/debt: ESF-001, ESF-003, ESF-006
- What was learned: Strong rules in prose are easier to follow when every non-trivial session declares its current workflow node and reports skipped validation explicitly.
- What caused delays: The root operating manual and Obsidian AI notes did not yet share the exact same autonomous workflow vocabulary.
- What failed: Relying on chat-only instructions makes future handoffs weaker because the rules can disappear outside repository state.
- What succeeded: The source-of-truth priority order, reality-enforcement rule, and node-based workflow are now written into root and vault governance docs.
- What should change: Future governance automation should parse node/completion evidence rather than relying only on human discipline.
- Pattern: Manual governance drift.
- Follow-up improvement: Continue [[Engineering System Flaw Remediation Plan]] Phase 02 and Phase 03 with parseable status schema and validation evidence ledger.
- Owner: Engineering
- Status: Open

### LESSON-20260604-024: Destructive Account Flows Need Two Failure Classes

- Related task: [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md) Phase 05
- Related system: [[Authentication]], [[Firebase Architecture]], [[Rules Strategy]]
- Related risk/debt: R-021, TD-021, BLK-010
- What was learned: Account deletion cannot use one generic error path. A failed password reauthentication is non-destructive and must preserve the current session, while backend/Auth failures after cleanup starts are destructive partial failures and must clear local session state.
- What caused delays: The original account-lifecycle gap mixed reauthentication, runtime shutdown, RTDB cleanup, Auth deletion, and local session reset into one conceptual "delete" action.
- What failed: Without an explicit failure class, a bad password could accidentally behave like account deletion, or a partial backend delete could leave stale local identity able to restore.
- What succeeded: `AccountDeletionException.destructiveActionStarted` now separates pre-destructive failures from partial destructive failures; runtime/provider tests cover preserving identity before reauth and clearing identity after backend failure.
- What should change: Every future destructive lifecycle flow should expose whether durable state was touched before deciding local cleanup and user messaging.
- Pattern: Destructive workflows need irreversible-boundary tracking.
- Follow-up improvement: Add Firebase emulator/device proof for account deletion tombstone cleanup and include the targeted account-deletion tests in the hard release gate.
- Owner: Engineering
- Status: Open

### LESSON-20260604-025: Login Must Not Repair Deleted Backend Accounts

- Related task: [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md) Phase 05
- Related system: [[Authentication]], [[Firebase Architecture]]
- Related risk/debt: R-021, TD-021, BLK-010
- What was learned: After account deletion tombstones RTDB, Firebase Auth deletion can still fail. If normal login treats a missing backend identity as a profile creation opportunity, the deleted account can be revived.
- What caused delays: The earlier source-of-truth fix guarded cached identity restoration, but the explicit login path still wrote backend identity when `fetchIdentity` returned null.
- What failed: A surviving Auth user after partial delete could authenticate, then `_saveBackendIdentity` could recreate `users/{username}` and `userSearch/{username}`.
- What succeeded: Login now requires backend identity proof after Auth succeeds, signs out on missing/wrong-owner backend identity, and does not upsert, set presence, or cache Drift identity. Firebase and emulator upsert paths also reject tombstoned users, and rules block `userSearch` writes for deleted users.
- What should change: Login and registration must stay separate lifecycle operations. Login validates durable backend account existence; registration creates it.
- Pattern: Recovery path accidentally became account recreation.
- Follow-up improvement: Add Firebase emulator proof that tombstoned accounts cannot re-add `userSearch` or upsert profile data.
- Owner: Engineering
- Status: Open

### LESSON-20260604-026: Testing Agents Need Graphs, Not Just Handoffs

- Related task: Scenario-intelligence operating layer.
- Related system: [[Scenario Intelligence Agent]], [[System Model]], [[Failure Graph]], [[Assumption Register]]
- Related risk/debt: R-001, R-003, R-014, R-021, TD-015, TD-016
- What was learned: A developer handoff explains where to work, but a testing/intelligence agent needs explicit system, state, business-rule, assumption, and failure graphs to generate useful scenarios.
- What caused delays: Existing notes had feature and dependency maps, but assumptions and cross-domain failure chains were not first-class testing inputs.
- What failed: Ad hoc scenario generation risks producing broad but shallow test lists that do not target Rain's interaction failures.
- What succeeded: The vault now includes [[Scenario Intelligence Agent]], [[System Model]], [[State Graph]], [[Business Rule Graph]], [[Assumption Register]], and [[Failure Graph]], and the AI/testing/knowledge indexes link them.
- What should change: Future QA and risk-analysis passes should start by violating assumptions and tracing failure chains before proposing tests, then record coverage in [[Scenario Coverage Matrix]].
- Pattern: Model-driven scenario generation.
- Follow-up improvement: Close the Gap and Partially Covered rows in [[Scenario Coverage Matrix]] with named tests, emulator proof, device proof, or explicit owner acceptance.
- Owner: Engineering
- Status: Open

### LESSON-20260604-027: Native Android Themes Must Match Flutter Splash

- Date: 2026-06-04
- Related task: Phase E Android splash flash remediation.
- Related system: [[Branding And UI]], [[Frontend Architecture]]
- Related risk/debt: R-022, TD-022
- What was learned: A correct Flutter splash surface is not enough if Android switches from `LaunchTheme` to a light `NormalTheme` before Flutter draws the first frame.
- What caused delays: The launch drawable was already dark, so the remaining white flash came from the post-launch native theme handoff rather than the Flutter widget tree.
- What failed: `NormalTheme` in both light and night resources still used the platform background.
- What succeeded: Both `LaunchTheme` and `NormalTheme` now use `@drawable/launch_background`, and `apps/rain/test/android_splash_resources_test.dart` locks the theme and drawable colors.
- What should change: Any future splash/branding change must check Android platform resources as well as Flutter widgets.
- Pattern: Native shell state can break a Flutter-owned visual contract.
- Follow-up improvement: Add platform resource contract tests when Android or Windows shell resources affect startup or branding.
- Owner: Engineering
- Status: Open

## Review Cadence

- Review lessons at the end of every completed task.
- Review recurring patterns weekly.
- Convert repeated patterns into items in [[Improvement Backlog]].
- Promote major process decisions into ADRs when they affect architecture or release policy.
