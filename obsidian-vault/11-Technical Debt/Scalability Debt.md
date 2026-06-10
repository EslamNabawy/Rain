# Scalability Debt

Last updated: 2026-06-05

## Purpose

Scalability debt covers data volume, local persistence growth, large file transfers, and free-tier growth pressure.

Related: [[Technical Debt Register]], [[Debt Categories]], [[Database Architecture]], [[File Transfer]], [[Streaming Architecture]], [[Backpressure Strategy]].

## Items

| Debt | Priority | Core System | Roadmap Task |
| --- | --- | --- | --- |
| TD-006 Missing local database index validation | P1 | [[Index Strategy]] | TASK-008 |
| TD-007 Eager conversation loading | P1 | [[Pagination Strategy]] | TASK-009 |
| TD-008 File transfer streaming and backpressure proof | P1, mitigating locally | [[Streaming Architecture]] | TASK-010, TASK-011 |

## Priority

Run index work before pagination. Run receive-streaming characterization before send-backpressure changes so transfer cleanup behavior is defined.

2026-06-05 update: TASK-010 and TASK-011 now have focused local proof for persistent receive sinks, send backpressure, cancel/hash/write-failure cleanup, and temp deletion. Keep real-network/device-scale large-transfer proof as the remaining release-confidence item.
