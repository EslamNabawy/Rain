# BLOCKERS

Last updated: 2026-08-21

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

Related: [[Risk Register]], [[Risk Categories]], [[Risk Matrix]], [[Blocker Resolution Plan]], [[Launch Blockers]], [[Critical Path]], [[Technical Debt Register]], [[2026-06-05 Senior Audit Remediation Plan]].

## Blocker Rules

- Critical blockers prevent public launch.
- High blockers prevent production readiness unless explicitly accepted.
- Blockers do not prevent unrelated parallel work.
- If a blocker cannot be resolved immediately, use the workaround and continue safe work from [[Parallel Work Streams]].
- If a blocker requires external input, document that dependency and continue independent tasks.

## Active Blockers

## 2026-06-05 Senior Audit Blocker Overlay

Source: [[2026-06-05 Senior Audit Remediation Plan]]

| SAR ID | Blocking Status | Mapped Blockers | Owner | Exit Evidence |
| --- | --- | --- | --- | --- |
| SAR-001 | Release-blocking, partial Phase 3 progress | BLK-001, BLK-002, BLK-005 | Engineering | First Phase 3 slice extracted `CallErrorClassifier` and media adapters; 2026-06-08 Phase 3a grouped extracted voice-call coordinators and added `VoiceCallStateCoordinator`; 2026-06-08 Phase 3b added `VoiceCallPreflightCoordinator` and `VoiceCallReconnectCoordinator`; 2026-06-08 Phase 3c added media, session-state, and signaling-cleanup coordinators and reduced `voice_call_runtime.dart` to 2,917 lines. Remaining exit evidence is lock/lease coordination, command orchestration, full conflict policy ownership, terminal characterization, diagnostics, and device-direction proof. |
| SAR-002 | Release-blocking | BLK-008, BLK-009 | Engineering | Phase 1 local proof added authoritative peer snapshot tests for stale, unknown, fresh, and stale receiver presence; emulator/device proof still required. |
| SAR-003 | Release-blocking | BLK-008, BLK-009 | Engineering/Product | Phase 1 local proof routes chat actions through peer snapshots instead of stale friend booleans; emulator/device proof still required. |
| SAR-004 | Release-blocking | BLK-001, BLK-002, BLK-003 | Engineering/Security | Phase 2 local emulator proof passed for stale/terminal/live locks, malformed writes, denied transitions, and state preservation; device-direction proof remains Phase 10. |
| SAR-005 | Conditional blocker accepted for current scope | BLK-005 if diagnostics/privacy claims imply local secrecy | Security/Product | Option A accepted 2026-06-05 in [[ADR-010]]: local Drift/SQLite storage is plaintext and release/support/privacy claims must not imply local database encryption. |
| SAR-006 | Locally mitigated; production-scale evidence still useful | No direct blocker; maps to scalability debt | Engineering | Drift schema/index migration and pagination validation passed locally on 2026-06-05; low-power/device frame-budget proof remains follow-up evidence. |
| SAR-007 | Locally mitigated; production-scale evidence still useful | No direct blocker; maps to file-transfer debt | Engineering | Phase 7 focused tests passed locally for large receive, slow receiver/backpressure, cancel cleanup, hash mismatch cleanup, disk write failure, and temp cleanup. Real-network/device-scale large-file proof remains follow-up evidence before release-scale closure. |
| SAR-008 | Locally mitigated for covered export privacy; residual taxonomy work | BLK-005, BLK-001 for route/media lifecycle proof | Security/Engineering | Recursive sanitizer/export and failure taxonomy tests passed locally on 2026-06-05; selected-route, first-track, and first-frame diagnostics remain open. |
| SAR-009 | Release-blocking | BLK-006 | DevOps | Release workflow gate parity and artifact evidence. |
| SAR-010 | Locally mitigated governance gap | BLK-006 for release evidence trust | DevOps/Engineering | Phase 9 semantic vault validation passed locally; generated metric reconciliation and fresh cloud release evidence remain future hardening. |
| SAR-011 | Conditional blocker | BLK-006 if demo artifacts are promoted as trusted release artifacts | DevOps/Security | Signing/artifact labeling policy. |
| SAR-012 | Non-blocking now | No direct blocker; performance risk | Engineering/UI | Phase 1 selected immutable chat snapshot landed; rebuild isolation tests remain Phase 6. |

### BLK-001: Voice/Video Call Setup Reliability Is Not Proven

- Status: Mitigating; covered export privacy locally mitigated 2026-06-05
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
- Progress 2026-06-04 terminal cleanup: `rain-diagnostics-2026-06-04T144952-237539Z.json` showed media reaching `connected`, then a Firebase `busy` terminal room and stalled local cleanup that hid the call UI, blocked file transfer, and delayed Windows shutdown. `VoiceCallRuntime` now publishes terminal failed/idle state before bounded cleanup; targeted runtime/contract/terminal friend-flow tests, analyze, and full Melos tests passed. Device-direction smoke proof is still required before closing this blocker.
- Progress 2026-06-05 Phase 3 first slice: `CallErrorClassifier` now owns call failure reason/message/taxonomy/retry classification, and `call_media_session_coordinator.dart` owns app-side audio/video media adapters plus media diagnostics mapping. Focused classifier, media-path, diagnostics-contract, failure-message, analyze, and full Melos tests passed. This reduces runtime concentration but does not close BLK-001 because room reconciliation, lock coordination, command orchestration, full media session ownership, and device-direction proof remain.
- Progress 2026-06-08 Phase 3a: Extracted voice-call coordinators now live under `apps/rain/lib/application/runtime/voice_call/`, and `VoiceCallStateCoordinator` owns pure start-block expiry, session phase/detail/failure mapping, remote media permission mapping, terminal-write failure state, same-live-session guards, and local-end reset policy. Focused coordinator tests, app analyzer, Melos analyze, and full Melos tests passed. BLK-001 remains open because command orchestration, Firebase room reconciliation, lock coordination, media/session orchestration, cleanup, and cross-peer device-direction proof remain.
- Progress 2026-06-08 Phase 3b: `VoiceCallPreflightCoordinator` now owns call-start availability/friend/presence guards and stale retry replacement, and `VoiceCallReconnectCoordinator` now owns reconnecting/failure state plus reconnect grace timers. Focused reconnect/preflight/state/room/terminal coordinator tests passed. BLK-001 remains open because command orchestration, Firebase room reconciliation, lock coordination, media/session orchestration, terminal cleanup, and cross-peer device-direction proof remain.
- Progress 2026-06-08 Phase 3c: `VoiceCallMediaCoordinator` now owns app-side media connection creation, renderer/app-lifecycle failure handling, camera-muted signaling, and video resource cleanup; `VoiceCallSessionStateCoordinator` owns session-state projection and diagnostics recording; `VoiceCallSignalingCleanupCoordinator` owns Firebase room watches, frame/ICE handling, terminal writes, stale cleanup, status timelines, subscription cancellation, and bounded cleanup. `voice_call_runtime.dart` is 2,917 lines and local analyzer/full Melos tests passed. BLK-001 remains open because command orchestration, lock/lease coordination, full call/file conflict policy ownership, and cross-peer device-direction proof remain.
- Progress 2026-06-05 Phase 10 scope: `apps/rain/integration_test/device_media_reality_proof_test.dart` now provides an opt-in real media capture proof through `FlutterWebRTCBridge` and `DefaultCallMediaConnection`. Local environment probes found no attached Android device (`flutter devices` showed Windows/web only; `adb devices` was empty), so no Android or cross-peer media proof was executed. `QA_Medium_API_36_1` exists but was not running. BLK-001 remains release-blocking until Android/Windows direction proof passes or launch scope is explicitly reduced.
- Progress 2026-06-07 deep audit: Android emulator single-device media proof passed for audio and video through the Rain call media stack. Audio-only proof passed with `RAIN_DEVICE_MEDIA_REQUIRE_VIDEO=false`; video-required proof initially timed out behind the Android permission controller, then passed after granting `CAMERA` and `RECORD_AUDIO` to `com.rainapp.rain`. The proof now uses Rain's native Android `rain/media_permissions` method channel before WebRTC capture, so permission ownership is in app/test code instead of external ADB setup. `scripts/run_device_media_proof.ps1` automates emulator launch, debug APK install, permission pregrant, and opt-in media proof execution; latest runner validation reached APK build/install, but the emulator/Flutter tool connection dropped before test execution, so it is not pass evidence. `flutter build apk --debug` and focused Dart analyzer passed after the code fix. This reduces P10-MEDIA risk but does not close BLK-001 because cross-peer Android/Windows call direction proof remains open.
- Exit Criteria: PC-to-mobile and mobile-to-PC voice/video setup have deterministic pass/fail behavior, no stuck connecting state remains, and diagnostics classify the failure source.
- Detection Strategy: Runtime tests, call diagnostics timeline, release smoke logs, and watcher for repeated failed media setup events.

### BLK-002: False Busy And Stale Call Locks Can Block Calls

- Status: Mitigating; local workflow contract proof added 2026-06-05
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
- Progress 2026-06-04 terminal cleanup: A terminal `busy` room can still be a real remote-side outcome, but it no longer leaves the local runtime in an active call state while cleanup stalls. This mitigates the user-visible false file-transfer block; full stale/live/newer lock repair proof remains open.
- Progress 2026-06-05 stale lock reclaim: Firebase and fake voice signaling now use shared `VoiceLockReclaimPolicy` during `createOutgoingCall`. Stale expired locks, caller-owned or orphan-aged missing-room locks, terminal rooms, caller-owned setup rooms, and expired setup rooms are reclaimed; live connected rooms, fresh other-owned setup, mismatched participants, and newer/different locks stay busy. Firebase compare-deletes before cleanup and retries the claim exactly once. A local terminal echo race after locally initiated hangup is fixed so the original hangup path still awaits session/media cleanup. Focused policy/signaling tests, targeted stale-lock app scenarios, `call_retry_policy_test.dart`, analyze, full Melos tests, and vault validation passed.
- Progress 2026-06-05 Phase 2 emulator proof: `.\scripts\ci_run_firebase_emulators.ps1` passed after adding RTDB emulator assertions for terminal leftover lock reclamation, missing inbox cleanup, malformed voice lock/inbox denial, unauthorized transition denial, oversized terminal reason denial, and denied-write state preservation. Backend functions lint/test/audit also passed. Live Firebase/device smoke proof remains separate release evidence.
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
- Progress 2026-06-05 Phase 2 emulator proof: Voice call RTDB rules now have local emulator proof for malformed lock/inbox writes, unauthorized transitions, live-lock preservation after denied cleanup, and terminal leftover lock reclamation. Connection-request quota proof remains tracked separately under BLK-009.
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
- Progress 2026-06-04: The reported missing warning was reproduced as metadata equality: `1.0.6+7` installs saw a `1.0.6+7` Remote Config policy and correctly reported `current`. App and manifests are now `1.0.7+8`, and the checked-in Remote Config template test proves previous `1.0.6+7` installs are `updateRequired`. `Build Rain Apps` run 26963049075 published fresh `rain-test-109-1` Android/Windows artifacts for pushed SHA `f1904e72f1c16773700f0bfa6bcc8ac0fcd7706d`. Closing this blocker still requires deployed Remote Config evidence.
- Progress 2026-06-06: The repeated warning miss after `rain-test-117-1` was another metadata equality case: both the installed app and live policy were `1.0.7+8`. App and manifests are now `1.0.8+9`, `version_metadata_test.dart` proves previous `1.0.7+8` installs are `updateRequired`, `Build Rain Apps` run 27062729519 published `rain-test-118-1`, and live Remote Config version 9 was deployed/read back advertising `1.0.8+9`. Closing still requires installed-app proof that old `1.0.7+8` clients show required update and current `1.0.8+9` clients report current.
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
- Impact: Covered diagnostics exports are safer for user-shared reports; debugging still remains incomplete for selected ICE route, first-track, first-frame, and full media lifecycle failures.
- Workaround Strategy: Keep exports local-only, require sanitizer regression samples for every new private diagnostic field, and avoid raw SDP/ICE/content/path/file/secrets in support reports.
- Parallel Progress Path: Continue call/runtime route and media lifecycle taxonomy while keeping diagnostics sanitization centralized.
- Resolution Plan:
  - [x] Add recursive denylist sanitizer.
  - [x] Add current call failure taxonomy buckets without raw SDP, ICE candidate strings, tokens, ciphertext, message text, or file bytes.
  - [x] Add summaries for Firebase, permission, ICE, TURN, media, and terminal failures.
  - [ ] Add selected route, candidate count, first-track, first-frame, and cleanup-lifecycle summaries without raw payloads.
- Progress 2026-06-05 Phase 4: `DiagnosticsSanitizer` now recursively sanitizes crash diagnostics, debug logs, coalesced event records, write-failure debug output, and final export payloads. Focused diagnostics export/debug-log/classifier tests passed locally.
- Exit Criteria: Export tests prove sensitive values are redacted, failure taxonomy is present, and remaining route/media lifecycle summaries are useful without raw private payloads.
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
  - [x] Define fast artifact workflow vs hard release gate.
  - [x] Require analyze/test/rules/vault validation before publish.
  - [x] Include commit, version, channel, and artifact metadata.
  - [x] Document failure ownership.
  - [ ] Record fresh cloud workflow proof for the changed release path before artifact promotion.
- Progress 2026-06-05 Phase 8: `release.yml` now validates before build/publish and requires Remote Config deploy/readback evidence; publish-capable workflows attach `rain-release-metadata.json`; `rain-test-*` direct-download releases are labeled `TEST ARTIFACT ONLY`; contract tests lock these requirements locally.
- Progress 2026-06-05 Phase 9: `scripts/check_obsidian_vault.ps1` now fails on missing operational owner/priority/evidence fields, stale reviewed dates, unsupported fixed-schema statuses, evidence-ledger gaps, closed blockers without evidence, and P0/P1 items without a next-action-equivalent field. This improves release evidence trust but does not replace the required fresh GitHub Actions proof.
- Exit Criteria: Release workflow blocks publish on failed gates, reports exact failing stage, and a fresh GitHub Actions run proves the changed workflow for the artifact being promoted.
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
- Progress 2026-06-05 Phase 10 scope: Android QA tooling is installed and `test-env.ps1` passed. `apps\rain\qa.appium.json` currently proves only the standalone auth toggle smoke path, not calls/media. The latest saved Rain Appium artifacts from 2026-05-30 timed out in WebDriver, so Appium remains development-supporting evidence only. Phase 10 added an opt-in Flutter integration proof for real mic/camera capture, but it was not executed successfully because no Android endpoint was attached.
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

- Status: Open, auth/account-deletion scope release-gate proven; remaining call/device and broader startup production proof still open
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
- Progress 2026-06-04 release-gate integration: Hard release workflows now run explicit `SCN-AUTH-001` through `SCN-AUTH-004` app tests and Obsidian vault validation. Firebase emulator integration includes account tombstone cleanup plus surviving-Auth no-recreate proof through `integration_account_deletion_emulator_test.dart`. Local emulator integration passed, and `Build Rain Apps` run 26957834309 passed on pushed `dev` SHA `883886a2e81ee370e3641ddcefce8d62942a3566`, publishing `rain-test-108-1`.
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
