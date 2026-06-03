# Performance Debt

Last updated: 2026-06-03

## Purpose

Performance debt covers low-power device behavior, broad UI rebuilds, and rendering paths that can make the app feel unstable.

Related: [[Technical Debt Register]], [[Debt Categories]], [[Frontend Architecture]], [[Coverage Dashboard]], [[Performance Debt]].

## Items

| Debt | Priority | Core System | Roadmap Task |
| --- | --- | --- | --- |
| TD-013 ARMv7 and low-power budget missing | P1 | [[Frontend Architecture]] | TASK-021 |
| TD-014 Broad UI rebuild boundaries | P2 | [[Frontend Architecture]] | TASK-020 |

## Priority

Define the low-power budget before broad UI polish. Provider-boundary work should follow pagination and call surface cleanup so rebuild tests target the final surfaces.

