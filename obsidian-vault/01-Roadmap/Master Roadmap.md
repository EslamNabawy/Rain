# Master Roadmap

This roadmap converts the authoritative audit into an execution program.

## Phase 1 - Architecture Stabilization

Objectives:

- Reduce runtime god objects.
- Split call start, media, lease, terminal reconciliation, and diagnostics.
- Stop UI state from hiding signaling failures as media failures.

Deliverables:

- [[VoiceCallRuntime Refactor]]
- [[CallStartCoordinator]]
- [[CallLeaseManager]]
- [[CallMediaCoordinator]]
- [[CallTerminalReconciler]]
- [[CallDiagnosticsRecorder]]

Risks:

- Regression in working call paths.
- Over-splitting without tests.

Dependencies:

- [[Original Audit]]
- [[Test Strategy]]

Success criteria:

- Call runtime responsibilities are separated.
- New call phases are visible and tested.
- No duplicate call state ownership.

Completion metrics:

- `VoiceCallRuntime` reduced below 1,500 lines or split behind tested coordinators.
- Runtime tests cover call start, failure, and terminal paths.

## Phase 2 - Signaling Reliability

Objectives:

- Eliminate false busy.
- Make call leases repairable and observable.
- Fail fast on signaling candidate write/read failures.

Deliverables:

- [[Signaling Architecture]]
- [[Lease Management]]
- [[Call State Machine]]
- [[Presence Management]]
- [[Firebase Architecture]]
- [[Rules Strategy]]
- [[Emulator Coverage]]

Success criteria:

- Stale locks are repaired before busy is shown.
- Offline wins over busy.
- ICE signaling failure is not mislabeled as generic media failure.

## Phase 3 - Database Scalability

Objectives:

- Make local data scale beyond small test accounts.
- Remove full-list conversation assumptions.

Deliverables:

- [[Index Strategy]]
- [[Pagination Strategy]]
- [[Migration Plan]]

Success criteria:

- Indexed conversation query.
- Paginated message loading.
- Migration tests from current schema.

## Phase 4 - File Transfer Optimization

Objectives:

- Remove chunk-copy and file-sink churn.
- Keep file transfer reliable under congestion.

Deliverables:

- [[Streaming Architecture]]
- [[Backpressure Strategy]]

Success criteria:

- Large transfer path avoids repeated list-front removal.
- Receiver uses persistent sink per transfer.
- Backpressure is event-driven or less polling-heavy.

## Phase 5 - Security Hardening

Objectives:

- Harden diagnostics privacy.
- Reduce Firebase rules drift.
- Keep demo/stable release boundaries clear.

Deliverables:

- [[Security Roadmap]]
- [[Privacy Review]]
- [[Diagnostics Sanitization]]

Success criteria:

- Raw error strings are sanitized.
- Rules tests cover allowed and denied branches.
- Release builds reject demo secrets.

## Phase 6 - CI/CD Modernization

Objectives:

- Make release gates consistent.
- Reduce workflow duplication.

Deliverables:

- [[CI-CD Roadmap]]
- [[Release Gates]]

Success criteria:

- Shared workflow actions for analyze/test/firebase/build.
- Documentation vault gate passes in CI.
- Release artifacts prove latest commit and version.

## Phase 7 - Production Readiness Validation

Objectives:

- Prove readiness with automated and manual gates.
- Move score from 48/100 to 90/100.

Deliverables:

- [[Coverage Dashboard]]
- [[Emulator Test Matrix]]
- [[Milestones]]
- [[Weekly Progress]]

Success criteria:

- Repeated Android/Windows voice/video calls pass.
- Update behavior passes old/new/current scenarios.
- Firebase permission denied has typed root-cause diagnostics.

Related: [[30 Day Plan]], [[60 Day Plan]], [[90 Day Plan]], [[Sprint Planning]], [[Critical Path]].
