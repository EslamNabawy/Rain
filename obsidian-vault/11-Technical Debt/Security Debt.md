# Security Debt

Last updated: 2026-06-03

## Purpose

Security debt covers Firebase rule proof, malformed signaling protection, diagnostics privacy, and Spark/free-tier abuse controls.

Related: [[Technical Debt Register]], [[Debt Categories]], [[Security Roadmap]], [[Rules Strategy]], [[Diagnostics Sanitization]], [[Firebase Architecture]].

## Items

| Debt | Priority | Core System | Roadmap Task |
| --- | --- | --- | --- |
| TD-009 Firebase rule coverage gaps | P0 | [[Rules Strategy]] | TASK-005 |
| TD-010 Diagnostics privacy exposure | P1 | [[Diagnostics Sanitization]] | TASK-014 |
| TD-011 Malformed signaling write protection | P0 | [[Firebase Architecture]] | TASK-005 |
| TD-012 Spark-free-tier guardrails are not fully instrumented | P1 | [[Connection Request Notifications]] | TASK-017, TASK-023 |

## Priority

Rules coverage and malformed signaling protection are release-critical. Diagnostics privacy and Firebase budget counters can run in parallel if they do not change signaling behavior.

