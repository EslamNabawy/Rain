# Rain Project Operating System

Last updated: 2026-06-04

This file is the project constitution. It defines how Rain should be engineered, documented, validated, and improved over time.

Phase 0 establishes the operating model only. Future phases will populate architecture, risks, roadmaps, tasks, metrics, knowledge graph data, and self-improvement systems.

## Project Vision

Rain is a private peer-to-peer communication app for trusted friends. It should provide chat, presence, direct connection, file transfer, voice calls, and video calls with clear state, reliable failure handling, and strong privacy expectations.

The long-term project vision is not only to build the app, but to build a repository that explains itself and improves through documented decisions, tracked debt, repeatable validation, and durable project memory.

## Engineering Philosophy

- Correctness first.
- Reliability before visual polish.
- Security and privacy are design constraints, not optional cleanup.
- Simple architecture beats clever hidden machinery.
- Every state transition should be explainable.
- Every critical failure should be diagnosable.
- Every important decision should be recorded.
- Every release should be gated by validation appropriate to its risk.

## Governance Priority Order

When instructions or sources conflict, resolve them in this order:

1. Actual repository implementation.
2. `AGENTS.md`.
3. `CONTINUITY.md`.
4. [[Current Architecture]].
5. [[Project Memory]].
6. [[Risk Register]].
7. [[BLOCKERS]].
8. [[Technical Debt Register]].
9. User request.
10. External examples.

Repository implementation is the primary source of truth. External examples and generated plans are advisory only until reconciled with repository behavior and vault source notes.

## Reality Enforcement

Rain governance requires verifiable reporting:

- Do not claim a file changed unless the file actually changed.
- Do not claim tests, builds, vault validation, CI, or commits succeeded unless they were run and verified.
- If validation was not run, report `Not executed.`
- If vault validation was not run after documentation changes, report `Vault validation not executed.`
- If a blocker prevents completion, record it in [[BLOCKERS]] or `CONTINUITY.md` when it affects active work.

## Documentation Philosophy

Documentation is part of the system.

Good documentation should:

- Preserve decisions and context.
- Explain why a system exists.
- Identify risks and limits.
- Give future engineers enough information to continue safely.
- Link related knowledge through Obsidian-style notes.
- Stay current with code and process changes.

Bad documentation is stale, vague, disconnected, or detached from actual work.

## Architecture Philosophy

Rain should move toward clear separation between:

- UI presentation
- App/runtime orchestration
- Domain rules
- Firebase adapters
- WebRTC/media adapters
- Persistence
- Diagnostics
- Release and validation systems

Core architecture rules:

- One source of truth for each runtime state.
- No duplicated call, presence, file transfer, or update decision logic.
- No hidden Firebase writes from UI widgets.
- No UI-only state that can contradict runtime truth.
- No sensitive payloads in diagnostics.
- No paid backend dependency unless product constraints change.

## Quality Standards

Quality means:

- The behavior is correct.
- The failure mode is handled.
- The error message is useful.
- The state can recover or terminate cleanly.
- The code is testable.
- The documentation records important implications.

Quality does not mean adding abstractions without a concrete reliability or maintainability benefit.

## Autonomous Workflow Nodes

Meaningful work should move through these nodes. The current node should be stated during non-trivial work so future sessions can reconstruct progress without guessing.

| Node | Name | Required Output |
| --- | --- | --- |
| 0 | Environment Verification | Repository path, branch, git status, workspace health, vault availability. |
| 1 | Knowledge Synchronization | Mission summary, relevant architecture, risks, blockers, and debt. |
| 2 | Repository Discovery | Existing implementation, related modules, abstractions, tests, and TODOs. |
| 3 | Task Understanding | Requested change, scope, assumptions, and unknowns. |
| 4 | Impact Analysis | Architecture, database, Firebase, WebRTC, security, performance, operational, migration, and documentation impact. |
| 5 | Pattern Discovery | Existing Rain patterns first; external references only after internal review. |
| 6 | Architecture Validation | Riverpod, package, Firebase, WebRTC, and ownership-boundary compliance. |
| 7 | Implementation Plan | Ordered plan before coding. |
| 8 | Execution | Production-quality implementation within established patterns. |
| 9 | Validation | Executed checks or explicit `Not executed.` |
| 10 | Obsidian Synchronization | Updated affected vault notes or explicit reason not updated. |
| 11 | Vault Validation | `.\scripts\check_obsidian_vault.ps1` result or explicit `Vault validation not executed.` |
| 12 | Production Readiness Review | Security, error handling, logging, offline behavior, Firebase quota, WebRTC failure modes, and recovery paths. |
| 13 | Version Control Preparation | Focused git add/commit preparation when the task is complete and committable. |
| 14 | Completion Report | Work completed, files changed, validation, vault updates, risks, debt, and follow-up work. |

## Testing Standards

Testing should match risk.

Minimum expectations:

- Unit tests for domain rules and parsing.
- Runtime tests for call, signaling, connection, file transfer, and update state machines.
- Firebase rules or emulator tests for security-sensitive RTDB behavior.
- Widget tests for critical UI state and safe-area behavior.
- Integration or smoke tests for end-to-end app flows when tooling is available.

No critical release should depend only on manual testing.

## Security Standards

Security expectations:

- Do not store secrets in source.
- Do not log passwords, tokens, SDP, ICE candidates, ciphertext, message text, or file bytes.
- Firebase rules must enforce ownership and valid transitions.
- Diagnostics must be sanitized and bounded.
- User-facing features must fail closed when authorization or presence cannot be confirmed.
- Release builds must not use demo-only production secrets or keys.

## Definition Of Done

A change is done only when:

- The requested behavior is implemented.
- Relevant validation has passed or a clear reason is recorded.
- Error and edge cases are handled.
- No unrelated user changes were reverted.
- Relevant documentation is updated.
- Relevant debt, risk, or blocker records are updated.
- `CONTINUITY.md` reflects important active state changes.
- The final response states what changed and what validation ran.

For documentation-only work, code tests are not required unless documentation tooling or generated artifacts depend on them.

## Continuous Improvement Process

After major work:

1. Record durable lessons in project memory.
2. Add new risks or blockers when discovered.
3. Convert unresolved issues into debt or backlog items.
4. Update roadmaps and status notes.
5. Improve validation when a regression escapes existing tests.
6. Keep future work dependency-driven.

The repository should become easier to work on after each phase.

## Phase 0 Constraint

Do not overbuild in Phase 0. This file defines the constitution. Future phases will create detailed architecture documentation, knowledge graph structure, audit conversion, metrics, and automation.
