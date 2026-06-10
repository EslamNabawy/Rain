# DevOps Debt

Last updated: 2026-06-03

## Purpose

DevOps debt covers release gates, workflow ownership, update validation, artifact traceability, and old-client safety.

Related: [[Technical Debt Register]], [[Debt Categories]], [[CI-CD Roadmap]], [[Release Gates]], [[Version And Updates]].

## Items

| Debt | Priority | Core System | Roadmap Task |
| --- | --- | --- | --- |
| TD-017 Weak release gate parity | P0 | [[Release Gates]] | TASK-015 |
| TD-018 Update version validation failures | P0 | [[Version And Updates]] | TASK-012 |

## Priority

Fix update validation before backend/rules changes reach old clients. Harden release gates before publishing more test artifacts as release candidates.

