# Technical Debt

Last updated: 2026-06-03

## Purpose

This architecture note summarizes debt that affects system shape. The detailed management system lives in [[Technical Debt Register]].

Related: [[Debt Categories]], [[Debt Prioritization]], [[Architecture Debt]], [[Scalability Debt]], [[Security Debt]], [[Performance Debt]], [[Testing Debt]], [[DevOps Debt]], [[UX Debt]].

## Current Debt Score

- Current debt risk score: 72/100.
- Target before public release: 30/100 or lower.
- P0 debt items: 7.
- P1 debt items: 10.
- P2 debt items: 3.

## Critical Architecture Debt

- TD-001: `VoiceCallRuntime` is oversized and must be split through [[VoiceCallRuntime Refactor]].
- TD-003: Call lease and terminal state ownership is distributed across Firebase, runtime, and session paths.
- TD-004: Call phases need one explicit [[Call State Machine]].
- TD-005: Call UI surfaces need one rendering contract.

## Systemic Debt Themes

- Runtime ownership is too concentrated.
- Firebase signaling rules and leases need stronger proof.
- Local data and file transfers need bounded growth behavior.
- Diagnostics need to explain failures without exposing private payloads.
- Release workflows need hard gate parity.
- UI and provider boundaries need performance validation.

## Execution Links

- Register: [[Technical Debt Register]]
- Prioritization: [[Debt Prioritization]]
- Roadmap: [[Master Roadmap]]
- Critical path: [[Critical Path]]
- Launch blockers: [[Launch Blockers]]
- High-risk work: [[High-Risk Work]]
