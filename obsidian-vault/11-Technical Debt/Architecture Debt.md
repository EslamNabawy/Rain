# Architecture Debt

Last updated: 2026-06-03

## Purpose

Architecture debt covers unclear ownership, overloaded runtime modules, duplicated state truth, and fragmented presentation contracts.

Related: [[Technical Debt Register]], [[Debt Categories]], [[VoiceCallRuntime Refactor]], [[Target Architecture]], [[Refactoring Strategy]].

## Items

| Debt | Priority | Core System | Roadmap Task |
| --- | --- | --- | --- |
| TD-001 Oversized VoiceCallRuntime | P0 | [[VoiceCallRuntime Refactor]] | TASK-001 |
| TD-002 RainRuntimeController domain concentration | P1 | [[Current Architecture]] | TASK-001, TASK-020 |
| TD-003 Distributed call lease and terminal ownership | P0 | [[Lease Management]] | TASK-002 |
| TD-004 Implicit async call state machine | P0 | [[Call State Machine]] | TASK-003, TASK-013 |
| TD-005 Fragmented call surface model | P1 | [[Frontend Architecture]] | TASK-019 |

## Priority

Start with TD-001 because it creates the seams needed for TD-003 and TD-004. UI surface consolidation waits until terminal call state is reliable.

