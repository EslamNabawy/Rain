# Technical Debt Register

Last updated: 2026-08-29

## Purpose

This register converts [[Original Audit]], [[Current Architecture]], and [[Master Roadmap]] into a technical debt management system.

Debt is not a complaint list. Each item has a category, owner, cost, priority, affected files, related systems, and a resolution strategy tied to roadmap tasks.

Related: [[Debt Categories]], [[Debt Prioritization]], [[Architecture Debt]], [[Scalability Debt]], [[Security Debt]], [[Performance Debt]], [[Testing Debt]], [[DevOps Debt]], [[UX Debt]], [[Audit Resolution Tracker]], [[Critical Path]], [[2026-06-05 Senior Audit Remediation Plan]].

## Management Model

### Status Values

- Open: debt exists and has no implementation evidence yet.
- In Progress: active task is underway.
- Mitigated: risk reduced but not fully removed.
- Closed: validation evidence exists and related docs are updated.
- Accepted: owner explicitly accepts remaining risk in [[Launch Readiness]].

### Priority Values

- P0: Blocks public release.
- P1: Blocks production readiness but may allow internal test artifacts.
- P2: Improves maintainability, scale, or operational confidence.
- P3: Useful cleanup with no near-term launch impact.

### Cost Scale

- XS: less than 1 day.
- S: 1-2 days.
- M: 3-5 days.
- L: 6-10 days.
- XL: more than 10 days or multi-system coordination.

## Debt Statistics

| Metric | Value |
| --- | --- |
| Total debt items | 23 |
| P0 items | 10 |
| P1 items | 11 |
| P2 items | 2 |
| P3 items | 0 |
| Critical launch-path items | 7 |
| Current debt risk score | 72/100 |
| Target debt risk before public release | 30 or lower |

## Category Distribution

| Category | Count | Priority Weight | Related Note |
| --- | --- | --- | --- |
| Architecture | 6 | Highest | [[Architecture Debt]] |
| Scalability | 3 | High | [[Scalability Debt]] |
| Security | 4 | Highest | [[Security Debt]] |
| Performance | 2 | High | [[Performance Debt]] |
| Testing | 3 | High | [[Testing Debt]] |
| DevOps | 2 | High | [[DevOps Debt]] |
| UX | 3 | Medium | [[UX Debt]] |

## Prioritization Summary

### Must Fix First

1. TD-001 - Oversized voice/video call runtime.
2. TD-003 - Distributed call lease and terminal ownership.
3. TD-004 - Implicit async call state machine.
4. TD-016 - Media capture and ICE/TURN failures are not classified well enough.
5. TD-009 - Firebase rules coverage gaps.
6. TD-018 - Update validation failures.
7. TD-017 - Weak release gate parity.
8. TD-021 - Split authentication/session source of truth.
9. TD-022 - Move startup/splash/navigation to a global readiness gate.

### Safe Parallel Work

- TD-006 and TD-007 can proceed after database migration planning.
- TD-008 can proceed after file transfer characterization tests.
- TD-010 can proceed without changing signaling behavior.
- TD-015 can proceed as test harness work.
- TD-020 can proceed as documentation process work.

## 2026-06-05 Senior Audit Debt Overlay

Source: [[2026-06-05 Senior Audit Remediation Plan]]

| SAR ID | Debt Mapping | Owner | Priority | Dependency | Evidence Required | Release Impact |
| --- | --- | --- | --- | --- | --- | --- |
| SAR-001 | TD-001, TD-003, TD-004, TD-016 | Engineering | P0 | Phases 1-2 proof first | Characterization tests, extracted call coordinator tests, renderer failure tests, split-state projection tests, and Phase 10 device/media proof. | Public launch blocked while unproven. |
| SAR-002 | TD-002, TD-014, TD-020 | Engineering | P0 | Phase 0 | Phase 1 added authoritative runtime-backed peer snapshot freshness tests; Firebase emulator/device proof remains. | Unsafe action routing is locally mitigated; release confidence still needs Phase 2/10 proof. |
| SAR-003 | TD-014, TD-020 | Engineering/Product | P0 | SAR-002 | Phase 1 removed `friend.isOnline` from chat action truth and routes through `PeerConnectivitySnapshot.peerOnlineForAction`; 2026-06-06 added unified `ConnectionDiagnostics` projection for peer status display/action gates. | Unsafe connect/request/call UI is locally mitigated; device proof remains. |
| SAR-004 | TD-003, TD-009, TD-011 | Engineering/Security | P0 | Phase 0 | Emulator/rules stale/live/newer-lock matrix. | Call reliability and security blocked. |
| SAR-005 | TD-010 plus accepted local-data decision | Security/Product | P1 | Phase 0 | Option A accepted 2026-06-05 in [[ADR-010]]; privacy/security docs now state local Drift/SQLite content is plaintext. | Strong local privacy claims remain blocked unless future encryption work lands with migration proof. |
| SAR-006 | TD-006, TD-007 | Engineering | P1 | Phase 0 | Drift schema/index migration tests and store/provider pagination tests passed locally on 2026-06-05. | Local scale-readiness structure is mitigated; low-power/device frame-budget proof remains before release-scale closure. |
| SAR-007 | TD-008 | Engineering | P1 | Phase 0 | Phase 7 focused tests passed locally for large receive, scripted slow receiver/backpressure, cancel cleanup, hash mismatch cleanup, disk write failure, and temp cleanup. | Local large-file confidence is mitigated; device-scale real-network proof remains before release-scale closure. |
| SAR-008 | TD-010, TD-016 | Security/Engineering | P0/P1 | Phase 0 | Recursive sanitizer/export and taxonomy tests passed locally on 2026-06-05; new diagnostic fields require sanitizer regressions. | Covered diagnostic export safety is locally mitigated; deeper ICE route and media lifecycle taxonomy remains TD-016 work. |
| SAR-009 | TD-017, TD-018 | DevOps | P0/P1 | Phase 0 | Phase 8 local workflow contract proof requires validation gates, metadata, and production Remote Config evidence before publish. | Fresh cloud workflow proof remains required before promoting a specific artifact. |
| SAR-010 | TD-020 and engineering-system governance debt | DevOps/Engineering | P1 | Phase 0 | Phase 9 local semantic vault validation now enforces operational owner/priority/evidence/review fields, evidence ledger rows, closed-blocker proof, and P0/P1 next-action coverage. | Trustworthy status claims have a local validation gate; generated metric reconciliation remains future hardening. |
| SAR-011 | TD-017 | DevOps/Security | P2 | Phase 8 | `rain-test-*` releases are labeled test-only and metadata records artifact purpose/build profile. | Demo artifacts remain unsuitable for production-trust claims. |
| SAR-012 | TD-014 | Engineering/UI | P2 | Phase 1/6 | Chat panel selected-slice proof landed; rebuild isolation and low-power proof remain. | Broad rebuild debt is reduced, not closed. |

## Architecture Debt

### TD-001: Oversized VoiceCallRuntime

- Category: Architecture
- Status: Mitigating
- Priority: P0
- Owner: Engineering
- Title: Oversized voice/video call runtime.
- Description: `VoiceCallRuntime` mixes call start, presence checks, leases, media setup, terminal reconciliation, diagnostics, renderer handling, and UI-facing state mutation.
- Cause: Iterative feature additions landed in the existing runtime path instead of being split into coordinators.
- Risk: One fix can regress unrelated call phases, and tests cannot isolate lease, media, or terminal behavior.
- Cost to Fix: M, about 5 days.
- Cost to Ignore: Repeated PC-to-mobile and mobile-to-PC call regressions, false busy, stuck connecting, and hard-to-debug production failures.
- Files Affected: `apps/rain/lib/application/calls/*`, `apps/rain/lib/application/runtime/*`, `packages/protocol_brain/lib/*`, `packages/peer_core/lib/*`.
- Related Systems: [[VoiceCallRuntime Refactor]], [[CallStartCoordinator]], [[CallLeaseManager]], [[CallMediaCoordinator]], [[CallTerminalReconciler]], [[CallDiagnosticsRecorder]], [[Voice Calls]], [[Video Calls]].
- Roadmap Tasks: TASK-001.
- Resolution Strategy: Extract call start, lease, media, terminal, and diagnostics ownership behind coordinator contracts, then add characterization and regression tests.
- Progress Note 2026-06-05: First Phase 3 decomposition slice is complete. `CallErrorClassifier` now owns call failure reason/message/taxonomy/retry classification, and `call_media_session_coordinator.dart` owns app-side audio/video media adapters plus media diagnostics mapping. `VoiceCallRuntime` still owns command orchestration, room reconciliation, lock coordination, state mutation, and terminal cleanup, so TD-001 remains open until those seams are extracted and validated.
- Progress Note 2026-06-06: Combined Phase 3 slice reduced runtime/state ambiguity but does not close TD-001. Added `VoiceCallTerminalReconciler` for terminal-session-state policy, added renderer target classification in `call_media_session_coordinator.dart`, and moved peer UI truth into `ConnectionDiagnostics`/`peerConnectionDiagnosticsProvider`. Command orchestration, Firebase room reconciliation, lock/lease coordination, and most terminal cleanup remain in `VoiceCallRuntime`.
- Progress Note 2026-06-08: Phase 2a extracted `VoiceCallRoomCoordinator` (164 lines, 20 tests). Room status tracking, terminal room detail/reason resolution, reason code mapping, and terminal write error detection moved to coordinator. voice_call_runtime.dart reduced 4751ΓåÆ4689 lines.
- Progress Note 2026-06-08: Phase 3 added `voice_call_rtdb_rules_contract_test.dart` (37 tests) validating all voice call RTDB rules paths. TD-009 rule coverage gaps now have static test validation. TD-011 malformed write protection validated through existing emulator tests.
- Progress Note 2026-06-08: Phase 3a grouped `VoiceCallRoomCoordinator`, `VoiceCallErrorCoordinator`, `VoiceCallDiagnostics`, `VoiceCallTerminalReconciler`, and new `VoiceCallStateCoordinator` under `apps/rain/lib/application/runtime/voice_call/`. `VoiceCallStateCoordinator` owns pure call-state mapping/reset policy and focused coordinator tests plus full Melos analyze/test passed. `VoiceCallRuntime` is now 4,480 lines, but command orchestration, Firebase room reconciliation, lock coordination, media/session orchestration, and most cleanup remain.
- Progress Note 2026-06-08: Phase 3b extracted `VoiceCallPreflightCoordinator` and `VoiceCallReconnectCoordinator` under `apps/rain/lib/application/runtime/voice_call/`. Preflight now owns call-start availability/friend/presence guards and stale retry replacement; reconnect now owns peer failure/reconnecting state, session reconnect markers, and reconnect grace timers. `voice_call_runtime.dart` is now 4,189 lines, but command orchestration, Firebase room reconciliation, lock coordination, media/session orchestration, terminal cleanup, and full start conflict policy remain.
- Progress Note 2026-06-08: Phase 3c extracted `VoiceCallMediaCoordinator`, `VoiceCallSessionStateCoordinator`, and `VoiceCallSignalingCleanupCoordinator` under `apps/rain/lib/application/runtime/voice_call/`. Media connection creation, renderer/resource lifecycle, session-state projection, diagnostics recording, Firebase room watches, frame/ICE handling, terminal writes, stale cleanup, and bounded cleanup now delegate out of `VoiceCallRuntime`. `voice_call_runtime.dart` is now 2,917 lines. TD-001 remains open until command orchestration, call/file conflict policy, and lock/lease orchestration are split and device-direction proof passes.
- Progress Note 2026-06-09: Phase 4 converted `voice_call_runtime.dart`, `connection_request_runtime.dart`, `file_transfer_runtime.dart`, and `friend_runtime.dart` from shared `part of` files to imported/exported Dart extension libraries. `RainRuntimeController` now has explicit internal accessors/wrappers for those libraries while backing fields remain private. This reduces hidden library coupling but does not close TD-001 because command orchestration, call/file conflict policy, lock/lease ownership, and device-direction proof remain.

### TD-002: RainRuntimeController Domain Concentration

- Category: Architecture
- Status: Mitigated
- Priority: P1
- Owner: Engineering
- Title: Runtime controller owns too many domains.
- Description: `RainRuntimeController` coordinates presence, friends, sessions, messages, files, calls, lifecycle, connection requests, diagnostics, and shutdown.
- Cause: The runtime controller became the integration point for every feature.
- Risk: Hidden cross-feature coupling makes fixes brittle and can cause unrelated regressions in chat, files, calls, and presence.
- Cost to Fix: L, 6-10 days across phases.
- Cost to Ignore: New features will keep increasing coupling and make root-cause isolation slower.
- Files Affected: `apps/rain/lib/application/runtime/*`, `apps/rain/lib/application/state/*`.
- Related Systems: [[Current Architecture]], [[Target Architecture]], [[Refactoring Strategy]], [[Presence And Direct Connect]], [[File Transfer]], [[Voice Calls]], [[Connection Request Notifications]].
- Roadmap Tasks: TASK-001, TASK-020.
- Resolution Strategy: First split call runtime ownership, then progressively separate file, connection request, presence, and lifecycle adapters where tests prove stable seams.
- Progress Note 2026-06-03: Presence resolution is now centralized inside `RainRuntimeController` for local friend seeding, direct Connect, chat Connect routing, connection-request routing, call start, and network auto-recovery. Stale raw-online backend records and non-`online` presence states are treated as offline before runtime actions proceed. Phase 08 added protocol contract coverage for session-owned presence, `onDisconnect` offline writes, and state-aware presence reads. Remaining debt is broader runtime domain extraction and full app-close regression proof under a working Drift/sqlite test harness.

### TD-003: Distributed Call Lease And Terminal Ownership

- Category: Architecture
- Status: Mitigating
- Priority: P0
- Owner: Engineering
- Title: Call lease and terminal state are not owned by one component.
- Description: Active user locks, pair locks, room status, inboxes, local runtime state, and session frames can disagree.
- Cause: Firebase signaling, local runtime, and WebRTC session cleanup evolved as separate paths.
- Risk: False busy, stale locks, duplicate terminal cleanup, or deleting live locks.
- Cost to Fix: M, about 4 days.
- Cost to Ignore: Users can become unable to call until data is repaired, and stale locks can block valid peers.
- Files Affected: `packages/protocol_brain/lib/src/voice/*`, `apps/rain/lib/application/calls/*`, `backend/firebase/database.rules.json`.
- Related Systems: [[Lease Management]], [[CallLeaseManager]], [[CallTerminalReconciler]], [[Signaling Architecture]], [[Firebase Architecture]].
- Roadmap Tasks: TASK-002.
- Resolution Strategy: Make matching `callId` ownership the only cleanup authority, inspect referenced rooms before busy, and retry stale cleanup once.
- Progress Note 2026-06-03: One denied terminal cleanup path is mitigated. `FirebaseSignalingAdapter.endCall` now writes terminal `voiceCalls/{callId}` state before best-effort callee inbox mirror updates, and emulator coverage proves a missing `voiceCallInboxes/{callee}/{callId}` row no longer blocks terminal state or lock release. Remaining debt is full lease manager extraction and all terminal transition coverage.
- Progress Note 2026-06-04: The diagnostic-driven terminal `busy` case no longer leaves the local runtime in an active call phase while cleanup stalls. `VoiceCallRuntime` now publishes terminal state before session/media disposal and bounds cleanup, so false local call state should not block file transfer or later call actions. Remaining debt is still centralized lease ownership and emulator proof for stale/live/newer lock variants.
- Progress Note 2026-06-05: False-busy stale lock reclamation now has a shared `VoiceLockReclaimPolicy` used by Firebase and fake voice signaling. `createOutgoingCall` inspects existing pair/user locks, referenced rooms, participant match, terminal/expired/setup state, and uses compare-delete plus one retry before reporting busy. A local terminal echo race in `VoiceCallRuntime` was also fixed so local hangup still awaits session/media cleanup after its own terminal room write. Focused policy/signaling tests, workspace analyze, full Melos tests, and vault validation passed. Remaining debt is emulator/live Firebase proof and eventual extraction of a first-class lease manager.

### TD-004: Implicit Async Call State Machine

- Category: Architecture
- Status: Mitigating
- Priority: P0
- Owner: Engineering
- Title: Call phases and terminal transitions are not strict enough.
- Description: Incoming, outgoing, media connecting, active, reconnecting, ending, failed, and ended presentation states can be inferred from mixed sources.
- Cause: Runtime state, Firebase terminal status, late frames, and UI presentation were layered incrementally.
- Risk: Stuck connecting, late frame reversal, remote not hanging up, or UI still showing failed call surfaces.
- Cost to Fix: M, about 4 days.
- Cost to Ignore: Voice/video reliability remains unstable even if individual media bugs are fixed.
- Files Affected: `apps/rain/lib/application/calls/*`, `apps/rain/lib/presentation/calls/*`.
- Related Systems: [[Call State Machine]], [[CallTerminalReconciler]], [[Voice Calls]], [[Video Calls]].
- Roadmap Tasks: TASK-003, TASK-013.
- Resolution Strategy: Define explicit allowed transitions, timeouts, terminal reconciliation, and late-frame ignore behavior, then test voice and video paths.
- Progress Note 2026-06-03: Late voice signaling frames after terminal Firebase rooms now remain structured `late_frame_ignored` diagnostics and no longer replace the latest real crash/error in exports. 2026-06-04 mitigation: terminal-sensitive media signaling sends now preflight the Firebase room before `accept`, `offer`, `answer`, and `mute` writes; missing or terminal rooms are skipped and reconciled before `writeVoiceOffer`/`writeVoiceAnswer` can become debug-adapter crash records. Remaining debt is the full state-machine and terminal reconciliation split.
- Progress Note 2026-06-04: Terminal reconciliation now has state-before-cleanup ordering. `_settleVoiceCallAfterTerminalRace`, local hangup/fail paths, and cleanup helpers publish failed/idle state before bounded WebRTC/session cleanup, and tests lock that terminal calls do not keep file-transfer guards blocked. Remaining debt is extracting a strict call state machine instead of keeping transition ordering inside the large runtime.
- Progress Note 2026-06-06: Video renderer failure now follows the terminal state machine instead of remaining a warning-only media issue. Live local renderer failure fails call start with `videoRendererFailed`; live remote renderer attach failure writes terminal failed room state; failed terminal UI state cannot be overwritten by late session idle during cleanup. Remaining debt is full state-machine extraction and device-direction proof.
- Progress Note 2026-06-08: `VoiceCallStateCoordinator` now owns pure phase/detail/failure mapping from `VoiceCallSessionState` into `VoiceCallState` plus terminal write/local end reset policy. This reduces state-machine logic inside `VoiceCallRuntime`, but allowed transitions, timeout-to-terminal rules, and device-direction proof remain open.
- Progress Note 2026-06-08: `VoiceCallReconnectCoordinator` now owns reconnecting/failure grace state mutation and timer guards outside the runtime file. This reduces reconnect-state coupling inside `VoiceCallRuntime`, but the full explicit call state machine, timeout-to-terminal rules, Firebase terminal reconciliation, and device-direction proof remain open.
- Progress Note 2026-06-08: `VoiceCallSessionStateCoordinator` now owns the large protocol-session-to-runtime projection plus failed-session finalization and diagnostics recording, and `VoiceCallSignalingCleanupCoordinator` owns terminal room writes, status timelines, terminal-sensitive send preflight, and already-closed classification. This further reduces implicit state-machine coupling, but explicit allowed transitions, timeout-to-terminal rules, lease ownership, and cross-device direction proof remain open.

### TD-005: Fragmented Call Surface Model

- Category: Architecture
- Status: Mitigated
- Priority: P1
- Owner: Product/UI
- Title: Call UI has multiple historical surface implementations.
- Description: Fullscreen, minimized, popup, PiP, ended, failed, voice, and video surfaces have had inconsistent control ownership.
- Cause: UI iterations were added before one presentation contract was frozen.
- Risk: Duplicate bars, unsafe-area overlap, inconsistent icons, missing hangup/answer actions, and confusing failure states.
- Cost to Fix: M, about 4 days.
- Cost to Ignore: Users will perceive the app as unreliable even when signaling works.
- Files Affected: `apps/rain/lib/presentation/calls/*`, `apps/rain/lib/presentation/home/*`.
- Related Systems: [[Frontend Architecture]], [[Voice Calls]], [[Video Calls]], [[Call State Machine]].
- Roadmap Tasks: TASK-019.
- Resolution Strategy: Render only one call surface from one presentation model and remove or make unreachable legacy popup/duplicate paths.

### TD-021: Split Authentication And Session Source Of Truth

- Category: Architecture
- Status: Mitigated
- Priority: P0
- Owner: Engineering/Product
- Title: Authentication and session state have multiple truths.
- Description: Drift local identity, Firebase Auth current user, RTDB user profile, RTDB presence, runtime state, and router state can disagree.
- Cause: Local identity became the signed-in UI signal while backend validation happens later inside runtime startup.
- Risk: Logout/reset can appear broken, deleted backend account data can be recreated from local identity, and stale users can reach protected app surfaces.
- Cost to Fix: M, about 4 days.
- Cost to Ignore: Users cannot trust logout/account deletion, stale profile/friend state can survive, and backend permission failures continue to appear as app instability.
- Files Affected: `apps/rain/lib/application/state/identity_providers.dart`, `apps/rain/lib/application/state/runtime_providers.dart`, `apps/rain/lib/application/runtime/rain_runtime_controller.dart`, `packages/protocol_brain/lib/adapters/firebase_adapter.dart`, `packages/rain_core/lib/identity/identity.dart`.
- Related Systems: [[Authentication]], [AUTHENTICATION_AUDIT.md](../../AUTHENTICATION_AUDIT.md), [ACCOUNT_LIFECYCLE_ANALYSIS.md](../../ACCOUNT_LIFECYCLE_ANALYSIS.md), [STATE_MANAGEMENT_FAILURE_ANALYSIS.md](../../STATE_MANAGEMENT_FAILURE_ANALYSIS.md).
- Roadmap Tasks: [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md).
- Resolution Strategy: Add an `AuthSessionCoordinator`, treat local identity as a session candidate only, validate Firebase/backend identity before runtime start, and clear local session in a guaranteed path during logout/reset/delete.
- Progress Note 2026-06-03: Phase 1 reduced this debt by changing `IdentityController` to validate cached Drift identity against the backend user record and current auth uid before restoring signed-in state. Missing backend accounts, missing uid data, uid mismatch, and session-expired errors now clear local session data instead of publishing identity. Register/login now write backend profile and presence before saving local identity. Phase 2 made runtime logout deterministic by clearing local session before best-effort backend sign-out, covering failed sign-out and logout after a previous app-exit shutdown. Phase 6 added `AuthenticatedSession.sessionGeneration` as the account-scope boundary, keyed runtime reuse by username plus generation, and made account-owned providers reset from session generation instead of a broad manual invalidation list. 2026-06-04 mitigation: registration backend-write failures now sign out and keep Drift identity empty; RTDB permission-denied on username row creation is mapped to a friendly account conflict; rollback deletes the just-created Auth user only before the durable user row exists. 2026-06-04 account deletion mitigation: Settings now has a password-reauthenticated delete-account flow; adapter cleanup tombstones the backend user row, removes account-owned search/mirror data where authorized, deletes Firebase Auth last, filters tombstoned identity from restoration, preserves the current session on bad-password reauth, and prevents login/upsert/search writes from recreating a missing or tombstoned backend account after Auth succeeds. 2026-06-07 mitigation: required tombstone failure preserves the signed-in session/local identity and reports an error instead of acting like logout; optional RTDB cleanup now runs best-effort after tombstone so one denied mirror cannot make delete look like a no-op; delete preflight no longer publishes global runtime loading before wrong-password/pre-tombstone failures can render their modal feedback; verified destructive delete now enters a full-screen `deletingAccount` phase with navigation hidden; successful delete records a same-device deleted-username hint for clearer later login copy; the auth-deletion boundary now cancels account RTDB listeners and active protocol/data-room sessions before Firebase Auth is deleted; live RTDB rules now allow only email-bound current-auth users to tombstone legacy backend rows missing `uid`. Remaining debt: reported Android account retry proof, hard-release-gate integration when publishing, and a fuller `AuthSessionCoordinator` extraction if the current provider-based coordinator becomes insufficient.

## Scalability Debt

### TD-006: Missing Local Database Index Validation

- Category: Scalability
- Status: Open
- Priority: P1
- Owner: Engineering
- Title: Drift query paths need index validation.
- Description: Conversation, unread, transfer, friend, and queue queries need explicit index coverage before large accounts.
- Cause: Local database grew around feature needs without a documented query plan.
- Risk: Slow startup, slow chat open, and expensive table scans under real user histories.
- Cost to Fix: M, about 3 days.
- Cost to Ignore: Performance degrades as message and transfer records grow.
- Files Affected: `packages/rain_core/lib/src/storage/*`.
- Related Systems: [[Database Architecture]], [[Index Strategy]], [[Migration Plan]], [[Database Schema]].
- Roadmap Tasks: TASK-008.
- Resolution Strategy: Identify critical queries, add safe Drift migration indexes, and validate migration from current schema.
- Progress Note 2026-06-05: Drift schema v6 adds explicit indexes for conversation reads, queued-message drain/recovery, file-transfer peer/message/state lookup, and friend display ordering. `rain_database_test.dart` verifies new-schema index creation and v5-to-v6 index migration. Remaining work is device-scale performance evidence, not missing index structure.

### TD-007: Eager Conversation Loading

- Category: Scalability
- Status: Mitigating
- Priority: P1
- Owner: Engineering/UI
- Title: Conversation loading is not proven to be bounded.
- Description: Large conversations need paginated reads and stable UI anchors instead of full-list assumptions.
- Cause: Early chat flows optimized for small test conversations.
- Risk: Memory pressure, slow scroll, broad provider rebuilds, and ARMv7 lag.
- Cost to Fix: M, about 4 days.
- Cost to Ignore: Chat becomes unusable as real message histories grow.
- Files Affected: `apps/rain/lib/presentation/chat/*`, `packages/rain_core/lib/src/messages/*`, `packages/rain_core/lib/src/storage/*`.
- Related Systems: [[Pagination Strategy]], [[Peer Chat]], [[Frontend Architecture]], [[Database Architecture]].
- Roadmap Tasks: TASK-009, TASK-020.
- Resolution Strategy: Add page windows, anchor behavior, paginated store queries, and provider/widget tests.
- Progress Note 2026-06-05: `MessageStore.watchConversationTail` and `MessageStore.loadConversationPage` now provide a bounded live tail plus cursor-based older pages. `MessagesController` starts from the default 50-message tail and merges older local pages on demand. Store/provider tests cover ordering, older-page loading, and duplicate prevention. Remaining work is low-power/device frame-budget proof and any UX refinement for older-message loading.

### TD-008: File Transfer Streaming And Backpressure Proof

- Category: Scalability
- Status: Open
- Priority: P1
- Owner: Engineering
- Title: Large file transfer behavior is not sufficiently bounded.
- Description: Receive path and send path need hard proof around persistent streaming, temp cleanup, and RTCDataChannel buffered amount.
- Cause: File transfer feature exists, but large-file pressure and slow-receiver behavior need stronger validation.
- Risk: Memory spikes, channel crashes, failed transfers, and corrupted temp state.
- Cost to Fix: L, 7 days across receive and send work.
- Cost to Ignore: Large transfers can destabilize the app and degrade peer sessions.
- Files Affected: `apps/rain/lib/application/runtime/file_transfer_runtime.dart`, `apps/rain/lib/application/runtime/rain_runtime_controller.dart`, `packages/rain_core/lib/file_transfer/file_transfer_protocol.dart`, `apps/rain/test/friend_flow_test.dart`, `packages/rain_core/test/file_transfer_protocol_test.dart`.
- Related Systems: [[File Transfer]], [[Streaming Architecture]], [[Backpressure Strategy]].
- Roadmap Tasks: TASK-010, TASK-011.
- Resolution Strategy: Stream incoming chunks to temp files, add high/low water marks, pause/resume sends, and test slow receivers and cancellation.
- Progress Note 2026-06-05: Phase 7 local mitigation is implemented. Incoming chunks now use a persistent receive sink per active transfer and close it on complete, cancel, failure, network loss, and shutdown. Terminal cleanup deletes temp files for cancellation, hash mismatch, invalid chunks, and disk write failure. The outgoing send loop carries one partial chunk instead of growing/removing from a pending list. Backpressure constants for chunk size, high/low watermarks, poll interval, and timeout now live in the protocol contract, and the sender records privacy-safe wait/complete/timeout diagnostics. Focused large receive, cancel cleanup, hash mismatch cleanup, disk write failure, and scripted backpressure tests passed locally; real-network/device-scale proof remains follow-up evidence.
- Progress Note 2026-08-26: Cross-platform remediation slice A1+A2 (from [CROSS_PLATFORM_REMEDIATION_PLAN.md](../../CROSS_PLATFORM_REMEDIATION_PLAN.md)) removed two main-thread hot-loop costs. Receiver final SHA-256 now runs in `Isolate.run` with streamed reads instead of hashing on the UI isolate. Incoming transfer records hydrate into a runtime cache on first chunk and reuse it through completion; `clearTransferRuntimeState` is the single invalidation funnel (terminal frames, reject, cancel, markTransferFailed, network-loss cleanup). A loadById-count regression test proves the chunk hot path performs exactly one store read. Sender-side incremental hashing stays on the main isolate by accepted design: per-event digest cost is micro-scale and the send loop yields every chunk via awaited sends/backpressure, so no freeze spike exists; revisit only if profiling disagrees. Workspace analyze and full Melos tests passed; real-network/device-scale transfer proof remains open.
- Progress Note 2026-08-26b: Cross-platform slice A3+A4 removed the remaining transfer hot-loop costs. Binary-only data-channel frames no longer rebuild peer connectivity snapshots per 32 KiB chunk: `PeerConnectivityController` filters binary messages and the runtime's data-event notification uses a leading-edge 250 ms throttle with a trailing flush, so burst timestamps still reach the UI within one window. Receive sinks now flush via `FileTransferFlushPolicy` (rain_core): first write always flushes to fail fast on unwritable destinations, later writes batch per 512 KiB (`fileTransferFlushThresholdBytes`), terminal closes flush remainders. Regression coverage: loadById-count test, emission-count throttle test (`data_event_throttle_test.dart`), and policy unit tests. Workspace analyze plus full Melos tests passed; real-network/device-scale transfer proof remains open.

## Security Debt

### TD-009: Firebase Rule Coverage Gaps

- Category: Security
- Status: Open
- Priority: P0
- Owner: Security/Engineering
- Title: RTDB rules are too important to remain under-tested.
- Description: Presence, friendships, signaling rooms, voice calls, locks, inboxes, requests, and metadata need allow/deny emulator coverage.
- Cause: Rules evolved with multiple feature passes and free-tier constraints.
- Risk: Permission-denied regressions, unauthorized writes, malformed signaling state, or accidental lockouts of valid clients.
- Cost to Fix: M, about 4 days.
- Cost to Ignore: Production failures can only be found after shipping, and security assumptions remain unproven.
- Files Affected: `backend/firebase/database.rules.json`, `backend/firebase/test/*`, `packages/protocol_brain/test/*`.
- Related Systems: [[Rules Strategy]], [[Emulator Coverage]], [[Firebase Architecture]], [[Security Roadmap]].
- Roadmap Tasks: TASK-005.
- Resolution Strategy: Build a rules matrix for allowed and denied writes, run it locally or in CI, and document old-client compatibility assumptions.
- Progress Note 2026-06-03: Added Firebase emulator regression for `endCall` when the callee inbox row was already cleaned. The test failed with RTDB permission denied before the adapter fix and now passes without broadening RTDB rules.

### TD-010: Diagnostics Privacy Exposure

- Category: Security
- Status: Open
- Priority: P1
- Owner: Security/Engineering
- Title: Diagnostics must stay useful without private payloads.
- Description: Diagnostics should never export raw SDP, ICE candidate strings, tokens, passwords, ciphertext, message text, or file bytes.
- Cause: Debugging pressure can lead to verbose logs unless sanitization is enforced centrally.
- Risk: User-shared diagnostics could expose private data or sensitive signaling metadata.
- Cost to Fix: S, about 2 days.
- Cost to Ignore: Support logs become unsafe to request or inspect.
- Files Affected: `apps/rain/lib/application/diagnostics/*`, `apps/rain/lib/infrastructure/services/*`.
- Related Systems: [[Diagnostics And Logging]], [[Diagnostics Sanitization]], [[Privacy Review]], [[Security Roadmap]].
- Roadmap Tasks: TASK-014.
- Resolution Strategy: Add recursive denylist sanitization, string caps, export tests, and diagnostics-only summaries.
- Progress Note 2026-06-03: The Android diagnostics export path failure from the RCA is mitigated. `CrashDiagnosticsService` now treats SAF `/document/...` and `/tree/...` handles as platform-managed picker outputs and does not open them through `dart:io`. 2026-06-04 strengthening: when the picker returns a platform-managed handle, Rain writes and reports a real fallback JSON file under the diagnostics export folder; regression coverage locks both content URI and `/document/...` behavior.
- Progress Note 2026-06-06: Android picker handles with embedded leading newlines, such as `/\ndocument/11`, are now normalized before filesystem detection and route to the same fallback JSON export path instead of throwing `PathNotFoundException`.
- Progress Note 2026-06-07: `file_picker 12.0.0-beta.3` on Android can write nothing natively, return `/document/...`, then try to write bytes through `dart:io` and throw before Rain sees the picker result. `CrashDiagnosticsService` now bypasses that wrapper on Android by sending bytes on the plugin method channel, treats returned SAF handles as platform-managed documents, and still writes a fallback JSON export if a legacy wrapper failure surfaces as `FileSystemException('/document/12')`.
- Progress Note 2026-06-05: Senior audit Phase 4 added `DiagnosticsSanitizer` as the shared recursive sanitizer for crash diagnostics and debug logs. It pseudonymizes peer/call/room/user/pair/file/path/Firebase path values, redacts secrets, message-like payloads, SDP, ICE candidates, ciphertext, nonce/MAC, and file bytes, and re-sanitizes final export payloads before JSON encoding. Focused diagnostics export and sanitizer regression tests passed locally; future diagnostic fields that can carry private data still need focused redaction proof.
- Progress Note 2026-06-06: `CrashDiagnosticsRecord` now supports sanitized context metadata, and `RainDebugLogService` passes operation context into `recordErrorSync`. The debug signaling adapter includes ICE path templates for `writeICE` failures, so diagnostics can identify `rooms/{roomId}/callerICE/{candidateId}` or `rooms/{roomId}/calleeICE/{candidateId}` without exposing actual room ids or raw candidates. Focused debug-log and crash-diagnostics tests passed locally.

### TD-011: Malformed Signaling Write Protection

- Category: Security
- Status: Open
- Priority: P0
- Owner: Security/Engineering
- Title: Security rules must reject malformed or unauthorized signaling artifacts.
- Description: Signaling paths must reject wrong owners, invalid statuses, stale timestamps, oversized payloads, and unauthorized lock writes.
- Cause: Client-driven signaling has many paths and no Cloud Functions authority on Spark/free-tier mode.
- Risk: Bad or malicious clients can create corrupt rooms, stale busy locks, or unauthorized call/request records.
- Cost to Fix: M, folded into rules coverage.
- Cost to Ignore: Signaling state can be corrupted by old or modified clients.
- Files Affected: `backend/firebase/database.rules.json`, `backend/firebase/test/*`.
- Related Systems: [[Firebase Architecture]], [[Rules Strategy]], [[Signaling Architecture]], [[Lease Management]].
- Roadmap Tasks: TASK-005.
- Resolution Strategy: Encode shape, ownership, timestamp, and state-transition guards in RTDB rules and prove them with emulator tests.
- Progress Note 2026-06-06: Data-peer ICE rules remain intentionally role-owned. Existing rules-contract tests assert `callerICE` cannot be written by the canonical callee and `calleeICE` cannot be written by the canonical caller. The `signaling.writeICE` diagnostic was handled by preventing stale queued local ICE callbacks after disconnect/room deletion, not by loosening RTDB ownership.

### TD-012: Spark-Free-Tier Guardrails Are Not Fully Instrumented

- Category: Security
- Status: Open
- Priority: P1
- Owner: Engineering/Ops
- Title: Firebase operation budgets and offline request abuse controls need stronger tracking.
- Description: Presence, call signaling, ICE, connection requests, and update checks need counters and budget expectations because paid backend escalation is not allowed.
- Cause: Free-tier operation cost is a hard product constraint, but not all write-heavy flows have budget visibility.
- Risk: Excess reads/writes can hit Spark limits or create poor user experience without warning.
- Cost to Fix: S, about 2 days.
- Cost to Ignore: The app may become unreliable under normal testing or small growth due to quota pressure.
- Files Affected: `packages/protocol_brain/lib/src/firebase/*`, `apps/rain/lib/application/diagnostics/*`, `backend/firebase/database.rules.json`.
- Related Systems: [[Firebase Architecture]], [[Connection Request Notifications]], [[Diagnostics And Logging]], [[Release Gates]].
- Roadmap Tasks: TASK-017, TASK-023.
- Resolution Strategy: Add operation counters, define budgets, enforce offline-only request writes, and message every blocked action.

## Performance Debt

### TD-013: ARMv7 And Low-Power Budget Missing

- Category: Performance
- Status: Open
- Priority: P1
- Owner: Engineering/UI
- Title: Low-power devices need a defined performance tier.
- Description: ARMv7 and low-RAM devices should not run the same expensive visual/diagnostic paths as standard devices.
- Cause: Premium UI and diagnostics were added before a strict low-power budget was documented.
- Risk: Laggy scrolling, pull-refresh freezes, expensive effects, and poor tester confidence on low-end devices.
- Cost to Fix: M, about 3 days.
- Cost to Ignore: V7 builds remain visibly worse than ARM64 builds.
- Files Affected: `apps/rain/lib/presentation/*`, `apps/rain/lib/application/diagnostics/*`.
- Related Systems: [[Frontend Architecture]], [[Coverage Dashboard]], [[Release Gates]].
- Roadmap Tasks: TASK-021.
- Resolution Strategy: Define low-power visual policy, static effect fallbacks, frame summary diagnostics, and widget/performance tests.

### TD-014: Broad UI Rebuild Boundaries

- Category: Performance
- Status: Open
- Priority: P2
- Owner: Engineering/UI
- Title: Riverpod provider boundaries can trigger broad UI rebuilds.
- Description: Message, friend, connection, call, diagnostics, and media state updates need tighter selected watches and consumer islands.
- Cause: Large screens and runtime providers were composed quickly as feature count grew.
- Risk: Scroll lag, chat jank, and unstable pull-refresh on lower-performance devices.
- Cost to Fix: M, about 4 days.
- Cost to Ignore: UI remains fragile as features and data volume grow.
- Files Affected: `apps/rain/lib/presentation/home/*`, `apps/rain/lib/presentation/chat/*`, `apps/rain/lib/application/state/*`.
- Related Systems: [[Frontend Architecture]], [[Peer Chat]], [[Voice Calls]], [[Performance Debt]].
- Roadmap Tasks: TASK-020.
- Resolution Strategy: Replace broad watches with `select`ed slices, add rebuild isolation tests, and pair with pagination work.

## Testing Debt

### TD-015: Adapter Contract And Smoke Test Gaps

- Category: Testing
- Status: Open
- Priority: P1
- Owner: QA/DevOps
- Title: Adapter contracts and Appium smoke setup need repeatable coverage.
- Description: Fake and Firebase-backed adapters need parity tests for success, permission denied, malformed data, cancellation, stale records, and cleanup.
- Cause: UI/device testing has been added reactively after failures.
- Risk: Release builds can pass unit tests but fail on Firebase permissions, watcher data, or Android smoke startup.
- Cost to Fix: L, about 5 days.
- Cost to Ignore: Broken release artifacts reach testers and failures remain expensive to reproduce.
- Files Affected: `packages/protocol_brain/test/*`, `backend/firebase/test/*`, `apps/rain/integration_test/*`, `qa.appium.json`.
- Related Systems: [[Test Strategy]], [[Emulator Coverage]], [[Emulator Test Matrix]], [[Release Gates]].
- Roadmap Tasks: TASK-018.
- Resolution Strategy: Create adapter contract matrix, fake parity tests, emulator RTDB tests, and stable smoke locators.
- Progress Note 2026-06-03: Added `scripts/run_rain_app_test.ps1` so isolated Rain app tests run from `apps/rain` and resolve Drift/SQLite native assets on Windows. The targeted stale-presence friend-flow test passed through the wrapper, then full `friend_flow_test.dart` passed with 120 tests passing and 10 skipped legacy control-channel cases.
- Progress Note 2026-06-05: Phase 10 added `apps/rain/integration_test/device_media_reality_proof_test.dart` as an opt-in Flutter integration proof for real microphone/camera capture through `FlutterWebRTCBridge` and `DefaultCallMediaConnection`. The Android QA toolkit is installed and `QA_Medium_API_36_1` exists, but no Android device/emulator was attached in this session and saved Appium artifacts timed out in WebDriver. TD-015 remains open until the smoke path repeats with artifacts.

### TD-016: WebRTC Failure Classification Coverage

- Category: Testing
- Status: Open
- Priority: P1
- Owner: Engineering
- Title: ICE, TURN, and media failure diagnostics need testable taxonomy.
- Description: Call failures should identify permission, Firebase, ICE, TURN, media capture, first-frame, and terminal-state causes separately.
- Cause: WebRTC failures are currently difficult to infer from app-level messages alone.
- Risk: Debugging remains guesswork and fixes target symptoms instead of root causes.
- Cost to Fix: M, about 3 days.
- Cost to Ignore: PC-to-mobile and mobile-to-PC failures continue cycling through unproven fixes.
- Files Affected: `packages/peer_core/lib/*`, `apps/rain/lib/application/diagnostics/*`, `packages/protocol_brain/test/*`.
- Related Systems: [[CallDiagnosticsRecorder]], [[Signaling Architecture]], [[Voice Calls]], [[Video Calls]].
- Roadmap Tasks: TASK-004.
- Resolution Strategy: Add sanitized call setup timeline, candidate counts, selected route metadata, first-track/frame events, and taxonomy tests.
- Progress Note 2026-06-03: Call setup diagnostics now retain Firebase room status transitions in the runtime and include them in `VoiceCallDiagnostics`. Remote terminal-room failure reconciliation also records diagnostics, so failed setup reports can show `ringing -> accepted -> failed` instead of an empty room timeline. Phase 08 added regressions for WebRTC transceiver/SDP native error sanitization, Firebase permission-denied setup messages, network-loss terminal messages, failed call suite state, terminal-room-before-session-hangup ordering, failed-media terminal writes, and already-terminal cleanup classification. Full ICE/TURN route and candidate classification remains open.
- Progress Note 2026-06-05: `CallErrorClassifier` now centralizes call failure reason/message/taxonomy/retry classification and focused tests cover native media errors, TURN failures, local camera/microphone permission, stale lock repair, Firebase permission denied, terminal rooms, and malformed remote signaling data. Full selected-route, candidate, first-track, and first-frame diagnostics remain open.
- Progress Note 2026-06-06: Renderer diagnostics now distinguish `video_renderer_failed`, `stale_renderer_callback_ignored`, and `peer_ui_state_split_detected`; focused renderer regression tests prove live local/remote renderer failures become `videoRendererFailed`. Full ICE/TURN route and real device media proof remain open.
- Progress Note 2026-06-06: Direct data-peer ICE lifecycle diagnostics now have one deterministic local regression: queued local ICE after disconnect does not write the stale Firebase room, while active current-session ICE write failure still fails the session. This reduces false Firebase-permission root-cause ambiguity but does not replace selected-route/candidate-pair/first-frame diagnostics.
- Progress Note 2026-06-06: `rain-diagnostics-2026-06-06T170224-576454Z.json` exposed a second data-peer ICE lifecycle gap: deleting the signaling room at connected can make valid late local trickle ICE fail RTDB room-existence rules. `ProtocolBrainImpl` now keeps the active room alive until session cleanup, and `protocol_brain_test.dart` covers late connected-session ICE writing the canonical bucket without failing the session.

## DevOps Debt

### TD-017: Weak Release Gate Parity

- Category: DevOps
- Status: Mitigated
- Priority: P0
- Owner: DevOps
- Title: Release artifacts can be built without enough proof.
- Description: Workflows need a hard gate that blocks publish when analyze, tests, rules, vault validation, or artifact metadata fail.
- Cause: Fast test builds and release builds were added for speed, then gate strictness became inconsistent.
- Risk: Broken APKs/Windows artifacts reach testers, wasting install cycles and masking real regressions.
- Cost to Fix: S, about 2 days.
- Cost to Ignore: Release confidence remains low and every build becomes a manual gamble.
- Files Affected: `.github/workflows/*`, `scripts/*`, `melos.yaml`.
- Related Systems: [[CI-CD Roadmap]], [[Release Gates]], [[Coverage Dashboard]].
- Roadmap Tasks: TASK-015.
- Resolution Strategy: Define hard gate matrix, enforce workflow dependencies, and include commit/version/channel evidence in artifacts.
- Progress Note 2026-06-05: Phase 8 local mitigation is implemented. `release.yml` is manual-only, validates before build/publish, requires Remote Config deploy/readback evidence, and publishes `rain-release-metadata.json`; `build-artifacts.yml`, `fast-release.yml`, and `validated-release.yml` also attach metadata; production fast/validated releases require Remote Config evidence; test-download releases are labeled `TEST ARTIFACT ONLY`. Remaining debt is fresh GitHub Actions proof for the changed workflows before artifact promotion.

### TD-018: Update Version Validation Failures

- Category: DevOps
- Status: Open
- Priority: P0
- Owner: Product/DevOps
- Title: App update policy has reported wrong old-version behavior.
- Description: Old versions have not reliably shown update prompts, and manual check behavior has been reported misleading.
- Cause: Version/build comparison and Remote Config manifest behavior need stricter tests.
- Risk: Old clients can continue running against incompatible backend rules or show "up to date" incorrectly.
- Cost to Fix: S, about 2 days.
- Cost to Ignore: Backend changes can break old apps without warning or safe upgrade path.
- Files Affected: `apps/rain/lib/application/update/*`, `apps/rain/lib/infrastructure/services/force_update*`, `apps/rain/test/*`.
- Related Systems: [[Version And Updates]], [[Release Gates]], [[Production Readiness]].
- Roadmap Tasks: TASK-012.
- Resolution Strategy: Add semantic/build comparison tests, manifest parser tests, required/optional prompt widget tests, and settings check behavior tests.
- Progress Note 2026-06-03: Update service now has explicit `remotePolicyOutdated` status for stale release manifests, same-version minimum-build upgrades are required updates, optional update prompts render from the root app surface before login/home, and settings manual checks report stale policy instead of "up to date."
- Progress Note 2026-06-04: Release metadata drift for the current test build is mitigated. The app is bumped to `1.0.7+8`, both release manifests advertise `1.0.7+8`, and `version_metadata_test.dart` proves previous `1.0.6+7` installs now receive `updateRequired` from the checked-in Remote Config template. `Build Rain Apps` run 26963049075 published `rain-test-109-1` Android/Windows artifacts for SHA `f1904e7`. Remaining debt is deploy evidence that production Remote Config was actually updated for the published artifacts.
- Progress Note 2026-06-06: Repeated update-warning miss was caused by same-version test artifacts (`1.0.7+8` published again as `rain-test-117-1`). The app and manifests are bumped to `1.0.8+9`, regression coverage proves previous `1.0.7+8` installs receive `updateRequired`, `Build Rain Apps` run 27062729519 published `rain-test-118-1`, and live Remote Config version 9 was deployed/read back advertising `1.0.8+9`. Remaining debt is installed old/current app proof against the live policy.

### TD-023: Plugin-Owned Kotlin Gradle Plugin Warnings

- Category: Operational
- Status: Open
- Priority: P2
- Owner: DevOps/Engineering
- Title: Flutter plugin Android modules still apply the legacy Kotlin Gradle Plugin.
- Description: Android debug logs can warn that several third-party Flutter plugins apply the Kotlin Gradle Plugin and may fail in future Flutter/AGP versions.
- Cause: Plugin Android modules must migrate to AGP built-in Kotlin or publish compatible versions; Rain only controls its own app module.
- Risk: Future Flutter upgrades can fail Android builds even when Rain's app module no longer applies `kotlin-android`.
- Cost to Fix: M, about 1-2 days after compatible plugin versions exist.
- Cost to Ignore: Android release gates can start failing after Flutter/AGP upgrades.
- Files Affected: `apps/rain/pubspec.yaml`, `apps/rain/android/settings.gradle.kts`, `apps/rain/android/app/build.gradle.kts`.
- Related Systems: [[Build Process]], [[Release Gates]].
- Roadmap Tasks: TASK-015, TASK-021.
- Resolution Strategy: Keep Rain's app module Java/no-KGP, keep the Kotlin plugin version declared in `settings.gradle.kts` with `apply false` for dependency modules, monitor plugin changelogs, and upgrade plugins when built-in Kotlin-compatible versions are available. Do not re-add app-level `kotlin-android` to silence plugin-owned warnings.
- Progress Note 2026-06-06: Rain's `MainActivity` shim was moved from Kotlin to Java and the app module no longer applies the Kotlin Gradle Plugin. `settings.gradle.kts` still pins Kotlin `2.2.20` for third-party plugin compilation. Remaining KGP warnings are owned by third-party plugin Android modules.

## UX Debt

### TD-019: Call UI Surface Instability

- Category: UX
- Status: Open
- Priority: P1
- Owner: Product/UI
- Title: Voice/video call presentation has not stabilized into a mature call suite.
- Description: Users have reported bad control layout, overlap, stuck failure screens, duplicate management surfaces, and confusing minimized behavior.
- Cause: Runtime reliability and UI surface redesign progressed in overlapping iterations.
- Risk: Even working calls can feel broken or unsafe to use.
- Cost to Fix: M, about 4 days.
- Cost to Ignore: Users lose trust in calls and confuse UI bugs with media failures.
- Files Affected: `apps/rain/lib/presentation/calls/*`, `apps/rain/lib/presentation/home/*`.
- Related Systems: [[Voice Calls]], [[Video Calls]], [[Frontend Architecture]], [[Call State Machine]].
- Roadmap Tasks: TASK-019.
- Resolution Strategy: Unify fullscreen, minimized bar, video PiP, ended, and failed surfaces under one control model and safe-area contract.

### TD-020: Blocked Action Messaging And Offline Request UX

- Category: UX
- Status: Open
- Priority: P0
- Owner: Product/Security
- Title: Connection request guardrails must explain every blocked action.
- Description: Offline notification requests must require confirmation, should not count online direct connect attempts, and must message every denied rule.
- Cause: Connection request behavior changed from direct connect fallback to quota-governed offline notifications.
- Risk: Users burn quota unintentionally or see silent failures when Firebase rules deny writes.
- Cost to Fix: M, about 3 days.
- Cost to Ignore: Users cannot understand connect/request behavior and support load increases.
- Files Affected: `apps/rain/lib/application/connection_requests/*`, `apps/rain/lib/presentation/*`, `packages/protocol_brain/lib/src/connection_requests/*`, `backend/firebase/database.rules.json`.
- Related Systems: [[Connection Request Notifications]], [[Presence Management]], [[Rules Strategy]], [[Firebase Architecture]].
- Roadmap Tasks: TASK-023.
- Resolution Strategy: Resolve online/offline/unknown presence before action, ask explicit confirmation for offline notification, and show fixed messages for every denial.
- Progress Note 2026-06-06: Chat/link status now consumes `ConnectionDiagnostics` from `peerConnectionDiagnosticsProvider`. `Data lane only` can keep message/file gates aligned through `canSendData` without visually showing `Connected`; manual disconnect, recovering, failed, out-of-sync, connected, stale, ready, and offline states have explicit projection precedence.

### TD-022: Route-Local Splash And Protected Navigation Gate

- Category: UX
- Status: Mitigated
- Priority: P0
- Owner: Engineering/Product
- Title: Startup splash and navigation readiness are route-local instead of app-global.
- Description: `RootScreen` owns loading/update/runtime gates only for `/`, while `ShellRoute` and protected sibling routes can exist before full app readiness.
- Cause: The routed app shell is created immediately after infrastructure bootstrap; auth/session/runtime readiness is resolved inside providers and route children.
- Risk: Navigation/app shell or protected route UI can render before authentication validation and runtime initialization finish.
- Cost to Fix: M, about 3 days.
- Cost to Ignore: Startup looks broken, protected screens can show `Unknown` identity, and loading/error states leak into normal app UI.
- Files Affected: `apps/rain/lib/main.dart`, `apps/rain/lib/presentation/screens/rain_app.dart`, `apps/rain/lib/presentation/navigation/app_routes.dart`, `apps/rain/lib/presentation/navigation/rain_navigation_shell.dart`, `apps/rain/lib/presentation/screens/root_screen.dart`, `apps/rain/lib/presentation/screens/settings_screen.dart`, `apps/rain/lib/presentation/screens/search_screen.dart`.
- Related Systems: [[Authentication]], [[Frontend Architecture]], [STARTUP_SEQUENCE_ANALYSIS.md](../../STARTUP_SEQUENCE_ANALYSIS.md), [SPLASH_SCREEN_INVESTIGATION.md](../../SPLASH_SCREEN_INVESTIGATION.md), [NAVIGATION_INITIALIZATION_AUDIT.md](../../NAVIGATION_INITIALIZATION_AUDIT.md).
- Roadmap Tasks: [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md).
- Resolution Strategy: Add a global startup gate and split route trees so protected app shell renders only after session validation and runtime readiness.
- Progress Note 2026-06-03: Phase 3 reduced this debt by introducing `AppStartupState` and `AppStartupPhase` as the single readiness model for update checks, identity validation, signed-out state, runtime startup, session-expired reset, failures, and ready state. `RootScreen`, shell navigation visibility, router refresh, and protected-route redirects now consume this model. Phase 4 moved loading, required-update, failed, and session-expired visual ownership to a global `RainStartupSurface` in `RainApp`, preventing `RainNavigationShell` from being inserted while startup is blocked. Phase 5 completed protected navigation readiness: `canRenderProtectedRoutes` gates settings/search/friend pages, route-local `_ProtectedRouteGate` blocks stale route content, unresolved protected paths redirect to `/`, and signed-out auth renders outside the shell with a standalone Navigator/Overlay. Phase 6 completed session-scoped provider lifecycle hardening by keying account-owned providers and runtime reuse to `AuthenticatedSession.sessionGeneration`. 2026-06-04 account deletion now uses that session boundary to preserve the session on failed reauth and clear it after destructive deletion starts. 2026-06-04 Phase E also aligned Android `NormalTheme` with `LaunchTheme` by using the dark `@drawable/launch_background` in light and night resources, with a platform resource contract test. Remaining debt is hard-release-gate integration and broader startup/device proof.
- Progress Note 2026-06-06: Pending logout now clears local session data before waiting on async cleanup, detaches the active runtime from provider readiness, and renders signed-out while cleanup continues best-effort. Destructive account deletion now reauthenticates, invokes backend/Auth delete while runtime cleanup is best-effort, then clears local session so it cannot degrade into plain logout. `AppStartupState` no longer treats runtime loading with a previous value or null runtime data as ready. Regression tests prove cleanup-blocked logout/delete do not leave protected shell visible and do not stick on startup loading; non-destructive bad-password deletion still restores the session.
- Progress Note 2026-06-07: Account deletion now has an explicit `deletingAccount` startup phase after password verification. The app shows a full-screen blocking deletion overlay, hides navigation, and keeps the current protected route mounted so recoverable backend failures can restore Settings and show the modal. Route/provider tests lock this behavior.
- Progress Note 2026-06-07: Account deletion no longer invokes runtime shutdown before backend/Auth deletion. Required tombstone failure now restores the existing runtime/session and keeps local identity, preventing failed delete from presenting as logout. Optional account cleanup is decoupled from the required tombstone write and retried path-by-path best-effort after multi-location cleanup failure. Runtime provider delete preflight now keeps startup ready while password verification is pending, preventing wrong-password failures from briefly replacing Settings with Splash and losing the error dialog.
- Progress Note 2026-06-07 live rules follow-up: the deployed `users/{username}` rule was updated and read back from `rain-8fb4b-default-rtdb` so legacy rows missing `uid` can be tombstoned only by the matching Firebase Auth email/current uid. This reduces the remaining startup/delete UX debt from a known backend rules denial to a user Android retry/device evidence item.
- Progress Note 2026-08-29: Added `registration conflict on existing username rethrows without cache, search, or sign-out` to `apps/rain/test/auth_identity_source_of_truth_test.dart`. The contract is now locked locally: when `adapter.register` throws `already taken`, the runtime must not call `addToUserSearch`, `upsertIdentity`, `setPresence`, or `signOut`, and Drift identity must stay empty. Combined with the existing post-user-row secondary-failure test, all three registration conflict cases listed in [[Recommended Next Actions]] #6 are now covered without live Firebase probes.

### TD-024: TraceId Coverage Gaps And Throttle Hash-Collision Risk

- Category: Testing
- Status: Open
- Priority: P2
- Owner: Engineering
- Title: Tracing system covers only register and call-start flows; provider throttling uses non-structural hashing.
- Description: The 2026-08-29 trace-context wiring ([[ADR-011]]) adds `traceId` only to `IdentityController.register` and `RainRuntimeController._startCall`. Heartbeat, `createOutgoingCall`, `writeICE`, `writeVoiceOffer`, `writeVoiceAnswer`, presence watches, and the rest of the runtime are not wrapped. `ThrottledProviderObserver` deduplicates using `Object.hashCode` and a hardcoded `_noisyProviders` set keyed on `ProviderObserver.provider.runtimeType.toString()`; `PeerConnectivitySnapshot` and `ConnectionDiagnostics` do not override `==`/`hashCode`, so identity-equal updates still emit and `hashCode` collisions across distinct values would silently drop legitimate updates.
- Cause: 2026-08-29 slice was scoped to PR1+PR3 of the 2026-08-27 design without Drift persistence, debug overlay, or full Track B wiring.
- Risk: Heartbeat, presence, and WebRTC flows remain uncorrelated in exports. Hash collisions in the throttling observer can hide legitimate provider state changes. The runtimeType key in `_noisyProviders` is brittle against Riverpod internals.
- Cost to Fix: M, about 3-5 days for traceId coverage plus structural equality.
- Cost to Ignore: Cross-flow queries by `traceId` only span register and call-start. The throttling observer may silently drop or double-emit updates.
- Files Affected: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`, `apps/rain/lib/application/runtime/voice_call_runtime.dart`, `apps/rain/lib/infrastructure/services/rain_debug_log_service.dart`, `apps/rain/lib/infrastructure/diagnostics/tracing/throttled_provider_observer.dart`, `apps/rain/lib/application/state/connection_diagnostics.dart`, `apps/rain/lib/application/state/peer_connectivity_snapshot.dart`.
- Related Systems: [[Diagnostics And Logging]], [[Presence And Direct Connect]], [[Call State Machine]], [[Peer Chat]], [[File Transfer]].
- Resolution Strategy: Wrap `_sendHeartbeatSafely`, `_fetchPeerPresenceSnapshot`, the call signaling writes, and the file transfer chunk pipeline in `TraceContext.runAsync`. Add structural `==` and `hashCode` to `PeerConnectivitySnapshot` and `ConnectionDiagnostics`. Replace the hardcoded noisy-provider set with a configurable per-provider policy.
- Roadmap Tasks: Phase 12, Phase 13 of [[Master Roadmap]] tracing overlay.

## Debt Burn-Down Plan

| Window | Close First | Expected Debt Score Impact |
| --- | --- | --- |
| 30 days | TD-001, TD-003, TD-004, TD-009, TD-010, TD-017, TD-018 | Reduce from 72 to about 50 if validated. |
| 60 days | TD-006, TD-007, TD-008, TD-015, TD-019 | Reduce from about 50 to about 38 if validated. |
| 90 days | TD-012, TD-013, TD-014, TD-016, TD-020, TD-002 | Reduce to target 30 or lower if residual risks are accepted. |

## Register Definition Of Done

- Every open debt item has an owner and links to roadmap tasks and architecture notes.
- Closed debt items include validation evidence in [[Audit Resolution Tracker]] or [[Coverage Dashboard]].
- Accepted debt items have explicit owner acceptance in [[Launch Readiness]].
- [[Project Memory]] is updated when a debt item changes durable project facts.
