# Continuous Learning Rules

Last updated: 2026-06-03

## Purpose

These are the rules that make the Rain vault self-improving after every implementation cycle.

Related: [[Lessons Learned]], [[Engineering Insights]], [[Improvement Backlog]], [[Optimization Opportunities]], [[Project Metrics]], [[Recommended Next Actions]], [[Continuous Improvement Log]].

## Task Completion Rule

After every completed task, answer:

1. What was learned?
2. What caused delays?
3. What failed?
4. What succeeded?
5. What should change?
6. Did this match a recurring pattern?
7. Does this require a process, architecture, testing, or automation improvement?

## Recurring Pattern Rule

If a problem appears twice, track it in [[Engineering Insights]].

If a problem appears three times, create or update:

- [[Improvement Backlog]]
- [[Optimization Opportunities]]
- [[Risk Register]]
- [[Technical Debt Register]]
- [[Recommended Next Actions]]

## Conversion Rules

| Pattern Type | Convert Into |
| --- | --- |
| Repeated debugging confusion | Testing improvement and diagnostics improvement. |
| Repeated state inconsistency | Architecture improvement and state ownership rule. |
| Repeated release failure | DevOps improvement and release gate change. |
| Repeated UI confusion | UX improvement and widget test. |
| Repeated performance complaint | Performance budget and measurable diagnostic. |
| Repeated knowledge loss | Documentation rule and vault checker requirement. |

## Update Rules

- Update [[Lessons Learned]] after implementation cycles.
- Update [[Engineering Insights]] when a pattern is confirmed.
- Update [[Improvement Backlog]] when an improvement is actionable.
- Update [[Optimization Opportunities]] when an improvement has measurable value.
- Update [[Project Metrics]] when scores, counts, gates, or validation change.
- Update [[Recommended Next Actions]] when priorities change.

## Validation Rule

No self-improvement note is complete until the vault checker passes.

