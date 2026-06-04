# BLOCKERS

Last updated: 2026-06-04

## Purpose

This is the operational blocker register for Rain.

Blockers must never stop progress. A blocker only prevents unsafe release or unsafe promotion. Every blocker must have:

- owner,
- affected risks,
- affected roadmap tasks,
- affected debt,
- workaround strategy,
- resolution plan,
- exit criteria,
- parallel progress path.

Related: [[Risk Register]], [[Risk Categories]], [[Risk Matrix]], [[Blocker Resolution Plan]], [[Launch Blockers]], [[Critical Path]], [[Technical Debt Register]].

## Blocker Rules

- Critical blockers prevent public launch.
- High blockers prevent production readiness unless explicitly accepted.
- Blockers do not prevent unrelated parallel work.
- If a blocker cannot be resolved immediately, use the workaround and continue safe work from [[Parallel Work Streams]].
- If a blocker requires external input, document that dependency and continue independent tasks.

## Active Blockers

### BLK-001: Voice/Video Call Setup Reliability Is Not Proven

- Status: Open
- Severity: Critical
- Owner: Engineering
- Type: Technical
- Related Risks: R-001, R-004, R-007, R-009
- Related Roadmap Tasks: TASK-001, TASK-003, TASK-004, TASK-013
- Related Debt: TD-001, TD-004, TD-016
- Related Architecture: [[VoiceCallRuntime Refactor]], [[Call State Machine]], [[CallMediaCoordinator]], [[CallDiagnosticsRecorder]]
- Impact: Public launch is blocked because a core feature can fail in PC-to-mobile, mobile-to-PC, or retry paths.
- Workaround Strategy: Keep artifacts as test builds only; require diagnostics export for every failed call; use text chat and file transfer as unaffected test surfaces.
- Parallel Progress Path: Work on [[Version And Updates]], [[Rules Strategy]], [[Diagnostics Sanitization]], [[Index Strategy]], and [[Backpressure Strategy]] while call runtime work proceeds.
- Resolution Plan:
  - Define coordinator contracts for start, lease, media, terminal, and diagnostics.
  - Add call setup timeline diagnostics.
  - Add runtime tests for success, timeout, media failure, permission denial, and terminal cleanup.
  - Prove both voice and video directions in automated or documented smoke evidence.
- Progress 2026-06-03: Failed call setup diagnostics now preserve Firebase room status timelines inside `VoiceCallDiagnostics`, and remote terminal-room failures emit diagnostics even when the local side only observes Firebase terminal state.
- Progress 2026-06-03 Phase 08: Local regression tests now lock WebRTC/Firebase/network call failure messages, failed call suite state, compact video dock behavior, terminal-room-before-session-hangup ordering, failed-media terminal write before disposal, and already-terminal cleanup classification.
- Exit Criteria: PC-to-mobile and mobile-to-PC voice/video setup have deterministic pass/fail behavior, no stuck connecting state remains, and diagnostics classify the failure source.
- Detection Strategy: Runtime tests, call diagnostics timeline, release smoke logs, and watcher for repeated failed media setup events.

### BLK-002: False Busy And Stale Call Locks Can Block Calls

- Status: Open
- Severity: Critical
- Owner: Engineering
- Type: Architecture/Technical
- Related Risks: R-002, R-009
- Related Roadmap Tasks: TASK-002, TASK-003, TASK-005
- Related Debt: TD-003, TD-011
- Related Architecture: [[Lease Management]], [[CallLeaseManager]], [[CallTerminalReconciler]], [[Firebase Architecture]]
- Impact: Users can be blocked from calling because stale Firebase locks appear as real active calls.
- Workaround Strategy: Use explicit cleanup/retry guidance in diagnostics; avoid treating busy as final until room status is inspected.
- Parallel Progress Path: Work on update validation, diagnostics sanitizer, and database/file scalability while lease repair tests are added.
- Resolution Plan:
  - Inspect room status before returning busy.
  - Repair missing, expired, terminal, corrupt, or caller-owned failed setup locks.
  - Delete only matching `callId` locks.
  - Retry internally once after cleanup.
  - Prove live newer locks are never deleted.
- Exit Criteria: Emulator/fake tests cover stale, missing, terminal, corrupt, live, and newer-lock cases.
- Detection Strategy: Diagnostics with pair/user lock path, call id, room status, cleanup action, and retry result.

### BLK-003: Firebase Rules And App Behavior Must Stay Spark-Safe

- Status: Open
- Severity: High
- Owner: Security/Engineering
- Type: Security/Operational
- Related Risks: R-014, R-016, R-017
- Related Roadmap Tasks: TASK-005, TASK-017, TASK-023
- Related Debt: TD-009, TD-011, TD-012, TD-020
- Related Architecture: [[Rules Strategy]], [[Emulator Coverage]], [[Firebase Architecture]], [[Connection Request Notifications]]
- Impact: Invalid rules can deny valid users, allow malformed writes, or force paid backend requirements.
- Workaround Strategy: Keep Spark/free-tier mode as the required path; use RTDB rules, TTL fields, client cleanup, and emulator tests instead of Cloud Functions-only guarantees.
- Parallel Progress Path: Work on UI messaging, diagnostics counters, and release gate documentation while rules tests are expanded.
- Resolution Plan:
  - Create allow/deny rules matrix for critical paths.
  - Add presence freshness checks where writes depend on online/offline state.
  - Add malformed payload deny tests.
  - Add operation counters for quota-sensitive flows.
- Exit Criteria: Emulator rules cover presence, call rooms, locks, inboxes, connection requests, messages, and file metadata.
- Detection Strategy: Firebase emulator test results, permission-denied diagnostics, Firebase operation counters.

### BLK-004: Update Prompt Reliability Is Not Trusted

- Status: Open
- Severity: Critical
- Owner: Product/DevOps
- Type: Product/Operational
- Related Risks: R-006
- Related Roadmap Tasks: TASK-012, TASK-015
- Related Debt: TD-018
- Related Architecture: [[Version And Updates]], [[Release Gates]], [[Production Readiness]]
- Impact: Old clients may keep running against incompatible rules or protocol versions.
- Workaround Strategy: Keep manual direct download links available and do not promote backend-incompatible changes until old-version tests pass.
- Parallel Progress Path: Continue call/runtime and Firebase rules work, but avoid deploying incompatible rules without update proof.
- Resolution Plan:
  - Test semantic version and build comparison.
  - Test required and optional update UI.
  - Test settings "Check for updates" behavior.
  - Include version/channel/build metadata in release artifacts.
- Progress 2026-06-03: Same-version minimum-build policy now produces required updates, stale Remote Config policy is shown as `remotePolicyOutdated` instead of "up to date," optional prompts render from the root app surface before login/home, and settings manual check reports stale policy clearly.
- Exit Criteria: Old stable/demo build simulations show required or optional update correctly.
- Detection Strategy: Unit tests, widget tests, Remote Config manifest parser tests, release gate evidence.

### BLK-005: Diagnostics Must Explain Failures Without Leaking Data

- Status: Open
- Severity: High
- Owner: Security/Engineering
- Type: Security/Testing
- Related Risks: R-015, R-001, R-004
- Related Roadmap Tasks: TASK-004, TASK-014
- Related Debt: TD-010, TD-016
- Related Architecture: [[Diagnostics Sanitization]], [[CallDiagnosticsRecorder]], [[Privacy Review]]
- Impact: Debugging remains guesswork or diagnostics become unsafe for users to share.
- Workaround Strategy: Keep exports local-only and require manual review of new diagnostic fields before release.
- Parallel Progress Path: Work on call/runtime tests while diagnostics schema and sanitizer tests are added.
- Resolution Plan:
  - Add recursive denylist sanitizer.
  - Add call setup timeline without raw SDP, ICE candidate strings, tokens, ciphertext, message text, or file bytes.
  - Add summaries for Firebase, permission, ICE, TURN, media, and terminal failures.
- Exit Criteria: Export tests prove sensitive values are redacted and failure taxonomy is present.
- Detection Strategy: Sanitizer tests, diagnostics export tests, failure taxonomy tests.

### BLK-006: Release Workflow Gate Evidence Is Not Strong Enough

- Status: Open
- Severity: High
- Owner: DevOps
- Type: Operational
- Related Risks: R-018
- Related Roadmap Tasks: TASK-015, TASK-016
- Related Debt: TD-017
- Related Architecture: [[CI-CD Roadmap]], [[Release Gates]], [[Coverage Dashboard]]
- Impact: Broken APK/EXE artifacts can reach testers, causing repeated install cycles and unclear regressions.
- Workaround Strategy: Treat cloud artifacts as test builds unless hard gate evidence is present.
- Parallel Progress Path: Continue docs, debt/risk, and test harness work while hard gate dependencies are clarified.
- Resolution Plan:
  - Define fast artifact workflow vs hard release gate.
  - Require analyze/test/rules/vault validation before publish.
  - Include commit, version, channel, and artifact metadata.
  - Document failure ownership.
- Exit Criteria: Release workflow blocks publish on failed gates and reports exact failing stage.
- Detection Strategy: Workflow run summaries, artifact metadata, gate dependency graph, vault validation.

### BLK-007: Local Android/Appium QA Harness Is Not Release-Blocking Yet

- Status: Open
- Severity: Medium
- Owner: QA/DevOps
- Type: Operational/Testing
- Related Risks: R-019
- Related Roadmap Tasks: TASK-018
- Related Debt: TD-015
- Related Architecture: [[Emulator Test Matrix]], [[Test Strategy]], [[Release Gates]]
- Impact: External black-box Android smoke evidence is not yet reliable enough for release decisions.
- Workaround Strategy: Use Flutter unit/widget/integration tests and cloud artifacts while Appium harness is stabilized.
- Parallel Progress Path: Continue release gate and contract tests without making Appium mandatory yet.
- Resolution Plan:
  - Add stable `ValueKey`/Semantics locators for smoke flow.
  - Update `qa.appium.json`.
  - Run shared local QA scripts when explicitly requested.
  - Store artifacts in the configured artifact path.
- Exit Criteria: Minimal Appium smoke test repeats on `QA_Medium_API_36_1`.
- Detection Strategy: Appium logs, adb logcat, integration artifacts, smoke workflow output.

### BLK-008: Presence Staleness Can Misroute Connect/Call/Request Actions

- Status: Open
- Severity: High
- Owner: Engineering/Product
- Type: Technical/Product
- Related Risks: R-003, R-016, R-020
- Related Roadmap Tasks: TASK-006, TASK-023
- Related Debt: TD-002, TD-012, TD-020
- Related Architecture: [[Presence Management]], [[Presence And Direct Connect]], [[Connection Request Notifications]]
- Impact: A closed peer can appear online, preventing offline request notifications or causing failed direct connect/call attempts.
- Workaround Strategy: Always perform backend presence preflight before call/connect/request actions and fail with a user message if unknown.
- Parallel Progress Path: Work on update, diagnostics, and file/database tasks while presence thresholds are tested.
- Resolution Plan:
  - Define fresh/stale/offline/unknown states.
  - Use session-owned heartbeat and stale-session rejection.
  - Gate direct connect/call/request actions through fresh presence.
  - Add user messages for offline and presence-unknown outcomes.
- Progress 2026-06-03: Direct friend seeding, Connect, connection-request routing, and voice/video call start now resolve backend `online + lastHeartbeat` through one 30 second app freshness window. Phase 05 continuation adds session metadata/state to backend identity snapshots, makes non-`online` presence state offline, routes chat Connect through the shared fresh-presence resolver, blocks network auto-recovery for stale/offline peers, and preserves `presenceExpired` as terminal UI/diagnostic intent until successful explicit reconnect. Phase 08 added protocol contract coverage for session-owned presence shape, `onDisconnect` offline state, and state-aware presence reads. `scripts/run_rain_app_test.ps1` now provides the working Windows Drift/sqlite app-test harness; full `friend_flow_test.dart` passed through it with app-close and stale-presence cases.
- Exit Criteria: App-close, stale heartbeat, unknown presence, online direct connect, and offline request flows pass tests.
- Detection Strategy: Presence diagnostics with heartbeat age, session id, action decision, and user message.

### BLK-009: Offline Request Guardrails Can Spend Quota Or Block Silently

- Status: Open
- Severity: Critical
- Owner: Product/Security
- Type: Product/Security
- Related Risks: R-016, R-020
- Related Roadmap Tasks: TASK-023, TASK-017
- Related Debt: TD-012, TD-020
- Related Architecture: [[Connection Request Notifications]], [[Rules Strategy]], [[Firebase Architecture]]
- Impact: Users can lose request credits for online connect attempts or get denied by Firebase without explanation.
- Workaround Strategy: Disable or avoid offline notification requests in release candidates until confirmation, presence, rules, and messages are tested.
- Parallel Progress Path: Continue normal direct connect, chat, call, and file tasks because online direct connect should not depend on request quota.
- Resolution Plan:
  - Require explicit offline-notification confirmation.
  - Check fresh backend presence before quota/cooldown.
  - Deny online receivers in rules.
  - Show a fixed message for every blocked rule.
  - Count quota only after confirmed offline/stale request creation.
- Exit Criteria: Runtime, adapter, rules, and widget tests cover online, offline, stale, unknown, cancelled, quota exceeded, and confirmation missing.
- Detection Strategy: Request diagnostics, RTDB rules tests, operation counters, blocked-action widget tests.

### BLK-010: Auth Session And Startup Readiness Are Not Production-Safe

- Status: Open, mitigated locally pending release-gate proof
- Severity: Critical
- Owner: Engineering/Product
- Type: Architecture/Product
- Related Risks: R-021, R-022
- Related Roadmap Tasks: [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md)
- Related Debt: TD-021, TD-022
- Related Architecture: [[Authentication]], [AUTHENTICATION_AUDIT.md](../../AUTHENTICATION_AUDIT.md), [STARTUP_SEQUENCE_ANALYSIS.md](../../STARTUP_SEQUENCE_ANALYSIS.md), [STATE_MANAGEMENT_FAILURE_ANALYSIS.md](../../STATE_MANAGEMENT_FAILURE_ANALYSIS.md)
- Impact: Public launch is blocked because logout/account reset can restore stale local identity and startup can render protected app surfaces before auth/runtime readiness.
- Workaround Strategy: Treat current builds as test builds only for auth/session behavior until the hard release gate records the auth/startup/account-deletion regression set. If accounts are reset externally outside the app, clear local app storage before retesting unless the app-owned delete-account path was used.
- Parallel Progress Path: Continue call diagnostics and release-gate work, but do not ship backend-incompatible changes or public builds until auth/session startup is fixed.
- Resolution Plan:
  - Add characterization tests for stale local identity, deleted backend user, failed sign-out, and protected route loading.
  - Add `AuthSessionCoordinator`.
  - Validate Firebase/backend identity before runtime start.
  - Guarantee local session clearing on logout/reset/delete.
  - Move splash/navigation readiness to a global startup gate.
- Progress 2026-06-03 Phase 1: Cached Drift identity is now treated as a candidate. `IdentityController` validates backend account existence and current auth uid ownership before restoring signed-in state, clears local session on deleted/mismatched backend identity, and saves local identity only after backend identity/presence writes during login/register. New tests cover backend deletion, uid mismatch, and backend profile winning over stale local cache.
- Progress 2026-06-03 Phase 2: Runtime logout now clears local session before best-effort backend sign-out, records failed sign-out as diagnostic-only after local clear, clears local session even when a previous app-exit shutdown future exists, and invalidates session-scoped Riverpod providers from `finally`. New tests cover failed backend sign-out and logout-after-app-exit shutdown.
- Progress 2026-06-03 Phase 3: Startup readiness is now a typed `AppStartupState`/`AppStartupPhase` model consumed by `RootScreen`, shell navigation visibility, and router refresh/redirect logic. Tests cover update loading, required update, session validation, signed-out, runtime loading, ready, and session-expired startup phases.
- Progress 2026-06-03 Phase 4: Global startup visual ownership is now above the router shell. `RainApp` uses `MaterialApp.router.builder` to show `RainStartupSurface` instead of the routed child while startup is loading, update-blocked, failed, or session-expired; `RootScreen` reuses the same surface. Tests prove blocked startup states do not insert `RainNavigationShell`, bottom navigation, or navigation rail.
- Progress 2026-06-03 Phase 5: Protected navigation readiness is now explicit. `canRenderProtectedRoutes` blocks settings/search/friend rendering until startup is ready, `_ProtectedRouteGate` provides route-local defense, protected paths redirect to `/` while unresolved, and signed-out auth renders outside `RainNavigationShell` through a standalone Navigator/Overlay. Tests prove protected routes do not render while runtime is loading or signed out.
- Progress 2026-06-03 Phase 6: State lifecycle hardening is complete. `AuthenticatedSession.sessionGeneration` scopes runtime reuse and account-owned providers; logout ends the authenticated session instead of relying on a broad manual invalidation list; request/call/connection/message/file/search/recent providers reject stale runtime generations or reset to empty state. Tests cover session generation changes, recent/search reset, signed-out message stream gating, startup routes, and full Melos analyze/test.
- Progress 2026-06-04 Phase 05: Account deletion is implemented locally. Settings prompts for confirmation plus password reauth; bad-password reauth does not clear the active session; destructive deletion shuts down runtime best-effort, tombstones backend identity, removes account-owned mirrors where authorized, deletes Firebase Auth last, and clears local Drift/authenticated-session state even on backend/Auth partial failure. Follow-up hardening prevents login/upsert/search writes from recreating missing or tombstoned backend identity after Auth succeeds. `dart run melos run analyze` and `dart run melos run test` passed.
- Progress 2026-06-04 release-gate integration: Hard release workflows now run explicit `SCN-AUTH-001` through `SCN-AUTH-004` app tests and Obsidian vault validation. Firebase emulator integration now includes account tombstone cleanup plus surviving-Auth no-recreate proof through `integration_account_deletion_emulator_test.dart`. Local emulator integration passed; cloud proof on the new pushed commit is pending.
- Exit Criteria: Logout always clears local identity, deleted backend account cannot be recreated from local cache, protected app shell never renders before readiness, session-scoped providers do not leak across account cycles, account deletion cannot reopen into a deleted identity, and all paths are covered by tests plus release-gate evidence.
- Detection Strategy: Auth/session widget and runtime tests, diagnostics for session validation failures, and release gate checks for protected-route startup behavior.

## Blocker Review Cadence

- Critical blockers: review before every release workflow.
- High blockers: review at sprint planning and before artifact publication.
- Medium blockers: review before making them release-gate dependencies.

## Blocker Definition Of Done

- Exit criteria are met.
- Related risk status is updated in [[Risk Register]].
- Related debt status is updated in [[Technical Debt Register]].
- Related roadmap task status is updated in [[Audit Resolution Tracker]] or sprint notes.
- Any residual risk is accepted in [[Launch Readiness]].
