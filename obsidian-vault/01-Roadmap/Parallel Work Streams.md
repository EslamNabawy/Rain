# Parallel Work Streams

Last updated: 2026-06-03

## Purpose

Identify work that can proceed safely in parallel without blocking the [[Critical Path]].

Related: [[Master Roadmap]], [[30 Day Plan]], [[60 Day Plan]], [[90 Day Plan]], [[High-Risk Work]].

## Streams

| Stream | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| Call reliability | P0 | [[VoiceCallRuntime Refactor]], [[Call State Machine]] | 17 days | Calls have explicit start, media, lease, terminal, and diagnostic ownership. | TASK-001, TASK-002, TASK-003, TASK-013 complete. |
| Firebase/security | P0 | [[Firebase Architecture]], [[Rules Strategy]] | 9 days | Rules, locks, costs, privacy, and offline request guardrails are tested. | TASK-005, TASK-014, TASK-017, TASK-023 complete. |
| Update/release | P0/P1 | [[Version And Updates]], [[Release Gates]] | 6 days | Old-app update state and artifact gates are deterministic. | TASK-012, TASK-015 complete. |
| Database/file scale | P1 | [[Database Architecture]], [[File Transfer]] | 14 days | Messages paginate and files stream with backpressure. | TASK-008, TASK-009, TASK-010, TASK-011 complete. |
| UI/performance | P1/P2 | TASK-003, TASK-009 | 11 days | Call surface is unified and low-power path is validated. | TASK-019, TASK-020, TASK-021 complete. |
| Knowledge/validation | P2 | [[Project Memory]], [[Documentation Workflow]] | Ongoing | Roadmap, memory, lessons, risks, and docs remain current. | TASK-022 complete and vault validation passes. |

## Parallelization Rule

- Do not start UI call-surface consolidation before TASK-003 defines terminal state.
- Do not start release gate closure before TASK-005 and TASK-012 are testable.
- Database/file scale work can proceed while call reliability work runs, as long as app runtime behavior is not changed by both streams at once.
