# Security Risk View

Last updated: 2026-06-05

## Purpose

This note is the security-focused view of the central [[Risk Register]].

Related: [[Security Roadmap]], [[Rules Strategy]], [[Diagnostics Sanitization]], [[Privacy Review]], [[Firebase Architecture]], [[Security Debt]], [[BLOCKERS]].

## Security Risks

| Risk | Severity | Central ID | Mitigation |
| --- | --- | --- | --- |
| Firebase rules allow malformed or unauthorized writes. | Critical | R-014 | Expand [[Rules Strategy]] and [[Emulator Coverage]]. |
| Diagnostics expose sensitive metadata or payloads. | High | R-015 | Enforce [[Diagnostics Sanitization]] and export tests. |
| Local Drift/SQLite data is plaintext. | High | SAR-005 | Accepted/documented in [[ADR-010]]; do not claim local message encryption unless a future encryption phase lands with migration proof. |
| Offline request notifications can be abused or spend quota incorrectly. | High | R-016 | Enforce offline-only request rules through [[Connection Request Notifications]] and [[Presence Management]]. |
| Spark/free-tier constraints limit backend authority and cleanup. | High | R-017 | Use [[Firebase Architecture]] cost counters, TTL fields, and RTDB rules. |

## Security Blockers

- BLK-003: Firebase rules and app behavior must stay Spark-safe.
- BLK-005: Diagnostics must explain failures without leaking data.
- BLK-009: Offline request guardrails can spend quota or block silently.

SAR-005 is not a runtime blocker after the 2026-06-05 acceptance, but it remains a claim blocker: release, support, and privacy material must not imply local database encryption.

See [[Blocker Resolution Plan]] for ownership and workaround details.
