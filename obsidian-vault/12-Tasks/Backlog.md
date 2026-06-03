# Backlog

Last updated: 2026-06-03

## Purpose

This backlog is the execution queue generated from [[Original Audit]]. The full Epic -> Feature -> Task -> Subtask hierarchy is in [[Master Roadmap]].

Related: [[Epic Index]], [[Audit Resolution Tracker]], [[Critical Path]], [[Active Sprint]], [[Technical Tasks]].

## Audit-Derived Tasks

| Task | Epic | Feature | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- | --- | --- |
| TASK-001 | [[Architecture Stabilization Epic]] | Runtime Responsibility Split | P0 | [[Current Architecture]], [[VoiceCallRuntime Refactor]] | 5 days | `VoiceCallRuntime` responsibilities are split into testable coordinators. | Coordinator tests pass and architecture docs update. |
| TASK-002 | [[Signaling Reliability Epic]] | Call Lease Repair | P0 | TASK-001, [[Lease Management]] | 4 days | Stale locks repair once before busy. | Fake/emulator lock tests pass. |
| TASK-003 | [[Signaling Reliability Epic]] | Explicit Call State Machine | P0 | TASK-001, TASK-002 | 4 days | Terminal room state clears both local and remote runtime. | Runtime tests prove no stuck connecting. |
| TASK-004 | [[Signaling Reliability Epic]] | WebRTC Failure Classification | P1 | TASK-001, [[CallDiagnosticsRecorder]] | 3 days | Call diagnostics distinguish Firebase, permission, ICE, TURN, media, and first-frame failures. | Sanitized timeline export tests pass. |
| TASK-005 | [[Security Hardening Epic]] | Firebase Rule Coverage | P0 | [[Rules Strategy]], [[Emulator Coverage]] | 4 days | RTDB rules reject malformed/unauthorized signaling writes. | Emulator/rules allow-deny tests pass. |
| TASK-006 | [[Signaling Reliability Epic]] | Presence Freshness | P0 | [[Presence Management]], [[Firebase Architecture]] | 3 days | Stale/offline peers cannot appear freshly callable or connectable. | Presence/app-close tests pass. |
| TASK-007 | [[Signaling Reliability Epic]] | Watch Stream Resilience | P1 | [[Firebase Architecture]], [[Diagnostics Sanitization]] | 2 days | Corrupt room/inbox data does not poison watch streams. | Corrupt record tests pass and watcher continues. |
| TASK-008 | [[Database Scalability Epic]] | Index Strategy | P1 | [[Database Architecture]], [[Migration Plan]] | 3 days | Critical local queries have explicit indexes. | Drift migration tests pass. |
| TASK-009 | [[Database Scalability Epic]] | Conversation Pagination | P1 | TASK-008, [[Pagination Strategy]] | 4 days | Conversation loads are bounded and paginated. | Pagination widget/provider tests pass. |
| TASK-010 | [[File Transfer Optimization Epic]] | Persistent Receive Streaming | P1 | [[Streaming Architecture]], [[File Transfer]] | 4 days | Incoming file chunks stream to disk without large memory retention. | Large receive tests pass with temp cleanup. |
| TASK-011 | [[File Transfer Optimization Epic]] | Data Channel Backpressure | P1 | TASK-010, [[Backpressure Strategy]] | 3 days | Sender pauses/resumes based on data-channel buffer budget. | Slow receiver tests pass. |
| TASK-012 | [[Production Validation Epic]] | Update Version Validation | P0 | [[Version And Updates]], [[Release Gates]] | 2 days | Old app versions show correct update state. | Version parser and prompt tests pass. |
| TASK-013 | [[Signaling Reliability Epic]] | Media Capture Ordering | P0 | TASK-001, TASK-003 | 4 days | Permission/capture failures terminate and release locks cleanly. | Media failure tests pass. |
| TASK-014 | [[Security Hardening Epic]] | Diagnostics Privacy | P1 | [[Diagnostics Sanitization]], [[Privacy Review]] | 2 days | Sensitive diagnostics payloads are recursively redacted. | Sanitizer tests pass. |
| TASK-015 | [[CI-CD Modernization Epic]] | Release Gate Parity | P1 | [[Release Gates]], [[Test Strategy]] | 2 days | Artifact publication cannot bypass critical gates. | Workflow gate evidence exists. |
| TASK-016 | [[CI-CD Modernization Epic]] | Workflow Ownership | P2 | TASK-015, [[CI-CD Roadmap]] | 2 days | Fast artifacts, PR checks, and hard release gates have clear ownership. | Workflow map is documented. |
| TASK-017 | [[Security Hardening Epic]] | Firebase Cost Guardrails | P1 | [[Firebase Architecture]], [[Diagnostics And Logging]] | 2 days | Firebase operation budgets and counters exist. | Diagnostics export includes budget counters. |
| TASK-018 | [[Production Validation Epic]] | Adapter Contract Tests | P1 | [[Emulator Coverage]], [[Test Strategy]] | 5 days | Fake and Firebase adapters cover success/failure/corruption/cancel paths. | Contract tests are part of release evidence. |
| TASK-019 | [[Architecture Stabilization Epic]] | Call Surface Single Source | P1 | TASK-003, [[Voice Calls]], [[Video Calls]] | 4 days | UI renders only one valid call surface at a time. | Widget tests prove no duplicate bars or unsafe overlays. |
| TASK-020 | [[Architecture Stabilization Epic]] | Provider Boundary Cleanup | P2 | TASK-009, TASK-019 | 4 days | Chat, friends, call, and diagnostics updates rebuild only relevant UI. | Rebuild isolation tests pass. |
| TASK-021 | [[Production Validation Epic]] | Performance Tier Validation | P1 | [[Frontend Architecture]], [[Release Gates]] | 3 days | ARMv7/low-power expectations are explicit and tested. | Low-power path tests and diagnostics summary pass. |
| TASK-022 | [[Production Validation Epic]] | Continuous Knowledge Maintenance | P2 | [[Project Memory]], [[Documentation Workflow]] | 1 day setup | Documentation remains a release artifact. | Vault validation and memory update rules stay current. |
| TASK-023 | [[Security Hardening Epic]] | Offline Request Guardrails | P0 | [[Connection Request Notifications]], [[Presence Management]], [[Rules Strategy]] | 3 days | Offline request quota is spent only after offline confirmation. | Runtime, adapter, rules, and widget tests cover all blocked messages. |

## Backlog Definition Of Done

- Status changes are mirrored in [[Audit Resolution Tracker]].
- Completed tasks update [[Project Memory]] when they change durable project facts.
- Any unresolved production risk is recorded in [[Risk Register]].
- Documentation links remain valid under the vault checker.
