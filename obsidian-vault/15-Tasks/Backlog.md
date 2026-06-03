# Backlog

Last updated: 2026-06-03

## Purpose

This backlog converts the audit in [[Original Audit]] into executable work. Each item links to [[Epic Index]], [[Master Roadmap]], [[Technical Debt Register]], and [[Audit Resolution Tracker]].

## Critical Backlog

### TASK-001: Extract VoiceCallRuntime into coordinators

- Status: [ ] Not Started
- Epic: [[Architecture Stabilization Epic]]
- Feature: [[VoiceCallRuntime Refactor]]
- Description: Split the runtime into [[CallStartCoordinator]], [[CallLeaseManager]], [[CallMediaCoordinator]], [[CallTerminalReconciler]], and [[CallDiagnosticsRecorder]].
- Business value: Users get reliable calls instead of random failed, busy, or stuck states.
- Technical value: Removes mixed responsibilities and makes call start/end testable.
- Risk level: Critical
- Dependencies: [[Current Architecture]], [[Target Architecture]], [[Call State Machine]]
- Files affected: `apps/rain/lib/application/calls/*`, `packages/protocol_brain/lib/*`, `packages/peer_core/lib/*`
- Acceptance criteria: Runtime behavior is unchanged externally; every coordinator has targeted unit tests; no duplicate call terminal paths remain.
- Definition of done: Tests pass, old runtime helpers are removed or delegated, diagnostics classify each coordinator phase.
- Estimated effort: 5 days

### TASK-002: Implement atomic call lease repair

- Status: [ ] Not Started
- Epic: [[Signaling Reliability Epic]]
- Feature: [[CallLeaseManager]]
- Description: Make user locks, pair locks, rooms, and inbox entries repairable only when the matching `callId` still owns them.
- Business value: Removes false `busy` after failed calls.
- Technical value: Creates a deterministic lease lifecycle.
- Risk level: Critical
- Dependencies: TASK-001, [[Lease Management]], [[Rules Strategy]]
- Files affected: `packages/protocol_brain/lib/src/voice/*`, `backend/firebase/database.rules.json`
- Acceptance criteria: Missing, expired, terminal, and corrupt rooms repair once; live rooms return real busy; stale cleanup never deletes newer locks.
- Definition of done: Emulator tests cover stale and live locks; diagnostics include lock path and cleanup result.
- Estimated effort: 4 days

### TASK-003: Enforce explicit call phase state machine

- Status: [ ] Not Started
- Epic: [[Signaling Reliability Epic]]
- Feature: [[Call State Machine]]
- Description: Replace implicit call UI/runtime phase assumptions with a typed state machine for incoming, outgoing, connecting media, active, terminal, failed, and ended presentation states.
- Business value: Users stop seeing stuck connecting or misleading dismiss-only failures.
- Technical value: Eliminates impossible states and late-frame confusion.
- Risk level: Critical
- Dependencies: TASK-001, TASK-002
- Files affected: `apps/rain/lib/application/calls/*`, `apps/rain/lib/presentation/calls/*`
- Acceptance criteria: No call can remain connecting past timeout; terminal Firebase room always reconciles both peers; late frames become diagnostics only.
- Definition of done: Runtime tests prove terminal room beats missing or late hangup frames.
- Estimated effort: 4 days

### TASK-004: Add ICE and TURN health classification

- Status: [ ] Not Started
- Epic: [[Signaling Reliability Epic]]
- Feature: [[CallDiagnosticsRecorder]]
- Description: Track ICE gathering, remote candidate count, selected candidate pair type, TURN relay use, first media frame, and failure reason.
- Business value: User reports become actionable instead of generic.
- Technical value: Distinguishes Firebase, permission, media, and NAT traversal failures.
- Risk level: High
- Dependencies: TASK-001, [[Signaling Architecture]]
- Files affected: `packages/peer_core/lib/*`, `apps/rain/lib/application/diagnostics/*`
- Acceptance criteria: Diagnostics export contains call setup timeline without raw SDP or ICE strings.
- Definition of done: Sanitization tests pass and export includes summary categories.
- Estimated effort: 3 days

### TASK-005: Expand Firebase rule coverage

- Status: [ ] Not Started
- Epic: [[Security Hardening Epic]]
- Feature: [[Rules Strategy]]
- Description: Add emulator coverage for presence, call rooms, call locks, inboxes, connection requests, messages, and file metadata.
- Business value: Prevents permission denied regressions and unsafe writes.
- Technical value: Rules become testable, not guessed.
- Risk level: Critical
- Dependencies: [[Firebase Architecture]], [[Emulator Coverage]]
- Files affected: `backend/firebase/database.rules.json`, `backend/firebase/test/*`
- Acceptance criteria: Rules reject unauthorized or malformed writes and allow valid user-owned flows.
- Definition of done: CI can run rules tests or a documented local equivalent.
- Estimated effort: 4 days

### TASK-006: Harden presence and app-close detection

- Status: [ ] Not Started
- Epic: [[Signaling Reliability Epic]]
- Feature: [[Presence Management]]
- Description: Make presence session-owned, fast enough for UX, and safe when old sessions write late.
- Business value: Offline peers are not shown as callable or directly connectable.
- Technical value: Reduces stale recovery loops and false online states.
- Risk level: High
- Dependencies: [[Rules Strategy]], [[VoiceCallRuntime Refactor]]
- Files affected: `packages/protocol_brain/lib/src/firebase/*`, `apps/rain/lib/application/runtime/*`
- Acceptance criteria: Closed app becomes offline within freshness window; old session cannot keep peer online.
- Definition of done: Unit tests simulate app close, old session heartbeat, and network loss.
- Estimated effort: 3 days

### TASK-007: Make Firebase watch streams non-poisoning

- Status: [ ] Not Started
- Epic: [[Signaling Reliability Epic]]
- Feature: [[Firebase Architecture]]
- Description: Corrupt entries should be removed or ignored without killing the app stream.
- Business value: One bad record does not crash Windows or block calls.
- Technical value: Watch handling is resilient to old app data and malformed records.
- Risk level: High
- Dependencies: [[Diagnostics Sanitization]], [[Rules Strategy]]
- Files affected: `packages/protocol_brain/lib/src/firebase/*`
- Acceptance criteria: Corrupt inbox or room logs cleanup and watcher continues.
- Definition of done: Tests inject malformed timestamps and unknown rooms.
- Estimated effort: 2 days

### TASK-008: Add Drift index migration

- Status: [ ] Not Started
- Epic: [[Database Scalability Epic]]
- Feature: [[Index Strategy]]
- Description: Add indexes for conversation message reads, unread counters, transfer records, and friend lookups.
- Business value: App stays responsive with large histories.
- Technical value: Prevents full scans and slow startup.
- Risk level: High
- Dependencies: [[Database Architecture]], [[Migration Plan]]
- Files affected: `packages/rain_core/lib/src/storage/*`
- Acceptance criteria: Migration is safe from existing schema; query plans are documented.
- Definition of done: Database tests pass and [[Database Architecture]] is updated.
- Estimated effort: 3 days

### TASK-009: Implement conversation pagination

- Status: [ ] Not Started
- Epic: [[Database Scalability Epic]]
- Feature: [[Pagination Strategy]]
- Description: Replace eager conversation loading with stable page windows and unread-aware anchors.
- Business value: Scrolling stays smooth on large chats and ARMv7.
- Technical value: Reduces allocations and Riverpod rebuild pressure.
- Risk level: High
- Dependencies: TASK-008
- Files affected: `apps/rain/lib/presentation/chat/*`, `packages/rain_core/lib/src/messages/*`
- Acceptance criteria: Initial chat load is bounded and older messages load on demand.
- Definition of done: Widget/provider tests verify no full-list rebuild for new pages.
- Estimated effort: 4 days

### TASK-010: Use persistent file receive sink

- Status: [ ] Not Started
- Epic: [[File Transfer Optimization Epic]]
- Feature: [[Streaming Architecture]]
- Description: Stream incoming file chunks directly to a temporary file instead of holding large payloads in memory.
- Business value: Large transfers stop crashing low-memory devices.
- Technical value: Makes receive path scalable.
- Risk level: High
- Dependencies: [[Backpressure Strategy]]
- Files affected: `packages/peer_core/lib/src/file_transfer/*`, `apps/rain/lib/application/files/*`
- Acceptance criteria: Receive path writes chunks incrementally and verifies final size/hash if available.
- Definition of done: Large-file unit/integration tests pass under bounded memory.
- Estimated effort: 4 days

### TASK-011: Add data-channel send backpressure gate

- Status: [ ] Not Started
- Epic: [[File Transfer Optimization Epic]]
- Feature: [[Backpressure Strategy]]
- Description: Pause chunk sends when `bufferedAmount` exceeds threshold and resume only after low-water signal or timer.
- Business value: Reduces file transfer crashes and channel failures.
- Technical value: Honors RTCDataChannel capacity instead of flooding it.
- Risk level: High
- Dependencies: TASK-010
- Files affected: `packages/peer_core/lib/src/file_transfer/*`
- Acceptance criteria: Large sends do not exceed configured buffer budget.
- Definition of done: Backpressure tests simulate slow receiver and disconnect.
- Estimated effort: 3 days

### TASK-012: Fix strict update version validation

- Status: [ ] Not Started
- Epic: [[Production Validation Epic]]
- Feature: [[Version And Updates]]
- Description: Make Remote Config manifest parsing and semantic/build comparison deterministic for old-version prompts.
- Business value: Users get told to update before incompatible rules break the app.
- Technical value: Prevents release drift and wrong "up to date" messages.
- Risk level: Critical
- Dependencies: [[Release Gates]]
- Files affected: `apps/rain/lib/application/update/*`, `apps/rain/test/*`
- Acceptance criteria: Older semantic version and lower build both trigger expected update state.
- Definition of done: Unit and widget tests cover required, optional, invalid, unavailable, and dismissed update states.
- Estimated effort: 2 days

### TASK-013: Validate media capture ordering

- Status: [ ] Not Started
- Epic: [[Signaling Reliability Epic]]
- Feature: [[CallMediaCoordinator]]
- Description: Ensure permission, capture, room claim, accept, and media connection order is platform-safe for Android and Windows.
- Business value: Reduces PC-to-mobile and mobile-to-PC setup failures.
- Technical value: Creates one voice/video setup pipeline.
- Risk level: Critical
- Dependencies: TASK-001, TASK-003
- Files affected: `packages/peer_core/lib/src/media/*`, `apps/rain/lib/application/calls/*`
- Acceptance criteria: Capture failure returns terminal call state and releases leases.
- Definition of done: Tests simulate denied mic/camera and disposed renderer/transceiver.
- Estimated effort: 4 days

### TASK-014: Strengthen diagnostics sanitization

- Status: [ ] Not Started
- Epic: [[Security Hardening Epic]]
- Feature: [[Diagnostics Sanitization]]
- Description: Denylist raw SDP, ICE candidates, tokens, ciphertext, passwords, message text, and file bytes from all diagnostics.
- Business value: Users can share reports without exposing private content.
- Technical value: Makes logging safe enough for support.
- Risk level: High
- Dependencies: [[Privacy Review]]
- Files affected: `apps/rain/lib/application/diagnostics/*`
- Acceptance criteria: Recursive sanitizer redacts sensitive keys and caps string length.
- Definition of done: Tests prove redaction for nested maps/lists.
- Estimated effort: 2 days

### TASK-015: Turn analyzer warnings into release blockers

- Status: [ ] Not Started
- Epic: [[CI-CD Modernization Epic]]
- Feature: [[Release Gates]]
- Description: Make analyze, test, rules validation, and app-level smoke checks required before publishing direct downloads.
- Business value: Broken builds do not reach testers.
- Technical value: Release workflow becomes a quality gate instead of only artifact generation.
- Risk level: High
- Dependencies: [[CI-CD Roadmap]]
- Files affected: `.github/workflows/*`, `melos.yaml`
- Acceptance criteria: Release workflow fails on analyzer/test/rules failures and reports exact failing gate.
- Definition of done: Workflow docs updated and dry-run passes.
- Estimated effort: 2 days

### TASK-016: Consolidate overlapping workflows

- Status: [ ] Not Started
- Epic: [[CI-CD Modernization Epic]]
- Feature: [[CI-CD Roadmap]]
- Description: Split fast artifact workflow from hard release gate while keeping test coverage meaningful.
- Business value: Test apps arrive faster without hiding risk.
- Technical value: Reduces duplicated YAML and inconsistent secrets/defines.
- Risk level: Medium
- Dependencies: TASK-015
- Files affected: `.github/workflows/*`, `docs/*`, `obsidian-vault/10-DevOps/*`
- Acceptance criteria: Workflows have clear purpose: fast test build, hard release gate, PR validation.
- Definition of done: Workflow matrix and artifact paths documented.
- Estimated effort: 2 days

### TASK-017: Add Firebase cost and event budgets

- Status: [ ] Not Started
- Epic: [[Security Hardening Epic]]
- Feature: [[Firebase Architecture]]
- Description: Define allowed read/write rates for presence, calls, ICE candidates, messages, requests, and update checks.
- Business value: Stays within Spark/free-tier operating assumptions.
- Technical value: Prevents accidental high-frequency signaling writes.
- Risk level: High
- Dependencies: [[Firebase Architecture]], [[Rules Strategy]]
- Files affected: `packages/protocol_brain/lib/src/firebase/*`, `obsidian-vault/05-Firebase/*`
- Acceptance criteria: Diagnostics report counters and docs define budgets per feature.
- Definition of done: Counter tests and dashboard docs updated.
- Estimated effort: 2 days

### TASK-018: Add API/signaling adapter contract tests

- Status: [ ] Not Started
- Epic: [[Production Validation Epic]]
- Feature: [[Test Strategy]]
- Description: Test adapters using fake and emulator-backed flows for auth, presence, call rooms, ICE, connection requests, and messages.
- Business value: Prevents regressions before release.
- Technical value: Locks external contracts instead of only UI behavior.
- Risk level: High
- Dependencies: [[Emulator Coverage]]
- Files affected: `packages/protocol_brain/test/*`, `backend/firebase/test/*`
- Acceptance criteria: Each adapter has success, permission denied, malformed payload, and cancellation cases.
- Definition of done: Tests are part of the hard release gate.
- Estimated effort: 5 days

### TASK-019: Centralize call surface rendering

- Status: [ ] Not Started
- Epic: [[Architecture Stabilization Epic]]
- Feature: [[Voice Calls]], [[Video Calls]]
- Description: Render only one call surface at a time from one presentation state: fullscreen, minimized bar, video PiP, ended, or failed.
- Business value: Removes duplicated bars, bad overlays, and inconsistent controls.
- Technical value: UI follows a single source of truth.
- Risk level: High
- Dependencies: TASK-003, [[Target Architecture]]
- Files affected: `apps/rain/lib/presentation/calls/*`, `apps/rain/lib/presentation/home/*`
- Acceptance criteria: Widget tests prove no duplicate call bars and safe-area placement.
- Definition of done: Popup mode is removed or unreachable and docs updated.
- Estimated effort: 4 days

### TASK-020: Stabilize Home and Chat provider boundaries

- Status: [ ] Not Started
- Epic: [[Architecture Stabilization Epic]]
- Feature: [[Frontend Architecture]]
- Description: Reduce broad rebuilds by isolating call, connection, messages, friends, and diagnostics provider watches.
- Business value: Less lag on ARMv7 and slow devices.
- Technical value: Cleaner state boundaries and lower rendering cost.
- Risk level: Medium
- Dependencies: TASK-009, TASK-019
- Files affected: `apps/rain/lib/presentation/home/*`, `apps/rain/lib/presentation/chat/*`
- Acceptance criteria: Message changes do not rebuild header, call controls, or full friends panel.
- Definition of done: Widget tests cover rebuild isolation and low-power visual path.
- Estimated effort: 4 days

### TASK-021: Add ARMv7 and low-power performance budget

- Status: [ ] Not Started
- Epic: [[Production Validation Epic]]
- Feature: [[Frontend Architecture]]
- Description: Define and test the reduced visual/performance path for ARMv7 and low-power devices.
- Business value: Slow devices get usable scrolling and call surfaces instead of premium effects that lag.
- Technical value: Makes performance expectations measurable instead of subjective.
- Risk level: High
- Dependencies: [[Release Gates]], [[Coverage Dashboard]], TASK-020
- Files affected: `apps/rain/lib/presentation/*`, `apps/rain/lib/application/diagnostics/*`, `obsidian-vault/09-Testing/*`
- Acceptance criteria: Low-power mode disables expensive non-essential effects and exports frame/performance summaries safely.
- Definition of done: Low-power widget tests and diagnostics summary tests pass.
- Estimated effort: 3 days

### TASK-022: Maintain vault and memory as release artifacts

- Status: [ ] Not Started
- Epic: [[Production Validation Epic]]
- Feature: [[Project Memory]]
- Description: Keep [[Project Memory]], roadmap, risk, debt, blocker, and lesson notes aligned with completed implementation work.
- Business value: Future sessions and maintainers do not rediscover solved problems or repeat failed approaches.
- Technical value: Keeps the Obsidian vault useful as an engineering control system.
- Risk level: Medium
- Dependencies: [[Documentation Workflow]], [[Knowledge Graph Index]]
- Files affected: `obsidian-vault/**/*`, `scripts/check_obsidian_vault.ps1`
- Acceptance criteria: Major changes update relevant vault notes and no broken wiki links remain.
- Definition of done: Vault validation passes and release workflow treats documentation as required evidence.
- Estimated effort: 1 day setup, ongoing per change

### TASK-023: Enforce offline-only connection request messaging

- Status: [ ] Not Started
- Epic: [[Security Hardening Epic]]
- Feature: [[Connection Request Notifications]]
- Description: Ensure offline notification request limits are spent only when fresh backend presence proves the peer is offline/stale and the user confirms the action.
- Business value: Users are not charged request quota for normal online direct connect, and every blocked action explains why.
- Technical value: Prevents abuse and keeps Spark/free-tier request writes bounded.
- Risk level: Critical
- Dependencies: [[Presence Management]], [[Rules Strategy]], [[Connection Request Notifications]]
- Files affected: `apps/rain/lib/application/connection_requests/*`, `packages/protocol_brain/lib/src/connection_requests/*`, `backend/firebase/database.rules.json`
- Acceptance criteria: Online peers use direct connect; offline/stale peers require confirmation; unknown presence fails closed with a message.
- Definition of done: Runtime, adapter, rules, and widget tests cover confirmation-required, online-denied, offline-allowed, stale-allowed, quota-exceeded, and presence-unknown cases.
- Estimated effort: 3 days

## Backlog Links

- Roadmap: [[Master Roadmap]]
- Sprint: [[Active Sprint]]
- Tracker: [[Audit Resolution Tracker]]
- Debt: [[Technical Debt Register]]
