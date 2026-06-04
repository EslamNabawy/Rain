# Assumption Register

Last updated: 2026-06-04

## Purpose

Track assumptions that Rain behavior, tests, release gates, and scenario analysis depend on.

Scenario-intelligence agents must read this note before testing or risk analysis, then generate scenarios that violate assumptions.

Related: [[Risk Register]], [[Risk Matrix]], [[Failure Graph]], [[System Model]], [[State Graph]], [[Business Rule Graph]].

## Status Values

- Active: assumption currently affects behavior or testing.
- Mitigated: code/tests reduce the assumption risk.
- Accepted: owner explicitly accepts the residual risk.
- Retired: assumption no longer applies.

## Assumptions

| ID | Assumption | Affected Domains | Violation Scenario | Expected Handling | Status |
| --- | --- | --- | --- | --- | --- |
| ASSUMP-001 | User has stable internet during auth, signaling, update, and diagnostics operations. | [[Authentication]], [[Signaling Architecture]], [[Version And Updates]], [[Diagnostics And Logging]] | Network drops after Auth succeeds but before RTDB identity write or call room update. | Fail closed, keep local state consistent, record sanitized diagnostics. | Active |
| ASSUMP-002 | Firebase RTDB writes succeed once authorized. | [[Firebase Architecture]], [[Rules Strategy]] | Rules deny a mirror cleanup write or backend write fails mid-flow. | Authoritative state must not depend on optional mirror writes; partial destructive flows clear local session. | Mitigated |
| ASSUMP-003 | Presence updates arrive quickly enough for user decisions. | [[Presence Management]], [[Presence And Direct Connect]] | Peer closes app but stale `online: true` remains. | Freshness resolver treats stale heartbeat/state as offline before connect/call/request. | Mitigated |
| ASSUMP-004 | Remote Config is available at startup. | [[Version And Updates]], [[Release Gates]] | Remote Config cannot be fetched or deployed policy is stale. | Show unavailable or `remotePolicyOutdated`, never report stale policy as current. | Mitigated |
| ASSUMP-005 | Single active call per user is enforceable through client-side RTDB locks. | [[Voice Calls]], [[Lease Management]] | Lock is stale, corrupt, missing room, terminal room, or belongs to another live call. | Inspect/repair only safe locks; live newer locks remain busy. | Active |
| ASSUMP-006 | Device clocks have small enough skew for room timestamps and presence freshness. | [[Presence Management]], [[Call State Machine]] | Caller/callee clocks differ or local clock moves behind room creation. | Normalize terminal timestamps and use freshness windows defensively. | Mitigated |
| ASSUMP-007 | Firebase Auth current user matches the requested Rain username. | [[Authentication]] | Surviving Auth user remains after backend tombstone or uid mismatch. | Login/restoration require backend uid proof; sign out on missing or wrong owner. | Mitigated |
| ASSUMP-008 | Android picker return values are usable filesystem paths. | [[Diagnostics And Logging]], [[File Transfer]] | Picker returns `content://` or `/document/...` handle. | Treat as platform-managed handle and create/report a real fallback file when needed. | Mitigated |
| ASSUMP-009 | WebRTC media setup failure source is distinguishable from signaling failure. | [[Voice Calls]], [[Video Calls]], [[CallDiagnosticsRecorder]] | Firebase write fails while media negotiation is in progress. | Classify signaling/terminal failures before reporting media failure. | Active |
| ASSUMP-010 | Offline connection request quota applies only to offline notification requests. | [[Connection Request Notifications]], [[Presence Management]] | Stale presence routes online direct connect attempt into offline quota. | Use fresh presence resolver and require explicit offline-notification confirmation. | Active |
| ASSUMP-011 | Diagnostics sanitization keeps useful failure evidence without private payloads. | [[Diagnostics And Logging]], [[Diagnostics Sanitization]] | New diagnostic field stores raw SDP, ICE candidate, password, message text, or file bytes. | Recursive sanitizer and tests must redact sensitive values. | Active |
| ASSUMP-012 | Local app tests run with correct package-native assets. | [[Test Strategy]] | Root-level app test invocation cannot resolve sqlite native assets on Windows. | Use `scripts/run_rain_app_test.ps1` or run from `apps/rain`. | Mitigated |

## Scenario Cycle

Every testing cycle:

1. Select assumptions relevant to the target feature.
2. Generate scenarios that violate each assumption.
3. Trace downstream effects through [[Failure Graph]].
4. Check whether existing tests cover the violation.
5. Record uncovered high-impact failures in [[Risk Register]], [[Technical Debt Register]], [[BLOCKERS]], or [[Recommended Next Actions]].

## Register Maintenance

- Add assumptions when a test, fix, or release gate relies on environment behavior.
- Move assumptions to Mitigated only when validation evidence exists.
- Do not delete retired assumptions without preserving the lesson or risk history.
