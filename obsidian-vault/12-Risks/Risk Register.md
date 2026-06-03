# Risk Register

Last updated: 2026-06-03

## Purpose

This register manages risks discovered through [[Original Audit]], [[Current Architecture]], [[Master Roadmap]], and [[Technical Debt Register]].

Risk is tracked separately from debt:

- Debt is a known structural weakness.
- Risk is the chance and impact of that weakness causing project, user, security, or operational failure.

Related: [[Risk Categories]], [[Risk Matrix]], [[BLOCKERS]], [[Blocker Resolution Plan]], [[Technical Debt Register]], [[Debt Prioritization]], [[Launch Readiness]], [[Production Readiness]].

## Risk Scoring Model

| Field | Values |
| --- | --- |
| Impact | Low, Medium, High, Critical |
| Probability | Low, Medium, High |
| Severity | Low, Medium, High, Critical |
| Status | Open, Watching, Mitigating, Mitigated, Accepted, Closed |

Severity rule:

- Critical: public launch blocker, security blocker, or core feature unusable.
- High: production-readiness blocker or likely severe user impact.
- Medium: meaningful quality, maintenance, or support risk.
- Low: cleanup or narrow edge-case risk.

## Risk Statistics

| Metric | Value |
| --- | --- |
| Total active risks | 22 |
| Critical risks | 10 |
| High risks | 9 |
| Medium risks | 3 |
| Low risks | 0 |
| Public-launch blockers | 8 |
| Risks linked to P0 tasks | 10 |
| Risks linked to technical debt | 20 |

## Category Distribution

| Category | Count | Highest Severity | Related Note |
| --- | --- | --- | --- |
| Technical | 4 | Critical | [[Risk Categories]] |
| Product | 3 | Critical | [[Risk Categories]] |
| Architecture | 4 | Critical | [[Architecture Debt]] |
| Scalability | 3 | High | [[Scalability Debt]] |
| Security | 3 | Critical | [[Security Debt]] |
| Operational | 3 | Critical | [[DevOps Debt]] |

## Critical Risk Summary

| Risk | Primary Blocker | Primary Roadmap Task | Primary Debt |
| --- | --- | --- | --- |
| R-001 PC-to-mobile calls fail or stick | BLK-001 | TASK-001, TASK-003, TASK-013 | TD-001, TD-004 |
| R-002 False busy from stale locks | BLK-002 | TASK-002 | TD-003 |
| R-004 Media capture order fails | BLK-001 | TASK-013 | TD-004, TD-016 |
| R-007 Oversized runtime creates regression risk | BLK-001 | TASK-001 | TD-001 |
| R-011 Update prompt unreliable | BLK-004 | TASK-012 | TD-018 |
| R-014 Rules allow malformed or deny valid writes | BLK-003 | TASK-005 | TD-009, TD-011 |
| R-018 Release workflow can publish unproven artifacts | BLK-006 | TASK-015 | TD-017 |
| R-020 Offline request guardrails fail silently or spend quota incorrectly | BLK-009 | TASK-023 | TD-020 |
| R-021 Logout/account reset restores stale identity | BLK-010 | [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md) | TD-021 |
| R-022 Startup shell/protected navigation renders before readiness | BLK-010 | [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md) | TD-022 |

## Active Risk Register

| ID | Category | Risk | Impact | Probability | Severity | Mitigation | Detection Strategy | Owner | Related Links | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| R-001 | Technical | PC-to-mobile voice/video setup can fail or remain stuck connecting. | Calling feature becomes unusable for a major platform direction. | High | Critical | Split runtime ownership, enforce state machine, validate media capture order. 2026-06-03 mitigation: failed setup diagnostics now include Firebase room status timelines and remote terminal-room failure diagnostics. Phase 08 added targeted regressions for failure messages, failed call surfaces, terminal write ordering, and already-terminal cleanup. | Runtime tests for PC/mobile directions, call timeline diagnostics, release smoke checks. | Engineering | [[VoiceCallRuntime Refactor]], [[Call State Machine]], [[CallMediaCoordinator]], TASK-001, TASK-003, TASK-013, TD-001, TD-004 | Open |
| R-002 | Technical | Stale Firebase call locks can report false busy. | Users cannot start calls after previous failures. | High | Critical | Implement matching-`callId` lease repair and retry once before busy. | Fake/emulator stale-lock tests, diagnostics with lock path and room status. | Engineering | [[Lease Management]], [[CallLeaseManager]], TASK-002, TD-003 | Open |
| R-003 | Technical | Presence can remain online after app close or stale sessions. | Calls/connects are offered to unavailable peers; offline request notification is blocked. | Medium | High | Use session-owned heartbeat, freshness thresholds, and stale-session rejection. 2026-06-03 mitigation: runtime now re-resolves backend `online + lastHeartbeat + state` before local seeding, direct Connect, connection-request routing, call start, chat Connect routing, and network auto-recovery. `presenceExpired` remains a terminal peer intent until successful explicit reconnect. Phase 08 added protocol contract coverage for session-owned presence and `onDisconnect` offline writes. | Presence expiry tests, app-close tests, diagnostics with heartbeat age/session id/state. | Engineering | [[Presence Management]], [[Presence And Direct Connect]], TASK-006, TD-002 | Mitigating |
| R-004 | Technical | Media capture, permissions, transceivers, or renderers can fail during call setup. | Calls fail after invite/answer and can leave room/locks active. | High | Critical | Move media setup into [[CallMediaCoordinator]] with cleanup-on-failure. | Permission-denied tests, disposed renderer/transceiver tests, media timeout diagnostics. | Engineering | [[CallMediaCoordinator]], [[Voice Calls]], [[Video Calls]], TASK-013, TD-004, TD-016 | Open |
| R-005 | Product | Call UI instability makes users think working calls are broken. | User trust drops; support reports mix UI and media failures. | Medium | High | Use one call surface model and safe-area contract. | Widget tests for fullscreen, minimized bar, PiP, ended, failed, and no duplicates. | Product/UI | [[Voice Calls]], [[Video Calls]], [[Frontend Architecture]], TASK-019, TD-005, TD-019 | Open |
| R-006 | Product | Update prompt behavior fails for old builds. | Old apps keep using incompatible rules/protocol and appear broken. | Medium | Critical | Harden manifest parsing, semver/build comparison, root gate, and settings check. 2026-06-03 mitigation: stale release policy is reported as `remotePolicyOutdated`, same-version minimum-build upgrades become required, and optional prompts render at root before login/home. Remaining operational dependency: deploy Remote Config after each release. | Unit/widget tests for old/current/newer, required/optional, invalid config. | Product/DevOps | [[Version And Updates]], [[Release Gates]], TASK-012, TD-018 | Mitigating |
| R-007 | Architecture | Oversized `VoiceCallRuntime` causes regressions when fixing call bugs. | Fixes in one call phase break another phase. | High | Critical | Extract call start, lease, media, terminal, and diagnostics coordinators. | Characterization tests around each coordinator boundary. | Engineering | [[VoiceCallRuntime Refactor]], [[Target Architecture]], TASK-001, TD-001 | Open |
| R-008 | Architecture | `RainRuntimeController` owns too many domains. | Hidden coupling affects chat, calls, files, presence, lifecycle, and request flows. | Medium | High | Split high-risk domains after call runtime is stabilized. | Provider/runtime contract tests, changed-file impact review. | Engineering | [[Current Architecture]], [[Refactoring Strategy]], TASK-001, TASK-020, TD-002 | Open |
| R-009 | Architecture | Call terminal state has multiple truths. | Remote side may not hang up, late frames can revive terminal calls, UI can stay failed. | High | Critical | Make terminal Firebase room state authoritative and explicit. | Voice/video terminal tests, late-frame ignore tests, diagnostics for terminal reconciliation. | Engineering | [[Call State Machine]], [[CallTerminalReconciler]], TASK-003, TD-004 | Open |
| R-010 | Architecture | Riverpod/provider boundaries can rebuild too broadly. | Scroll, pull-refresh, and call surfaces lag on slower devices. | Medium | Medium | Use selected state slices and consumer islands after pagination/surface cleanup. | Rebuild isolation widget tests and frame summary diagnostics. | Engineering/UI | [[Frontend Architecture]], [[Performance Debt]], TASK-020, TD-014 | Open |
| R-011 | Scalability | Large file transfers can overload memory or data-channel buffers. | App crashes, transfer fails, or peer connection degrades. | Medium | High | Persistent receive sink and data-channel high/low water marks. | Slow receiver tests, large transfer tests, bufferedAmount diagnostics. | Engineering | [[File Transfer]], [[Streaming Architecture]], [[Backpressure Strategy]], TASK-010, TASK-011, TD-008 | Open |
| R-012 | Scalability | Local database queries may not scale. | Large chats slow startup, chat open, unread updates, or transfer listing. | Medium | High | Add Drift indexes and migration tests. | Migration tests, query path review, pagination tests. | Engineering | [[Database Architecture]], [[Index Strategy]], [[Migration Plan]], TASK-008, TD-006 | Open |
| R-013 | Scalability | Conversation loading may be eager and memory-heavy. | Chat scrolling becomes slow and ARMv7 performance worsens. | Medium | High | Add bounded pagination and stable anchors. | Provider/widget pagination tests and low-power smoke checks. | Engineering/UI | [[Pagination Strategy]], [[Peer Chat]], TASK-009, TD-007 | Open |
| R-014 | Security | Firebase rules may allow malformed writes or deny valid writes. | Unauthorized signaling, corrupt rooms, permission-denied failures, or lockouts. | Medium | Critical | Expand emulator allow/deny coverage for all critical RTDB branches. | Firebase rules emulator matrix, permission-denied diagnostics. | Security/Engineering | [[Rules Strategy]], [[Emulator Coverage]], TASK-005, TD-009, TD-011 | Open |
| R-015 | Security | Diagnostics can expose sensitive metadata or payloads. | User-shared logs leak private data or signaling secrets. | Medium | High | Central recursive sanitizer and denylist for sensitive fields. | Sanitizer unit tests and export redaction checks. | Security | [[Diagnostics Sanitization]], [[Privacy Review]], TASK-014, TD-010 | Open |
| R-016 | Security | Offline request notifications can be abused or spend quota incorrectly. | Firebase usage grows and users lose request credits for normal online connect. | Medium | High | Enforce offline-only confirmation path in app and RTDB rules. | Runtime, adapter, rules, and widget tests for online/offline/unknown/blocked states. | Security/Product | [[Connection Request Notifications]], [[Presence Management]], TASK-023, TD-012, TD-020 | Open |
| R-017 | Operational | Firebase Spark/free-tier constraints limit backend authority and cleanup. | Client/rules must carry more risk; quota can degrade reliability. | High | High | Use RTDB-only guardrails, TTL fields, opportunistic cleanup, and counters. | Firebase cost counters, rules tests, diagnostics operation summaries. | Engineering/Ops | [[Firebase Architecture]], [[Rules Strategy]], TASK-017, TD-012 | Open |
| R-018 | Operational | Release workflow can publish artifacts without enough proof. | Broken APK/EXE reaches testers and wastes install cycles. | Medium | Critical | Enforce hard release gates and artifact metadata. | Workflow dependency checks, release evidence, vault validation. | DevOps | [[Release Gates]], [[CI-CD Roadmap]], TASK-015, TD-017 | Open |
| R-019 | Operational | Local Android/Appium smoke workflow is not stable enough as a release blocker. | Device regressions escape unit/widget tests. | Medium | High | Add stable locators, repeatable AVD smoke, and artifacts. | Appium smoke logs, integration test result, emulator artifacts. | QA/DevOps | [[Emulator Test Matrix]], [[Test Strategy]], TASK-018, TD-015 | Open |
| R-020 | Product | Blocked actions may not show clear user-facing messages. | Users cannot understand connect/call/request failures. | Medium | Critical | Fixed message matrix for every guardrail denial and failed fallback. | Widget tests for blocked actions and runtime diagnostics. | Product/UI | [[Connection Request Notifications]], `RuntimeInteractionGuard`, TASK-023, TD-020 | Open |
| R-021 | Architecture | Logout/account reset can restore stale identity or recreate deleted backend data. | Users cannot trust logout, account deletion, or clean reset. | High | Critical | Introduce an auth session coordinator, validate backend identity before runtime start, and clear local session before/beside backend cleanup. | Tests for stale local identity, deleted backend account, failed Firebase sign-out, and session-expired reset. | Engineering | [[Authentication]], [AUTHENTICATION_AUDIT.md](../../AUTHENTICATION_AUDIT.md), [ACCOUNT_LIFECYCLE_ANALYSIS.md](../../ACCOUNT_LIFECYCLE_ANALYSIS.md), TD-021 | Open |
| R-022 | Product | Startup/loading can render shell or protected routes before session/runtime readiness. | Users see partial UI, navigation, or unknown profile state during startup. | High | Critical | Move splash/auth/runtime readiness to a global gate before protected router/shell creation. | Widget tests for `/`, `/settings`, `/search`, and friend routes during identity/runtime loading. | Product/UI | [[Authentication]], [SPLASH_SCREEN_INVESTIGATION.md](../../SPLASH_SCREEN_INVESTIGATION.md), [NAVIGATION_INITIALIZATION_AUDIT.md](../../NAVIGATION_INITIALIZATION_AUDIT.md), TD-022 | Open |

## Detection Strategy By Category

| Category | Detection Strategy |
| --- | --- |
| Technical | Runtime tests, diagnostics timeline, fake/emulator adapter tests, call setup taxonomy. |
| Product | Widget tests, user-message matrix, update prompt simulations, UX smoke flows. |
| Architecture | Contract tests, dependency review, changed-file impact review, architecture note updates. |
| Scalability | Migration tests, pagination tests, large transfer tests, low-power performance summaries. |
| Security | Emulator rules tests, sanitizer tests, authorization/shape deny tests, operation budget counters. |
| Operational | CI workflow gates, artifact metadata checks, vault validation, Appium/local smoke evidence. |

## Escalation Rules

- Any Critical security risk blocks public distribution.
- Any Critical call reliability risk blocks public launch.
- Any Critical update/version risk blocks backend rule changes that can affect old clients.
- Any Critical release-gate risk blocks cloud release promotion.
- Blockers must never stop progress; use [[Blocker Resolution Plan]] to route parallel work.

## Register Definition Of Done

- Every risk has impact, probability, severity, mitigation, detection strategy, owner, and links to roadmap/debt.
- Every Critical risk maps to at least one blocker in [[BLOCKERS]] or explicit acceptance in [[Launch Readiness]].
- Mitigated risks update [[Technical Debt Register]], [[Audit Resolution Tracker]], and [[Project Memory]] when durable facts change.
