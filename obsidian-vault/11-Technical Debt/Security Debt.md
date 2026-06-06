# Security Debt

Last updated: 2026-06-05

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
| SAR-005 Local data at rest accepted plaintext scope | P1 | [[Privacy Review]] | [[ADR-010]] |

## Priority

Rules coverage and malformed signaling protection are release-critical. Diagnostics privacy and Firebase budget counters can run in parallel if they do not change signaling behavior.

2026-06-05 update: TD-010 is locally mitigated for covered diagnostics export samples through the shared recursive sanitizer. Keep sanitizer regressions mandatory for new private diagnostics fields.

Local data at rest is accepted as plaintext for the current implementation. This is not a security fix; it is an explicit scope decision that blocks any claim of local database encryption until a future encrypted-storage phase is implemented and migration-tested.
