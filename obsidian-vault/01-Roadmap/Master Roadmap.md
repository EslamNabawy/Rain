# Master Roadmap

Last updated: 2026-06-03

## Purpose

This roadmap converts the authoritative findings in [[Original Audit]] into a dependency-driven execution program.

Do not treat this as a new audit. The source of truth is [[Original Audit]]. This note converts those findings into:

Epic -> Feature -> Task -> Subtask

Related: [[Project Home]], [[Current Architecture]], [[Audit Resolution Tracker]], [[Critical Path]], [[30 Day Plan]], [[60 Day Plan]], [[90 Day Plan]], [[Parallel Work Streams]], [[Launch Blockers]], [[Quick Wins]], [[High-Risk Work]].

## Roadmap Rules

- P0 blocks public release.
- P1 blocks production readiness but may not block internal test artifacts.
- P2 improves maintainability, scale, or operational confidence.
- Every task must have dependencies, estimated effort, success criteria, and definition of done.
- Every implementation task must update related notes, especially [[Project Memory]], [[Technical Debt Register]], [[Risk Register]], and [[Audit Resolution Tracker]].
- No roadmap item is complete until validation is recorded.

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
  - [ ] TASK-001.1 Define coordinator boundaries and method contracts.
  - [ ] TASK-001.2 Move diagnostics-only helpers into [[CallDiagnosticsRecorder]].
  - [ ] TASK-001.3 Move start eligibility into [[CallStartCoordinator]].
  - [ ] TASK-001.4 Move lease creation/repair into [[CallLeaseManager]].
  - [ ] TASK-001.5 Move media capture/session ownership into [[CallMediaCoordinator]].
  - [ ] TASK-001.6 Move terminal state cleanup into [[CallTerminalReconciler]].

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
- Subtasks:
  - [ ] TASK-006.1 Define freshness thresholds.
  - [ ] TASK-006.2 Validate session-owned heartbeat behavior.
  - [ ] TASK-006.3 Add runtime tests for app-close and stale-session cases.
  - [ ] TASK-006.4 Update [[Presence Management]].

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
- Subtasks:
  - [ ] TASK-008.1 Identify critical query paths.
  - [ ] TASK-008.2 Add index migration.
  - [ ] TASK-008.3 Add migration tests.
  - [ ] TASK-008.4 Update [[Index Strategy]].

#### Feature DB-02: Conversation Pagination

##### TASK-009: Implement conversation pagination

- Audit finding: 8. Local data must scale beyond small conversations.
- Priority: P1
- Dependencies: TASK-008, [[Pagination Strategy]]
- Estimated effort: 4 days
- Affected architecture: [[Database Architecture]], [[Peer Chat]], [[Frontend Architecture]]
- Success criteria: Initial conversation load is bounded and older messages load on demand.
- Definition of done: Widget/provider tests prove pagination and no full-list rebuild on append/page load.
- Subtasks:
  - [ ] TASK-009.1 Define page window and anchor behavior.
  - [ ] TASK-009.2 Add paginated store query.
  - [ ] TASK-009.3 Update chat provider.
  - [ ] TASK-009.4 Add pagination tests.

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
- Subtasks:
  - [ ] TASK-010.1 Define temp file lifecycle.
  - [ ] TASK-010.2 Stream chunks into persistent sink.
  - [ ] TASK-010.3 Add cleanup on cancel/failure.
  - [ ] TASK-010.4 Add large-transfer tests.

#### Feature FT-02: Data Channel Backpressure

##### TASK-011: Add data-channel send backpressure gate

- Audit finding: 7. File transfer needs stronger backpressure.
- Priority: P1
- Dependencies: TASK-010, [[Backpressure Strategy]], [[File Transfer]]
- Estimated effort: 3 days
- Affected architecture: [[Backpressure Strategy]], [[Streaming Architecture]]
- Success criteria: Sender pauses when buffered amount exceeds budget and resumes when safe.
- Definition of done: Slow-receiver tests prove bounded buffered amount and transfer recovery/termination behavior.
- Subtasks:
  - [ ] TASK-011.1 Define high/low water marks.
  - [ ] TASK-011.2 Wire send loop to backpressure.
  - [ ] TASK-011.3 Add slow receiver tests.
  - [ ] TASK-011.4 Update [[Backpressure Strategy]].

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
- Subtasks:
  - [ ] TASK-014.1 Define denylist.
  - [ ] TASK-014.2 Add recursive sanitizer tests.
  - [ ] TASK-014.3 Verify export summaries remain useful.

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
  - [ ] TASK-015.1 Define hard gate matrix.
  - [ ] TASK-015.2 Update workflow dependencies.
  - [ ] TASK-015.3 Add release gate documentation.

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
- Subtasks:
  - [ ] TASK-012.1 Add semantic/build comparison tests.
  - [ ] TASK-012.2 Add required/optional prompt tests.
  - [ ] TASK-012.3 Add settings "Check for updates" behavior test.

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
