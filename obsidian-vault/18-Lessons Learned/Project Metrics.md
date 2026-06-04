# Project Metrics

Last updated: 2026-06-04

## Purpose

This note tracks project health metrics used to guide [[Recommended Next Actions]], [[Improvement Backlog]], and release readiness.

Related: [[Project Home]], [[Production Readiness]], [[Launch Readiness]], [[Risk Register]], [[Technical Debt Register]], [[Coverage Dashboard]].

## Baseline Scores

| Metric | Current | Target Before Public Release | Source |
| --- | --- | --- | --- |
| Completion estimate | 62% | 90%+ | [[Project Home]] |
| Production readiness | 48/100 | 90/100 | [[Production Readiness]] |
| Technical debt risk | 72/100 | 30/100 or lower | [[Technical Debt Register]] |
| Security score | 66/100 | 90/100 | [[Project Home]] |
| Scalability score | 45/100 | 85/100 | [[Project Home]] |
| Maintainability score | 50/100 | 85/100 | [[Project Home]] |
| Test coverage score | 72/100 | 90/100 | [[Project Home]] |

## Operating Metrics

| Metric | Current State | Target | Notes |
| --- | --- | --- | --- |
| Open Critical risks | 8 | 0 before public launch | See [[Risk Register]]. |
| Open blockers | 9 | 0 Critical before public launch | See [[BLOCKERS]]. |
| P0 debt items | 7 | 0 before public launch | See [[Debt Prioritization]]. |
| Required vault files validation | Passing | Always passing | Enforced by vault checker. |
| Markdown files in vault | 195 | Healthy, no broken links | Counted during 2026-06-04 vault validation. |
| Branch ahead of origin/dev | 1 local commit plus dirty worktree observed 2026-06-04 | Push when user requests | Current GitHub release-gate run validated pushed `origin/dev`, not local dirty changes. |
| Latest cloud hard release gate | Passed for `origin/dev` `d58b7b5` | Pass on release candidate SHA | `Build Rain Apps` run 26931788461 passed hard gate, Android/Windows artifacts, and `rain-test-107-1` publication. |
| Duplicate note titles | 0 uncontrolled duplicates | 0 uncontrolled duplicates | Duplicate-title validation now fails the vault check. See [[Engineering System Flaw Remediation Plan]]. |
| Governance enforcement depth | Required files, links, inbound/outbound links, and duplicate titles | Semantic governance validation | Stale metrics, evidence links, and phase consistency checks are still pending. |

## Learning Metrics

| Metric | Current | Target |
| --- | --- | --- |
| Lessons recorded | 15 | Add one per completed implementation cycle when relevant. |
| Improvement backlog items | 17 | Review weekly. |
| Optimization opportunities | 8 | Promote high-value items into tasks. |
| ADR count | 8 | Add when decisions affect architecture/release policy. |

## Update Rule

Update this note when:

- risk/debt/blocker counts change,
- release readiness score changes,
- vault validation count changes meaningfully,
- a new phase completes,
- a recurring pattern creates a new improvement item,
- a hard release gate passes or fails for a new reason.
