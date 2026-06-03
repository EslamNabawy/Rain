# Epic Index

Last updated: 2026-06-03

## Purpose

This index groups every [[Original Audit]] finding into execution epics. The detailed hierarchy lives in [[Master Roadmap]].

Related: [[Audit Resolution Tracker]], [[Backlog]], [[Critical Path]], [[Parallel Work Streams]].

## Production Readiness Epics

| Epic | Features | Tasks |
| --- | --- | --- |
| [[Architecture Stabilization Epic]] | Runtime Responsibility Split; Call Surface Single Source; Provider Boundary Cleanup | TASK-001, TASK-019, TASK-020 |
| [[Signaling Reliability Epic]] | Call Lease Repair; Explicit Call State Machine; Presence Freshness; Watch Stream Resilience; WebRTC Failure Classification; Media Capture Ordering | TASK-002, TASK-003, TASK-004, TASK-006, TASK-007, TASK-013 |
| [[Database Scalability Epic]] | Index Strategy; Conversation Pagination | TASK-008, TASK-009 |
| [[File Transfer Optimization Epic]] | Persistent Receive Streaming; Data Channel Backpressure | TASK-010, TASK-011 |
| [[Security Hardening Epic]] | Firebase Rule Coverage; Diagnostics Privacy; Firebase Cost Guardrails; Offline Request Guardrails | TASK-005, TASK-014, TASK-017, TASK-023 |
| [[CI-CD Modernization Epic]] | Release Gate Parity; Workflow Ownership | TASK-015, TASK-016 |
| [[Production Validation Epic]] | Update Version Validation; Adapter Contract Tests; Performance Tier Validation; Continuous Knowledge Maintenance | TASK-012, TASK-018, TASK-021, TASK-022 |

## Epic Rules

- Every task in [[Backlog]] must link to one epic and one feature in [[Master Roadmap]].
- Every audit finding in [[Audit Resolution Tracker]] must map to at least one task.
- P0 tasks block public release until complete or explicitly accepted in [[Launch Readiness]].
- Epic notes must stay aligned with [[Project Memory]] and [[Technical Debt Register]] when implementation changes durable architecture.

## Execution Links

- Roadmap: [[Master Roadmap]]
- 30 day plan: [[30 Day Plan]]
- 60 day plan: [[60 Day Plan]]
- 90 day plan: [[90 Day Plan]]
- Critical path: [[Critical Path]]
- Launch blockers: [[Launch Blockers]]
