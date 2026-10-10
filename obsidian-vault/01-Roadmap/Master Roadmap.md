# Master Roadmap

Last updated: 2026-06-06

## Purpose

This roadmap converts the authoritative findings in [[Original Audit]] into a dependency-driven execution program.

Do not treat this as a new audit. The source of truth is [[Original Audit]]. This note converts those findings into:

Epic -> Feature -> Task -> Subtask

Related: [[Project Home]], [[Current Architecture]], [[Audit Resolution Tracker]], [[Critical Path]], [[30 Day Plan]], [[60 Day Plan]], [[90 Day Plan]], [[Parallel Work Streams]], [[Launch Blockers]], [[Quick Wins]], [[High-Risk Work]], [[2026-06-05 Senior Audit Remediation Plan]].

## Roadmap Rules

- P0 blocks public release.
- P1 blocks production readiness but may not block internal test artifacts.
- P2 improves maintainability, scale, or operational confidence.
- Every task must have dependencies, estimated effort, success criteria, and definition of done.
- Every implementation task must update related notes, especially [[Project Memory]], [[Technical Debt Register]], [[Risk Register]], and [[Audit Resolution Tracker]].
- No roadmap item is complete until validation is recorded.

## Active Senior Audit Remediation Overlay

Source: [[2026-06-05 Senior Audit Remediation Plan]]

This work is the active execution overlay created from the 2026-06-05 senior audit. It does not replace [[Original Audit]]; it binds fresh repository/vault findings to the existing roadmap, blocker, risk, debt, and validation system.

| Phase | Priority | Status | Dependencies | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| Phase 0: Evidence Lock And Planning Hygiene | P0 | Complete 2026-06-05 | [[2026-06-05 Senior Audit Remediation Plan]], [[Audit Resolution Tracker]], [[Technical Debt Register]], [[Risk Register]], [[BLOCKERS]] | SAR-001 through SAR-012 are visible in tracker/risk/debt/blocker notes with owner, priority, evidence, and release impact. | Vault validation passes and [[Project Metrics]] records branch, commit, command, result, and date. |
| Phase 1: Peer Presence And Action Authority | P0 | Complete local proof 2026-06-05 | Phase 0, [[Presence Management]], [[Connection Request Notifications]] | Connect, call, and offline request actions use one authoritative peer connectivity snapshot. | `dart pub get`, `dart run melos run analyze`, and `dart run melos run test` passed; Firebase emulator/rules quota proof remains Phase 2. |
| Phase 2: Firebase Call Lock And Rule Proof | P0 | Complete rule/emulator proof 2026-06-05 | Phase 0, [[Lease Management]], [[Rules Strategy]], [[Emulator Test Matrix]] | Stale/live/newer call locks and malformed call transitions are proven by emulator/rules tests. | Firebase emulator script, backend functions lint/test/audit, Melos analyze/test, and vault validation passed. |
| Phase 3: Voice Call Runtime Decomposition | P0 | Partial local proof 2026-06-09 | Phases 1-2, [[VoiceCallRuntime Refactor]], [[Call State Machine]] | Call command, media, lock, room reconciliation, terminal reconciliation, peer UI projection, renderer failure authority, error classification, preflight, reconnect, session-state, and signaling-cleanup ownership are split or explicitly bounded. | Characterization tests pass before and after extraction; 2026-06-08 focused state/room/terminal/reconnect/preflight coordinator tests passed locally, Phase 3c app analyze plus full Melos tests passed, and 2026-06-09 Phase 4 converted runtime extensions from `part of` files to proper imports/exports. Full lock/lease/command extraction and device proof remain. |
| Phase 4: Diagnostics Privacy And Failure Taxonomy | P0/P1 | Mitigated locally 2026-06-05 | Phase 0, [[Diagnostics Sanitization]], [[Privacy Review]] | Diagnostics classify failures without leaking sensitive values. | Recursive sanitizer/export and failure taxonomy tests passed locally; every new private diagnostics field still needs sanitizer regression proof. |
| Phase 5: Local Data Security Decision | P1 | Not Started | Phase 0, [[Security Roadmap]], [[Privacy Review]] | Local plaintext storage is either accepted explicitly or encryption work is planned separately. | Security/product docs match implementation truth. |
| Phase 6: Database Scalability | P1 | Mitigated locally 2026-06-05 | Phase 0, [[Index Strategy]], [[Pagination Strategy]], [[Migration Plan]] | Message queries are indexed and conversation loading is bounded. | Drift migration, index, store pagination, provider pagination, workspace analyze/test, and vault validation passed locally; low-power/device frame-budget proof remains follow-up evidence. |
| Phase 7: File Transfer Streaming And Backpressure | P1 | Mitigated locally 2026-06-05 | Phase 0, [[Streaming Architecture]], [[Backpressure Strategy]] | Large transfers use bounded IO/memory and clean failure paths. | Focused large receive, slow receiver/backpressure, cancel, hash failure, disk write failure, and temp cleanup tests passed locally; device-scale real-network proof remains follow-up evidence. |
| Phase 8: Release Gate Unification | P0/P1 | Mitigated locally 2026-06-05 | Phase 0, [[Release Gates]], [[CI-CD Roadmap]] | No release path can publish without hard validation evidence. | Local workflow contract tests require hard gates, metadata, and production Remote Config evidence; fresh cloud workflow proof remains required per release. |
| Phase 9: Obsidian Vault Semantic Enforcement | P1 | Mitigated locally 2026-06-05 | Phase 0, [[Engineering System Flaw Remediation Plan]] | Vault checks semantic truth, not only links/files. | `scripts/check_obsidian_vault.ps1` now enforces operational owner/priority/evidence/review fields, closed-blocker evidence, and P0/P1 next-action coverage; vault validation passed locally. |
| Phase 10: Device And Media Reality Proof | P0 | Scoped/blocked 2026-06-05 | Phases 1-4, [[Emulator Test Matrix]], [[Scenario Coverage Matrix]] | Voice/video reliability is proven across target device directions or explicitly scoped down. | Target matrix and opt-in real media capture proof exist; Android endpoint was not attached, so device/cross-peer evidence remains required before public release. |

## Active Tracing Overlay

Source: [[ADR-011]] and `docs/plans/2026-08-27-rain-tracing-implementation-guide.md`.

| Phase | Priority | Status | Dependencies | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| Phase 11: Trace Context Wiring (slice 1) | P2 | Complete locally 2026-08-29 | [[Diagnostics And Logging]], [[Diagnostics Sanitization]], [[Current Architecture]] | `IdentityController.register` and `RainRuntimeController._startCall` share one `traceId` for the entire flow; `AppNavigationObserver` records every GoRouter push/pop/replace with the active `traceId`; `ThrottledProviderObserver` replaces `RainDebugProviderObserver` in `RainStartupApp`. | All 4 Melos packages pass `dart run melos run analyze` and `dart run melos run test`. Obsidian vault records the slice in [[Project Memory]], [[Risk Register]] (R-023), [[Technical Debt Register]] (TD-024), and [[Recommended Next Actions]]. [[ADR-011]] documents the scope cut: no Drift persistence, no `/debug/traces` overlay, no heartbeat / presence / signaling-write traceId in this slice. |
| Phase 12: Trace Context Coverage (slice 2) | P2 | Partially merged 2026-08-29 | Phase 11, [[Diagnostics And Logging]] | Heartbeat and presence calls (`_sendHeartbeatSafely`, `_setPresenceOnlineSafely`, `_setPresenceOfflineSafely`, `_fetchPeerPresenceSnapshot`) in `RainRuntimeController` wrap their body in `TraceContext.runAsync` so all `presence/*` and `connection/*` events share one `traceId`. | Each affected call site wraps in `TraceContext.runAsync`; `presence/heartbeat_sent`, `presence/heartbeat_failed`, `presence/presence_marked_online`, `presence/presence_marked_offline`, and `presence/backend_presence_stale_resolved_offline` all carry the same `traceId` for the originating user action. `dart run melos run analyze` and `dart run melos run test` SUCCESS across all 4 packages (1145 tests). Residual scope: traceId in `brain.connect` / `brain.send` data-peer signaling writes, voice signaling writes (`writeVoiceOffer` / `writeVoiceAnswer` / `writeICE` in `protocol_brain` adapter), and file transfer chunk pipeline in `file_transfer_runtime.dart`. The upstream `_startCall` traceId already covers the voice-signaling flow at the call boundary, so per-write traceIds are lower-priority. |
| Phase 13: Provider Throttle Hardening (slice 3) | P2 | Merged 2026-08-29 | Phase 11, [[Peer Chat]], [[Call State Machine]] | `ThrottledProviderObserver.hashForDedupe` produces structural hashes for `ConnectionDiagnostics`, `PeerConnectivitySnapshot`, and `Map<String, PeerConnectivitySnapshot>` so identity-equal-but-content-equal updates dedupe correctly. | 10 new tests in `apps/rain/test/throttled_provider_observer_test.dart` lock structural equality for both value types, the map canonicalization across insertion order, status-key changes, `peerId` changes, `manualDisconnected` changes, and `null` handling. `dart run melos run analyze` and `dart run melos run test` SUCCESS across all 4 packages; `rain` test count went 742 -> 752. |
| Phase 14: Drift Event Persistence And Debug Overlay (slice 4) | P3 | Not started | Phase 11, [[Database Architecture]] | `app_events` Drift table indexed on `(traceId, recordedAt)` with 7-day TTL; `/debug/traces` page lists traces with span waterfall; `DiagnosticsSheet` floating widget shows live tail filtered by `traceId`/`category`. | Drift migration and query tests pass; overlay is gated behind `kDebugMode` or `updateChannel == 'demo'`. Requires sanitizer regression samples for every new persisted field. |

## Active Auth/Startup Remediation Overlay

Source: [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md)

This work is a P0 launch-blocking remediation stream discovered after the original roadmap baseline. It is tracked in [[Audit Resolution Tracker]], [[Authentication]], [[Technical Debt Register]], [[Risk Register]], and [[BLOCKERS]].

| Phase | Priority | Status | Dependencies | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| Phase 1: Authentication Source Of Truth | P0 | Done 2026-06-03 | [AUTHENTICATION_AUDIT.md](../../AUTHENTICATION_AUDIT.md), [[Authentication]] | Deleted or wrong-owner backend accounts do not restore from cached Drift identity. | Backend validation tests pass; docs updated; one phase commit created. |
| Phase 2: Deterministic Logout | P0 | Done 2026-06-03 | Phase 1 | Logout clears local session/runtime state even when backend cleanup fails. | Runtime logout clears local session before best-effort sign-out; logout after prior app-exit shutdown still clears local session; provider invalidation runs in `finally`; tests cover failed sign-out and existing shutdown. |
| Phase 3: Startup State Machine | P0 | Done 2026-06-03 | Phase 1, Phase 2 | Startup phases are explicit and repeatable. | `AppStartupState` centralizes update/session/runtime/session-expired/router readiness; `RootScreen` and shell navigation consume it; tests cover loading, required update, session validation, signed-out, runtime loading, ready, and expired-session phases. |
| Phase 4: Global Splash Architecture | P0 | Done 2026-06-03 | Phase 3 | Main UI cannot render before startup completes. | `RainApp` gates the routed child through `RainStartupSurface` while `AppStartupState.blocksRoutedSurface` is true; tests prove loading, required-update, and failed startup states render no `RainNavigationShell`, bottom navigation, or rail. |
| Phase 5: Navigation Readiness | P0 | Done 2026-06-03 | Phase 3, Phase 4 | Protected routes only exist after auth/runtime readiness. | `AppStartupState.canRenderProtectedRoutes` guards route rendering; unresolved protected paths redirect to `/`; settings/search/friend pages use a route-local guard; signed-out auth renders outside the app shell with its own Navigator/Overlay; route tests prove protected content cannot render while loading or signed out. |
| Phase 6: State Lifecycle Hardening | P0 | Done 2026-06-03 | Phase 2, Phase 3 | Session-scoped providers cannot leak account state across login/logout cycles. | `AuthenticatedSession.sessionGeneration` scopes runtime/provider ownership; account-owned providers reset on session end/change; tests cover generation changes, recent/search reset, signed-out message streams, startup routes, and full Melos validation. |
| Root Phase 05: Account Deletion Workflow | P1 | Done 2026-06-04 | Phase 1, Phase 2, Phase 6 | User can delete an account from the app and cannot reopen into the deleted identity locally. | Settings delete-account UI, signaling adapter contract, Firebase reauth/delete/tombstone cleanup, runtime/provider destructive-session handling, no-recreate login/upsert/search guards, and local tests are implemented. `dart run melos run analyze` and `dart run melos run test` passed. Hard release-gate integration and optional Firebase emulator/device cleanup proof remain next. |

## Epic Map

| Epic | Goal | Roadmap Window | Primary Components |
| --- | --- | --- | --- |
| E01: [[Architecture Stabilization Epic]] | Separate overloaded runtime/UI ownership. | Days 1-30 | [[VoiceCallRuntime Refactor]], [[Current Architecture]], [[Target Architecture]] |
| E02: [[Signaling Reliability Epic]] | Eliminate false busy, stale call state, and unclear call failures. | Days 1-45 | [[Signaling Architecture]], [[Lease Management]], [[Call State Machine]], [[Presence Management]] |
| E03: [[Database Scalability Epic]] | Make local persistence scale beyond small test accounts. | Days 31-60 | [[Database Architecture]], [[Index Strategy]], [[Pagination Strategy]], [[Migration Plan]] |
| E04: [[File Transfer Optimization Epic]] | Make large transfers safe under memory and channel pressure. | Days 31-60 | [[Streaming Architecture]], [[Backpressure Strategy]] |
| E05: [[Security Hardening Epic]] | Harden rules, diagnostics privacy, and Firebase cost controls. | Days 1-75 | [[Security Roadmap]], [[Rules Strategy]], [[Diagnostics Sanitization]], [[Firebase Architecture]] |
| E06: [[CI-CD Modernization Epic]] | Make releases fast, validated, and traceable. | Days 31-90 | [[CI-CD Roadmap]], [[Release Gates]], [[Coverage Dashboard]] |
| E07: [[Production Validation Epic]] | Prove release readiness through tests and documented gates. | Days 1-90 | [[Emulator Test Matrix]], [[Launch Readiness]], [[Production Readiness]] |

## Audit Finding Work Breakdown

### E01: Architecture Stabilization

#### Feature AS-01: Runtime Responsibility Split

##### TASK-001: Extract `VoiceCallRuntime` into call coordinators

- Audit finding: 1. `VoiceCallRuntime` has too many responsibilities.
- Priority: P0
- Dependencies: [[Current Architecture]], [[VoiceCallRuntime Refactor]], [[Test Strategy]]
- Estimated effort: 5 days
- Affected architecture: [[CallStartCoordinator]], [[CallLeaseManager]], [[CallMediaCoordinator]], [[CallTerminalReconciler]], [[CallDiagnosticsRecorder]]
- Success criteria: Call start, media setup, lease handling, terminal reconciliation, and diagnostics are separable and testable.
- Definition of done: Coordinator interfaces exist, old behavior is covered by targeted tests, no duplicate runtime truth is introduced, and [[Current Architecture]] is updated.
- Subtasks:
  - [x] TASK-001.1 Define coordinator boundaries and method contracts.
  - [x] TASK-001.2 Move diagnostics-only helpers into [[CallDiagnosticsRecorder]].
  - [/] TASK-001.3 Move start eligibility into [[CallStartCoordinator]]; friend/presence availability and stale retry replacement are extracted, while file/call conflict policy remains.
  - [ ] TASK-001.4 Move lease creation/repair into [[CallLeaseManager]].
  - [/] TASK-001.5 Move media capture/session ownership into [[CallMediaCoordinator]]; media connection creation, renderer lifecycle, app lifecycle failure handling, camera-muted signaling, and video resource cleanup are extracted, while command-level media start/end orchestration remains.
  - [/] TASK-001.6 Move terminal state cleanup into [[CallTerminalReconciler]]; terminal-session decisions, terminal writes, status timelines, stale cleanup, and bounded cleanup are extracted, while lock/lease ownership and some command sequencing remain.
  - [x] TASK-001.7 Add unified peer status projection for split call/data/presence UI truth.

#### Feature AS-02: Call Surface Single Source

##### TASK-019: Centralize call surface rendering

- Audit finding: 11. Call UI must use a single surface model.
- Priority: P1
- Dependencies: TASK-003, [[Voice Calls]], [[Video Calls]], [[Target Architecture]]
- Estimated effort: 4 days
- Affected architecture: [[Frontend Architecture]], [[Voice Calls]], [[Video Calls]]
- Success criteria: UI renders only one valid call surface at a time.
- Definition of done: Widget tests prove no duplicate bars, no unsafe overlays, and consistent voice/video control model.
- Subtasks:
  - [ ] TASK-019.1 Define call surface rendering contract.
  - [ ] TASK-019.2 Remove or make unreachable duplicate call surfaces.
  - [ ] TASK-019.3 Add widget tests for fullscreen, minimized bar, video PiP, ended, and failed states.
  - [ ] TASK-019.4 Link UI state documentation to [[Call State Machine]].

#### Feature AS-03: Provider Boundary Cleanup

##### TASK-020: Stabilize Home and Chat provider boundaries

- Audit finding: 19. Riverpod provider boundaries should avoid broad UI rebuilds.
- Priority: P2
- Dependencies: TASK-009, TASK-019, [[Frontend Architecture]]
- Estimated effort: 4 days
- Affected architecture: [[Frontend Architecture]], [[Current Architecture]]
- Success criteria: Message updates, connection updates, diagnostics, and call state changes update only relevant UI regions.
- Definition of done: Widget/provider tests prove rebuild isolation for chat list, header, call controls, and friends panel.
- Subtasks:
  - [ ] TASK-020.1 Identify broad provider watches in Home/Chat.
  - [ ] TASK-020.2 Replace broad watches with selected state slices.
  - [ ] TASK-020.3 Add repaint/rebuild regression tests.
  - [ ] TASK-020.4 Record performance implications in [[Technical Debt Register]].

### E02: Signaling Reliability

#### Feature SR-01: Call Lease Repair

##### TASK-002: Implement atomic call lease repair

- Audit finding: 2. Call lease and terminal state handling can create false busy and stuck call states.
- Priority: P0
- Dependencies: TASK-001, [[Lease Management]], [[Firebase Architecture]], [[Rules Strategy]]
- Estimated effort: 4 days
- Affected architecture: [[CallLeaseManager]], [[CallTerminalReconciler]], [[Signaling Architecture]]
- Success criteria: Stale, terminal, missing, corrupt, and caller-owned failed setup locks repair once before busy is shown.
- Definition of done: Emulator/fake-adapter tests prove live locks stay busy, stale locks repair, and newer locks are never deleted.
- Progress 2026-06-04: A diagnostic-driven terminal `busy` case no longer leaves local runtime state active while media/session cleanup stalls. This reduces false local busy/file-transfer blocking, but full stale/live/newer lock repair proof remains open.
- Subtasks:
  - [ ] TASK-002.1 Define matching-lock ownership rules by `callId`.
  - [ ] TASK-002.2 Implement pair-lock repair tests.
  - [ ] TASK-002.3 Implement user-lock repair tests.
  - [ ] TASK-002.4 Add diagnostics for repair action and result.
  - [ ] TASK-002.5 Update [[Lease Management]].

#### Feature SR-02: Explicit Call State Machine

##### TASK-003: Enforce explicit call phase state machine

- Audit finding: 14. Async cancellation and terminal cleanup need stricter ownership.
- Priority: P0
- Dependencies: TASK-001, TASK-002, [[Call State Machine]]
- Estimated effort: 4 days
- Affected architecture: [[Call State Machine]], [[CallTerminalReconciler]], [[Voice Calls]], [[Video Calls]]
- Success criteria: Incoming, outgoing, connecting, active, reconnecting, ending, failed, and ended states are explicit and terminal-safe.
- Definition of done: No call can remain connecting past timeout; terminal Firebase room beats late frames; runtime returns to idle after terminal cleanup.
- Progress 2026-06-04: Terminal reconciliation now publishes failed/idle UI state before bounded WebRTC/session cleanup, and regression tests cover state-before-cleanup plus file-transfer guard recovery after failed terminal calls. Remaining work is extracting the explicit state machine and adding device-direction proof.
- Progress 2026-06-06: Live video renderer failure now writes terminal failed call state with `videoRendererFailed`; late local session idle after terminal failure cannot overwrite failed UI. Unified peer status projection prevents stale data lanes or connected data sessions from showing false Connected when call state is failed/recovering. Remaining work is full state-machine extraction and device-direction proof.
- Subtasks:
  - [ ] TASK-003.1 Define allowed transitions.
  - [ ] TASK-003.2 Add timeout-to-terminal rules.
  - [ ] TASK-003.3 Add late-frame ignore path.
  - [ ] TASK-003.4 Add runtime tests for voice and video terminal behavior.

#### Feature SR-03: Presence Freshness

##### TASK-006: Harden presence and app-close detection

- Audit finding: 3. Presence freshness can lag behind app close or stale sessions.
- Priority: P0
- Dependencies: [[Presence Management]], [[Firebase Architecture]], [[Rules Strategy]]
- Estimated effort: 3 days
- Affected architecture: [[Presence Management]], [[Presence And Direct Connect]], [[Connection Request Notifications]]
- Success criteria: Stale/offline peers cannot be called or direct-connected as online; offline request notification eligibility updates from fresh backend state.
- Definition of done: Tests cover stale heartbeat, old session heartbeat, app close, network loss, and manual disconnect.
- Progress 2026-06-03: Stale raw-online backend identity records are now resolved offline before local friend seeding, direct Connect, connection-request routing, or voice/video call start. Phase 05 continuation now carries session metadata in backend identity snapshots, treats non-`online` presence state as offline, routes the chat Connect button through the shared fresh-presence resolver, blocks auto-recovery when backend presence is stale/offline, and preserves `presenceExpired` as a terminal peer intent until an explicit successful reconnect. Phase 08 added a Firebase contract regression for session-owned presence, `onDisconnect` offline state, and state-aware presence reads. `scripts/run_rain_app_test.ps1` now runs isolated Windows app tests from `apps/rain`; full `friend_flow_test.dart` passed through the wrapper with 120 passing tests and 10 skipped legacy control-channel cases.
- Subtasks:
  - [ ] TASK-006.1 Define freshness thresholds.
  - [x] TASK-006.2 Validate session-owned heartbeat behavior.
  - [x] TASK-006.3 Add or run full app-close and stale-session cases under a working Drift/sqlite test harness.
  - [x] TASK-006.4 Update [[Presence Management]].

#### Feature SR-04: Watch Stream Resilience

##### TASK-007: Make Firebase watch streams non-poisoning

- Audit finding: 5. Watch streams must survive corrupt room or inbox data.
- Priority: P1
- Dependencies: [[Firebase Architecture]], [[Diagnostics Sanitization]]
- Estimated effort: 2 days
- Affected architecture: [[Signaling Architecture]], [[Firebase Architecture]]
- Success criteria: Malformed room/inbox records do not crash or close app streams.
- Definition of done: Tests inject corrupt timestamps, malformed inbox entries, and missing rooms; watcher continues after cleanup/ignore.
- Subtasks:
  - [ ] TASK-007.1 Add corrupt inbox parser/cleanup test.
  - [ ] TASK-007.2 Add corrupt room cleanup-only parse test.
  - [ ] TASK-007.3 Record diagnostics without raw payloads.

#### Feature SR-05: WebRTC Failure Classification

##### TASK-004: Add ICE and TURN health classification

- Audit finding: 13. WebRTC ICE/TURN failure classification is incomplete.
- Priority: P1
- Dependencies: TASK-001, [[Signaling Architecture]], [[CallDiagnosticsRecorder]]
- Estimated effort: 3 days
- Affected architecture: [[CallDiagnosticsRecorder]], [[Signaling Architecture]], [[Voice Calls]], [[Video Calls]]
- Success criteria: Diagnostics classify candidate count, selected route, relay/direct route, first frame, permission, Firebase, ICE, TURN, and media failures.
- Definition of done: Diagnostics export includes a sanitized call setup timeline and test coverage for failure taxonomy.
- Progress 2026-06-03: Runtime now keeps a bounded Firebase room status timeline per call and includes it in `VoiceCallDiagnostics`; remote terminal-room failure reconciliation records diagnostics even when the local side only observes the Firebase terminal room. Phase 08 added local regressions for WebRTC transceiver/SDP native error sanitization, Firebase permission-denied setup messages, network-loss messages, terminal-write ordering diagnostics, and already-terminal cleanup classification.
- Subtasks:
  - [ ] TASK-004.1 Define call setup timeline schema.
  - [ ] TASK-004.2 Capture local/remote candidate counts.
  - [ ] TASK-004.3 Capture selected route and TURN readiness.
  - [ ] TASK-004.4 Add taxonomy tests.

#### Feature SR-06: Media Capture Ordering

##### TASK-013: Validate media capture ordering

- Audit finding: 2 and 14. Call setup can fail or leave stuck state when media/signaling order is wrong.
- Priority: P0
- Dependencies: TASK-001, TASK-003, [[CallMediaCoordinator]]
- Estimated effort: 4 days
- Affected architecture: [[CallMediaCoordinator]], [[Voice Calls]], [[Video Calls]]
- Success criteria: Permission/capture failure terminates cleanly and releases Firebase locks.
- Definition of done: Tests simulate denied mic/camera, disposed transceiver/renderer, media timeout, and successful cleanup.
- Progress 2026-06-03: Phase 08 added focused regressions for disposed transceiver/SDP native errors mapping to media failure, failed media sessions writing terminal Firebase state before session disposal, and failed call suite state rendering retry/close instead of remaining in connecting UI. Full media timeout and permission/capture cleanup tests remain open.
- Subtasks:
  - [ ] TASK-013.1 Define audio/video capture preflight.
  - [ ] TASK-013.2 Add cleanup on capture failure.
  - [ ] TASK-013.3 Add media timeout tests.
  - [ ] TASK-013.4 Update [[CallMediaCoordinator]].

### E03: Database Scalability

#### Feature DB-01: Index Strategy

##### TASK-008: Add Drift index migration

- Audit finding: 8. Local database needs index validation.
- Priority: P1
- Dependencies: [[Database Architecture]], [[Index Strategy]], [[Migration Plan]]
- Estimated effort: 3 days
- Affected architecture: [[Database Architecture]], [[Database Schema]]
- Success criteria: Conversation, unread, transfer, friend, and queue queries have explicit index coverage.
- Definition of done: Migration tests pass from current schema and query behavior is documented.
- Progress 2026-06-05: Drift schema v6 adds named indexes for message conversation reads, queued-message drain/recovery, file-transfer peer/message/state lookup, and friend display ordering. New-schema and v5-to-v6 migration tests pass locally.
- Subtasks:
  - [x] TASK-008.1 Identify critical query paths.
  - [x] TASK-008.2 Add index migration.
  - [x] TASK-008.3 Add migration tests.
  - [x] TASK-008.4 Update [[Index Strategy]].

#### Feature DB-02: Conversation Pagination

##### TASK-009: Implement conversation pagination

- Audit finding: 8. Local data must scale beyond small conversations.
- Priority: P1
- Dependencies: TASK-008, [[Pagination Strategy]]
- Estimated effort: 4 days
- Affected architecture: [[Database Architecture]], [[Peer Chat]], [[Frontend Architecture]]
- Success criteria: Initial conversation load is bounded and older messages load on demand.
- Definition of done: Widget/provider tests prove pagination and no full-list rebuild on append/page load.
- Progress 2026-06-05: `MessageStore` now exposes bounded live-tail and cursor page APIs. `MessagesController` starts with the default 50-message live tail and merges older local pages on pull-to-refresh. Provider tests cover bounded initial load, older-page loading, ordering, and duplicate prevention. Device frame-budget proof remains open.
- Subtasks:
  - [x] TASK-009.1 Define page window and anchor behavior.
  - [x] TASK-009.2 Add paginated store query.
  - [x] TASK-009.3 Update chat provider.
  - [x] TASK-009.4 Add pagination tests.

### E04: File Transfer Optimization

#### Feature FT-01: Persistent Receive Streaming

##### TASK-010: Use persistent file receive sink

- Audit finding: 7. File transfer needs stronger streaming.
- Priority: P1
- Dependencies: [[Streaming Architecture]], [[File Transfer]]
- Estimated effort: 4 days
- Affected architecture: [[Streaming Architecture]], [[File Transfer]]
- Success criteria: Incoming chunks stream to a temp file without holding large payloads in memory.
- Definition of done: Large-file tests pass under bounded memory and failed transfers clean temp paths.
- Progress 2026-06-05: Incoming file chunks now write through one persistent per-transfer temp-file sink in `file_transfer_runtime.dart`. Complete, cancel, failure, network loss, and shutdown close active receive sinks; hash mismatch, disk write failure, invalid chunks, and cancellation clean temp files. Focused `friend_flow_test.dart` cases prove large receive, cancel cleanup, hash mismatch cleanup, and disk write failure behavior.
- Subtasks:
  - [x] TASK-010.1 Define temp file lifecycle.
  - [x] TASK-010.2 Stream chunks into persistent sink.
  - [x] TASK-010.3 Add cleanup on cancel/failure.
  - [x] TASK-010.4 Add large-transfer tests.

#### Feature FT-02: Data Channel Backpressure

##### TASK-011: Add data-channel send backpressure gate

- Audit finding: 7. File transfer needs stronger backpressure.
- Priority: P1
- Dependencies: TASK-010, [[Backpressure Strategy]], [[File Transfer]]
- Estimated effort: 3 days
- Affected architecture: [[Backpressure Strategy]], [[Streaming Architecture]]
- Success criteria: Sender pauses when buffered amount exceeds budget and resumes when safe.
- Definition of done: Slow-receiver tests prove bounded buffered amount and transfer recovery/termination behavior.
- Progress 2026-06-05: File-transfer backpressure now uses shared `rain_core` protocol constants for chunk size, high/low watermarks, poll interval, and timeout. The sender waits on `SessionManager.bufferedAmount` before each file chunk and records privacy-safe wait/complete/timeout diagnostics. Focused `friend_flow_test.dart` scripts high-to-low buffered amounts and proves binary send waits until drain.
- Subtasks:
  - [x] TASK-011.1 Define high/low water marks.
  - [x] TASK-011.2 Wire send loop to backpressure.
  - [x] TASK-011.3 Add slow receiver tests.
  - [x] TASK-011.4 Update [[Backpressure Strategy]].

### E05: Security Hardening

#### Feature SEC-01: Firebase Rule Coverage

##### TASK-005: Expand Firebase rule coverage

- Audit finding: 4 and 15. Firebase rules need broader emulator coverage and must prevent malformed or unauthorized signaling writes.
- Priority: P0
- Dependencies: [[Rules Strategy]], [[Emulator Coverage]], [[Firebase Architecture]]
- Estimated effort: 4 days
- Affected architecture: [[Firebase Architecture]], [[Security Roadmap]]
- Success criteria: Rules tests cover allow/deny branches for auth, presence, friendships, signaling rooms, voice calls, locks, inboxes, requests, and metadata.
- Definition of done: Emulator/rules tests run in the hard release gate or documented local equivalent.
- Subtasks:
  - [ ] TASK-005.1 Inventory critical RTDB branches.
  - [ ] TASK-005.2 Add allowed write tests.
  - [ ] TASK-005.3 Add denied malformed/unauthorized tests.
  - [ ] TASK-005.4 Wire or document gate execution.

#### Feature SEC-02: Diagnostics Privacy

##### TASK-014: Strengthen diagnostics sanitization

- Audit finding: 9. Diagnostics must be useful without exposing sensitive data.
- Priority: P1
- Dependencies: [[Diagnostics Sanitization]], [[Privacy Review]]
- Estimated effort: 2 days
- Affected architecture: [[Diagnostics And Logging]], [[Security Roadmap]]
- Success criteria: Sensitive keys and payload-like values are recursively redacted.
- Definition of done: Sanitizer tests cover tokens, passwords, SDP, ICE candidates, ciphertext, message text, file bytes, nested maps, and lists.
- Progress 2026-06-05: `DiagnosticsSanitizer` is now the central recursive sanitizer for crash diagnostics, debug logs, coalesced records, write-failure debug output, and final export payloads. Focused diagnostics export, debug log, and call taxonomy tests passed locally; new private diagnostics fields still require redaction samples.
- Subtasks:
  - [x] TASK-014.1 Define denylist.
  - [x] TASK-014.2 Add recursive sanitizer tests.
  - [x] TASK-014.3 Verify export summaries remain useful.

#### Feature SEC-03: Firebase Cost Guardrails

##### TASK-017: Add Firebase cost and event budgets

- Audit finding: 17. Firebase cost counters should be tracked because Spark/free tier is a hard constraint.
- Priority: P1
- Dependencies: [[Firebase Architecture]], [[Rules Strategy]], [[Diagnostics And Logging]]
- Estimated effort: 2 days
- Affected architecture: [[Firebase Architecture]], [[Release Gates]]
- Success criteria: Firebase operation counters and budgets exist for presence, calls, ICE, requests, and update checks.
- Definition of done: Diagnostics export includes counters and docs define expected budget thresholds.
- Subtasks:
  - [ ] TASK-017.1 Define budget categories.
  - [ ] TASK-017.2 Add counter summary tests.
  - [ ] TASK-017.3 Update [[Firebase Architecture]].

#### Feature SEC-04: Offline Request Guardrails

##### TASK-023: Enforce offline-only connection request messaging

- Audit finding: 16. Connection request notification limits must be offline-only and message every blocked action.
- Priority: P0
- Dependencies: [[Connection Request Notifications]], [[Presence Management]], [[Rules Strategy]]
- Estimated effort: 3 days
- Affected architecture: [[Connection Request Notifications]], [[Firebase Architecture]]
- Success criteria: Online direct connect never consumes offline request quota; blocked actions always show a user message.
- Definition of done: Runtime, adapter, rules, and widget tests cover online, offline, stale, unknown, cancelled, quota-exceeded, and confirmation-required cases.
- Subtasks:
  - [ ] TASK-023.1 Verify fresh-presence decision order.
  - [ ] TASK-023.2 Add confirmation-required tests.
  - [ ] TASK-023.3 Add rules tests for online receiver denial.
  - [ ] TASK-023.4 Update user-message matrix.

### E06: CI/CD Modernization

#### Feature CI-01: Release Gate Parity

##### TASK-015: Turn analyzer/test/rules warnings into release blockers

- Audit finding: 10. Release workflows need clearer hard gates.
- Priority: P1
- Dependencies: [[CI-CD Roadmap]], [[Release Gates]], [[Test Strategy]]
- Estimated effort: 2 days
- Affected architecture: [[Release Gates]], [[Coverage Dashboard]]
- Success criteria: Release artifact jobs cannot publish when analyze, tests, vault validation, or Firebase rules gates fail.
- Definition of done: Workflow status clearly identifies failing gate and artifact output references exact commit/version.
- Subtasks:
  - [x] TASK-015.1 Define hard gate matrix.
  - [x] TASK-015.2 Update workflow dependencies.
  - [x] TASK-015.3 Add release gate documentation.
- Progress 2026-06-05: Phase 8 local contract proof added metadata, production Remote Config evidence requirements, and validate-first stable publishing. Fresh GitHub Actions proof remains required before promoting any specific artifact.

#### Feature CI-02: Workflow Ownership

##### TASK-016: Consolidate overlapping workflows

- Audit finding: 10. Release workflows need faster test artifact paths and less duplication.
- Priority: P2
- Dependencies: TASK-015, [[CI-CD Roadmap]]
- Estimated effort: 2 days
- Affected architecture: [[Release Gates]], [[CI-CD Roadmap]]
- Success criteria: Fast test build, hard release gate, PR gate, and docs gate each have clear purpose.
- Definition of done: Workflow map is documented and duplicate/conflicting logic is reduced or explicitly justified.
- Subtasks:
  - [ ] TASK-016.1 Map workflow ownership.
  - [ ] TASK-016.2 Separate fast artifacts from hard release.
  - [ ] TASK-016.3 Document artifact URLs and retention.

### E07: Production Validation

#### Feature PV-01: Update Version Validation

##### TASK-012: Fix strict update version validation

- Audit finding: 6. Update version validation has reported old-version prompt failures.
- Priority: P0
- Dependencies: [[Version And Updates]], [[Release Gates]]
- Estimated effort: 2 days
- Affected architecture: [[Version And Updates]], [[Production Readiness]]
- Success criteria: Old semantic versions and lower build numbers trigger required/optional update states correctly.
- Definition of done: Unit and widget tests cover old/current/newer, invalid manifest, unavailable Remote Config, and dismissed optional prompt.
- Progress 2026-06-03: Same-version minimum-build upgrades now become required updates; stale Remote Config policy is surfaced as `remotePolicyOutdated` instead of `current`; optional update prompts render from `RootScreen` before login/home and are dismissible through the existing per-build dismissal key.
- Progress 2026-06-04/06: The app and release manifests were first bumped to `1.0.7+8` after update warnings did not appear for `1.0.6+7`; `Build Rain Apps` run 26963049075 published `rain-test-109-1`. The 2026-06-06 follow-up found `rain-test-117-1` still used `1.0.7+8`, so `1.0.7+8` installs correctly reported `current`. The app and manifests are now bumped to `1.0.8+9`, regression coverage proves previous `1.0.6+7` and `1.0.7+8` Android/Windows stable/demo installs receive `updateRequired`, `Build Rain Apps` run 27062729519 published `rain-test-118-1`, and live Remote Config version 9 advertises `1.0.8+9`. Installed-app proof remains the operational follow-up.
- Subtasks:
  - [x] TASK-012.1 Add semantic/build comparison tests.
  - [x] TASK-012.2 Add required/optional prompt tests.
  - [x] TASK-012.3 Add settings "Check for updates" behavior test.

#### Feature PV-02: Adapter Contract Tests

##### TASK-018: Add API/signaling adapter contract tests

- Audit finding: 18. Appium/local smoke tests need stable locators and adapter contracts need stronger coverage.
- Priority: P1
- Dependencies: [[Emulator Coverage]], [[Test Strategy]], [[Release Gates]]
- Estimated effort: 5 days
- Affected architecture: [[Signaling Architecture]], [[Firebase Architecture]], [[Emulator Test Matrix]]
- Success criteria: Adapter tests cover success, permission denied, malformed data, cancellation, stale data, and cleanup behavior.
- Definition of done: Fake and emulator-backed tests run in the hard gate or a documented pre-release gate.
- Subtasks:
  - [ ] TASK-018.1 Define adapter contract matrix.
  - [ ] TASK-018.2 Add fake adapter parity tests.
  - [ ] TASK-018.3 Add emulator RTDB tests.
  - [ ] TASK-018.4 Add Appium locator smoke checklist.

#### Feature PV-03: Performance Tier Validation

##### TASK-021: Add ARMv7 and low-power performance budget

- Audit finding: 12. ARMv7 and low-power device paths need performance budgets.
- Priority: P1
- Dependencies: [[Coverage Dashboard]], [[Release Gates]], [[Frontend Architecture]]
- Estimated effort: 3 days
- Affected architecture: [[Frontend Architecture]], [[Release Gates]]
- Success criteria: Low-power tier disables expensive non-essential visuals and captures frame/performance summaries without causing lag.
- Definition of done: Tests verify low-power visual path and release gate documents ARMv7 expectations.
- Subtasks:
  - [ ] TASK-021.1 Define low-power performance budget.
  - [ ] TASK-021.2 Add low-power UI tests.
  - [ ] TASK-021.3 Add diagnostics summary validation.

#### Feature PV-04: Continuous Knowledge Maintenance

##### TASK-022: Maintain vault and memory as release artifacts

- Audit finding: 20. Project knowledge must be maintained continuously in [[Project Memory]].
- Priority: P2
- Dependencies: [[Project Memory]], [[AI Memory Index]], [[Documentation Workflow]]
- Estimated effort: 1 day setup, ongoing per change
- Affected architecture: [[Knowledge Graph Index]], [[Project Home]]
- Success criteria: Major changes update memory, architecture, risk/debt/blocker notes, and validation keeps links healthy.
- Definition of done: Vault validation remains in CI and future sessions can use [[Project Memory]] as primary context.
- Subtasks:
  - [ ] TASK-022.1 Keep vault checker required-list current.
  - [ ] TASK-022.2 Update memory after roadmap/release changes.
  - [ ] TASK-022.3 Record lessons after escaped regressions.

## Critical Path Summary

The release-critical chain is:

1. TASK-001: Split call runtime ownership.
2. TASK-002: Repair call leases safely.
3. TASK-003: Enforce explicit terminal call state.
4. TASK-013: Validate media capture ordering.
5. TASK-005: Prove Firebase rules with emulator coverage.
6. TASK-012: Fix update version prompts.
7. TASK-015: Enforce hard release gates.

Detailed view: [[Critical Path]].

## Parallel Work Streams

See [[Parallel Work Streams]].

The safe parallel streams are:

- Call reliability stream.
- Firebase/security stream.
- Update/release stream.
- Database/file scalability stream.
- UI/performance stream.
- Documentation/knowledge stream.

## Launch Blockers

See [[Launch Blockers]].

Public launch is blocked by:

- Unproven voice/video reliability.
- False busy/stale lock risk.
- Update prompt failures.
- Insufficient Firebase rules coverage.
- Weak release gate parity.
- Diagnostics privacy and root-cause classification gaps.

## Quick Wins

See [[Quick Wins]].

Near-term wins:

- Update version tests.
- Diagnostics sanitizer tests.
- Watch stream corruption tests.
- Release gate documentation.
- Firebase cost counter docs.
- Vault/memory validation.

## High-Risk Work

See [[High-Risk Work]].

Highest-risk items:

- `VoiceCallRuntime` split.
- Call lease repair.
- Explicit terminal state machine.
- Media capture ordering.
- Firebase rules expansion.
- Adapter/emulator contracts.
- Call surface unification.
