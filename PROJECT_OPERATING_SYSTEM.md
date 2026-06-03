# Rain Project Operating System

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
