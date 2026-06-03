# Milestones

Last updated: 2026-06-03

## M1: Architecture Stabilization

- Target: Runtime split is complete.
- Exit criteria: [[VoiceCallRuntime Refactor]] delegates to coordinators and tests pass.
- Related roadmap phase: [[Master Roadmap]]
- Status: [ ] Open

## M2: Reliable Calls

- Target: Voice/video call start and terminal paths are deterministic.
- Exit criteria: [[CallStartCoordinator]], [[CallLeaseManager]], and [[CallTerminalReconciler]] pass runtime and emulator tests.
- Status: [ ] Open

## M3: Spark-Safe Firebase

- Target: Firebase RTDB rules enforce the core protocol while staying on free tier.
- Exit criteria: [[Rules Strategy]] and [[Emulator Coverage]] validate allowed and denied writes.
- Status: [ ] Open

## M4: Scalable Local Data And Transfers

- Target: Chat and file transfer scale without avoidable lag or memory pressure.
- Exit criteria: [[Index Strategy]], [[Pagination Strategy]], and [[Backpressure Strategy]] pass tests.
- Status: [ ] Open

## M5: Hard Release Gate

- Target: Release workflow builds only after critical quality gates.
- Exit criteria: [[Release Gates]] covers app tests, rules tests, update validation, and artifact publication.
- Status: [ ] Open

Related: [[Weekly Progress]], [[30 Day Plan]], [[60 Day Plan]], [[90 Day Plan]].
