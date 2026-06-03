# Improvement Backlog

Last updated: 2026-06-03

## Purpose

This backlog converts recurring patterns from [[Engineering Insights]] and [[Lessons Learned]] into process, architecture, testing, and automation improvements.

Related: [[Continuous Improvement Log]], [[Optimization Opportunities]], [[Recommended Next Actions]], [[Project Metrics]], [[Master Roadmap]].

## Improvement Items

| ID | Category | Improvement | Source Pattern | Priority | Owner | Success Criteria | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| IMP-001 | Testing | Add call failure taxonomy tests before more call fixes. | Symptom-first debugging | P0 | Engineering | Diagnostics classify Firebase, permission, ICE, TURN, media, renderer, terminal state. | Open |
| IMP-002 | Testing | Add RTDB rules emulator gate before release artifacts are trusted. | Backend-contract drift | P0 | Security/Engineering | Rules allow/deny matrix runs and blocks hard release when failing. | Open |
| IMP-003 | Architecture | Make `PeerAvailabilityResolver` the action truth source. | Stale state ambiguity | P0 | Engineering | Connect/call/request decisions use fresh backend presence, not stale UI state. | Open |
| IMP-004 | Architecture | Make `CallLeaseManager` the only call lease authority. | Stale state ambiguity | P0 | Engineering | Busy is returned only after room/lock inspection. | Open |
| IMP-005 | Architecture | Use one call surface renderer and one control model. | UI surface fragmentation | P1 | Product/UI | No duplicate call bars or unsafe overlays in widget tests. | Open |
| IMP-006 | DevOps | Label every artifact with gate status, commit, version, and channel. | Artifact trust ambiguity | P1 | DevOps | Testers can distinguish fast test builds from hard-gated builds. | Open |
| IMP-007 | DevOps | Make vault validation part of every hard release gate. | Knowledge loss | P1 | DevOps | Broken links or missing required notes block release promotion. | Open |
| IMP-008 | Performance | Track low-power/ARMv7 UI budget in diagnostics and tests. | Slow-device regressions | P1 | Engineering/UI | Low-power path has explicit visual and frame-summary checks. | Open |
| IMP-009 | Scalability | Add bounded local data tests for messages and file transfers. | Small-test bias | P1 | Engineering | Large message/file scenarios are covered before release. | Open |
| IMP-010 | Process | Require lesson capture after completed tasks. | Knowledge loss | P1 | Engineering | Every completed task updates [[Lessons Learned]] or states no new lesson. | Open |
| IMP-011 | Automation | Add recurring-pattern review to weekly progress. | Repeated failures | P2 | Engineering | [[Weekly Progress]] includes patterns and recommended next actions. | Open |
| IMP-012 | Product | Maintain user-facing blocked-action message matrix. | Silent/unclear failures | P0 | Product/UI | Every guardrail denial has a deterministic message and widget test. | Open |

## Backlog Conversion Rule

Convert an improvement into a roadmap task when:

- it blocks release,
- it appears in three or more lessons,
- it maps to a Critical or High risk,
- it can be automated,
- it reduces repeated manual debugging.

## Status Review

- P0 improvements: review before release workflows.
- P1 improvements: review during sprint planning.
- P2 improvements: review weekly.

