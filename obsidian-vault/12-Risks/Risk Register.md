# Risk Register

Last updated: 2026-06-03

## Purpose

This register tracks risks that could block [[Production Readiness]], increase Firebase cost, or create unsafe user behavior.

## Active Risks

| ID | Risk | Severity | Probability | Impact | Mitigation | Owner | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R-001 | PC-to-mobile voice/video call setup can fail or become stuck. | Critical | High | Calling feature unusable for major platform path. | Split runtime through [[CallStartCoordinator]], [[CallLeaseManager]], [[CallMediaCoordinator]], and [[CallTerminalReconciler]]. | Engineering | [ ] Open |
| R-002 | Stale Firebase locks can report false busy. | Critical | High | Users cannot start calls after previous failures. | Lock repair protocol in [[Lease Management]] and emulator tests in [[Emulator Coverage]]. | Engineering | [ ] Open |
| R-003 | Firebase Spark/free tier limits constrain server-side cleanup and enforcement. | High | High | Rules and client cleanup must carry more responsibility. | Use [[Rules Strategy]], TTL fields, opportunistic cleanup, and cost guardrails. | Engineering | [ ] Open |
| R-004 | Old app versions can become incompatible with rules but not show an update prompt. | Critical | Medium | Users install broken versions and cannot recover. | Harden version manifest checks in [[Release Gates]] and [[Production Readiness]]. | Engineering | [ ] Open |
| R-005 | Security rules may allow unauthorized or malformed signaling writes. | Critical | Medium | Hijacked sessions, corrupt rooms, or data exposure. | Expand [[Rules Strategy]] and [[Security Roadmap]]. | Security | [ ] Open |
| R-006 | Large file transfers can overload memory or data-channel buffers. | High | Medium | App crash or transfer failure. | Implement [[Backpressure Strategy]] and persistent receive sinks. | Engineering | [ ] Open |
| R-007 | Diagnostics may expose sensitive metadata if sanitizer rules regress. | High | Medium | Privacy breach through exported logs. | Maintain denylist in [[Diagnostics Sanitization]] and tests in [[Test Strategy]]. | Security | [ ] Open |
| R-008 | Release workflow can publish artifacts without enough app-level tests. | High | Medium | Broken APK/EXE reaches testers. | Enforce [[Release Gates]] and [[CI-CD Roadmap]]. | DevOps | [ ] Open |
| R-009 | Presence state can remain online after app close. | High | Medium | Calls/connects are offered to unavailable peers. | Harden [[Presence Management]] with session-owned heartbeats and onDisconnect. | Engineering | [ ] Open |
| R-010 | UI changes can create duplicate call controls or unsafe overlay placement. | Medium | Medium | Confusing or broken call UX. | Use target call-suite contract in [[Target Architecture]] and widget gates in [[Coverage Dashboard]]. | Product/UI | [ ] Open |

## Escalation Rules

- Any Critical risk keeps [[Launch Readiness]] below beta.
- Any security Critical risk blocks public distribution.
- Any release-gate Critical risk blocks [[Release Gates]] style workflows.

Related: [[Technical Debt Register]], [[BLOCKERS]], [[Master Roadmap]].
