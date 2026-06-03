# Technical Debt Register

Last updated: 2026-06-03

## Purpose

This register turns audit findings from [[Original Audit]] into owned debt items connected to [[Master Roadmap]], [[Epic Index]], and [[Audit Resolution Tracker]].

## Debt Items

| ID | Debt | Severity | Source | Resolution Path | Status |
| --- | --- | --- | --- | --- | --- |
| TD-001 | Oversized voice/video runtime mixes presence, leases, media, diagnostics, and UI state mutation. | Critical | [[Original Audit]] | [[VoiceCallRuntime Refactor]], [[Architecture Stabilization Epic]] | [ ] Open |
| TD-002 | Call lease and terminal state logic is not isolated enough to prove no false busy or stale call state. | Critical | [[Original Audit]] | [[CallLeaseManager]], [[CallTerminalReconciler]] | [ ] Open |
| TD-003 | Presence freshness and session ownership are shared across UI, connect, call, and request flows without a single canonical adapter contract. | High | [[Original Audit]] | [[Presence Management]], [[Signaling Reliability Epic]] | [ ] Open |
| TD-004 | Firebase RTDB rules and emulator coverage lag behind app behavior. | Critical | [[Original Audit]] | [[Rules Strategy]], [[Emulator Coverage]] | [ ] Open |
| TD-005 | Call diagnostics have improved but still need one taxonomy that can explain permission, Firebase, ICE, TURN, and media failures separately. | High | [[Original Audit]] | [[CallDiagnosticsRecorder]], [[Diagnostics Sanitization]] | [ ] Open |
| TD-006 | File transfer uses WebRTC data channels but needs stricter persistent streaming and backpressure proof. | High | [[Original Audit]] | [[Streaming Architecture]], [[Backpressure Strategy]] | [ ] Open |
| TD-007 | Local database query paths need index and pagination validation before large conversation growth. | High | [[Original Audit]] | [[Index Strategy]], [[Pagination Strategy]] | [ ] Open |
| TD-008 | CI/CD has several workflows with overlapping responsibility and inconsistent gate strictness. | High | [[Original Audit]] | [[CI-CD Roadmap]], [[Release Gates]] | [ ] Open |
| TD-009 | Version/update behavior has user-reported comparison and prompt failures. | Critical | [[Original Audit]] | [[Production Readiness]], [[Release Gates]] | [ ] Open |
| TD-010 | UI call surfaces have churned through multiple implementations; the target call-suite contract needs to be the only source. | High | [[Original Audit]] | [[Target Architecture]], [[Voice Calls]], [[Video Calls]] | [ ] Open |

## Scoring

- Current debt risk score: 72/100.
- Target before production: 30/100 or lower.
- Critical debt must be closed before [[Launch Readiness]] can move past limited testing.

Related: [[Risk Register]], [[Backlog]], [[Critical Path]].
