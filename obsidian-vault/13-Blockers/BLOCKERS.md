# BLOCKERS Index

Last updated: 2026-06-03

## Purpose

This note is a lightweight index for the operational blocker system. The detailed source of truth is [[BLOCKERS]] in `14-Blockers`.

Related: [[Risk Register]], [[Blocker Resolution Plan]], [[Launch Blockers]], [[Critical Path]], [[Launch Readiness]].

## Active Blocker Summary

| Blocker | Severity | Owner | Main Workaround |
| --- | --- | --- | --- |
| BLK-001 Call setup reliability | Critical | Engineering | Keep releases as test builds and require diagnostics. |
| BLK-002 False busy/stale locks | Critical | Engineering | Inspect room/lock evidence before treating busy as final. |
| BLK-003 Spark-safe Firebase rules | High | Security/Engineering | Use RTDB rules, TTL fields, and client cleanup. |
| BLK-004 Update prompt reliability | Critical | Product/DevOps | Keep manual downloads and avoid incompatible rule deployments. |
| BLK-005 Diagnostics safety/usefulness | High | Security/Engineering | Local-only exports and schema review. |
| BLK-006 Release gate evidence | High | DevOps | Treat artifacts as test builds until hard gate passes. |
| BLK-007 Appium QA instability | Medium | QA/DevOps | Use Flutter tests and cloud artifacts while smoke harness stabilizes. |
| BLK-008 Presence staleness | High | Engineering/Product | Fresh backend preflight before connect/call/request. |
| BLK-009 Offline request guardrails | Critical | Product/Security | Avoid release candidate offline requests until guardrails pass. |

## Rule

Blockers must never stop all work. They block unsafe release or unsafe promotion only.

Use [[Blocker Resolution Plan]] to identify:

- owner,
- resolution plan,
- workaround,
- parallel work,
- exit criteria.

