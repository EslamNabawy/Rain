# Engineering Insights

Last updated: 2026-06-03

## Purpose

This note tracks recurring engineering patterns discovered across bugs, audits, releases, documentation phases, and implementation cycles.

Related: [[Lessons Learned]], [[Improvement Backlog]], [[Optimization Opportunities]], [[Risk Register]], [[Technical Debt Register]], [[Architecture Refactor Plan Index]].

## Recurring Patterns

| Pattern | Evidence | Impact | Improvement Direction |
| --- | --- | --- | --- |
| Symptom-first debugging | Voice/video fixes happened before enough failure taxonomy existed. | Repeated call failures remained hard to isolate. | Add diagnostics before declaring reliability fixes complete. |
| Backend-contract drift | Firebase permission denied and update/rules issues reached app testing. | APKs can appear broken because backend rules reject expected writes. | Add emulator/rules gates before release artifacts. |
| Stale state ambiguity | Presence, call locks, terminal room state, and UI state can disagree. | Users see online peers that are gone, false busy, or stuck connecting. | Create single-source resolvers/managers for each truth domain. |
| Release artifact trust ambiguity | Fast builds and hard release builds have different validation levels. | Testers waste time installing unproven artifacts. | Attach gate status and commit metadata to artifacts. |
| UI surface fragmentation | Call UI changed through several surface models. | Duplicate controls and unsafe overlays appear. | Use one presentation state and one call surface renderer. |
| Knowledge loss between sessions | Plans and fixes existed across chat, files, diagnostics, and docs. | Future work repeats old mistakes. | Keep [[Project Memory]], [[Lessons Learned]], and [[Recommended Next Actions]] current. |
| Manual governance drift | The vault defines mandatory reading, documentation updates, and lessons, but current validation does not enforce most of those rules. | Future sessions can appear compliant while skipping evidence, lessons, or canonical source updates. | Execute [[Engineering System Flaw Remediation Plan]] before building Phase 9 automation. |
| Ambiguous knowledge graph sources | The vault currently contains duplicate note titles such as `Risk Register`, `BLOCKERS`, `Backlog`, `Test Strategy`, `Database Architecture`, and `ADR-001`. | Plain Obsidian links can resolve to the wrong note, weakening the single-source-of-truth model. | Canonicalize source notes and add duplicate-title validation. |

## Converted Improvements

| Pattern | Process Improvement | Architecture Improvement | Testing Improvement | Automation Opportunity |
| --- | --- | --- | --- | --- |
| Symptom-first debugging | Require root-cause category before closing bugs. | Add [[CallDiagnosticsRecorder]]. | Add failure taxonomy tests. | Generate diagnostics summary checks in CI. |
| Backend-contract drift | Deploy/test rules before APK testing. | Centralize Firebase adapters and lease manager contracts. | Add RTDB emulator allow/deny tests. | Add rules gate to hard release workflow. |
| Stale state ambiguity | Record state source in every user-facing failure. | Add `PeerAvailabilityResolver` and [[CallLeaseManager]]. | Add stale-session and stale-lock tests. | Add state-conflict diagnostics report. |
| Release artifact trust ambiguity | Label artifacts by gate status. | Keep release metadata source centralized. | Gate publish on quality matrix. | Publish direct downloads with validation summary. |
| UI surface fragmentation | Freeze UI contract before polish. | Add single call surface model. | Add no-duplicate-surface widget tests. | Screenshot diff for call surfaces later. |
| Knowledge loss | Require lesson/memory update after tasks. | Keep documentation as part of architecture. | Validate wiki links and required notes. | Extend vault checker and CI docs gate. |
| Manual governance drift | Treat documentation completion as a validated deliverable. | Add source-of-truth contracts to project governance. | Validate evidence, stale docs, lessons, and task status. | Add Phase 9 preflight and completion scripts. |
| Ambiguous source notes | Canonicalize note ownership before adding more docs. | Add canonical source and view-note pattern. | Validate duplicate note titles. | Fail vault check when uncontrolled duplicate titles appear. |

## Engineering Principles Learned

- Do not fix WebRTC call reliability without first separating signaling, permission, ICE/TURN, media, and UI-state causes.
- Do not trust UI online state for actions; action paths need fresh backend truth.
- Do not publish artifacts unless the validation level is visible.
- Do not let blockers stop unrelated work; use [[Blocker Resolution Plan]].
- Do not add UI polish before state ownership is stable.
- Do not depend on chat history for project memory; write durable notes.

## Insight Review Rule

When the same pattern appears three times, create or update:

- [[Improvement Backlog]]
- [[Optimization Opportunities]]
- [[Risk Register]]
- [[Technical Debt Register]]
- [[Recommended Next Actions]]
