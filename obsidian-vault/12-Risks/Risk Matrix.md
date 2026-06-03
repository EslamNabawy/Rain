# Risk Matrix

Last updated: 2026-06-03

## Purpose

This matrix defines how [[Risk Register]] maps impact and probability into severity.

Related: [[Risk Categories]], [[BLOCKERS]], [[Launch Readiness]], [[Production Readiness]], [[Debt Prioritization]].

## Impact Scale

| Impact | Meaning |
| --- | --- |
| Critical | Blocks public launch, creates security exposure, or makes a core feature unusable. |
| High | Blocks production readiness or causes severe user-facing failure. |
| Medium | Creates quality, support, performance, or maintainability risk. |
| Low | Narrow or cosmetic risk with limited operational impact. |

## Probability Scale

| Probability | Meaning |
| --- | --- |
| High | Already reported, frequently reproducible, or structurally likely. |
| Medium | Plausible in normal use, device variation, network variation, or release drift. |
| Low | Edge case or unlikely unless a specific condition occurs. |

## Severity Matrix

| Impact \ Probability | Low | Medium | High |
| --- | --- | --- | --- |
| Critical | High | Critical | Critical |
| High | Medium | High | Critical |
| Medium | Low | Medium | High |
| Low | Low | Low | Medium |

## Escalation

- Critical severity creates or updates a blocker in [[BLOCKERS]].
- High severity requires a roadmap task or accepted deferral.
- Medium severity requires a detection strategy.
- Low severity can be tracked as backlog or technical debt.

## Risk Acceptance

Accepted risks must include:

- owner,
- reason for acceptance,
- expiry or review date,
- fallback/workaround,
- affected release scope.

Record acceptance in [[Launch Readiness]] and link back to [[Risk Register]].

