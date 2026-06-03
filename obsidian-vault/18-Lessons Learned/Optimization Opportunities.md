# Optimization Opportunities

Last updated: 2026-06-03

## Purpose

This note identifies opportunities to improve performance, reliability, workflow speed, documentation quality, and testing leverage.

Related: [[Improvement Backlog]], [[Project Metrics]], [[Recommended Next Actions]], [[Performance Debt]], [[DevOps Debt]], [[Testing Debt]].

## Opportunities

| ID | Area | Opportunity | Expected Value | Dependencies | Recommended Action |
| --- | --- | --- | --- | --- | --- |
| OPT-001 | Diagnostics | Generate a call setup timeline summary for every failed call. | Faster call root-cause analysis. | [[CallDiagnosticsRecorder]], TASK-004 | Implement before more call reliability claims. |
| OPT-002 | Firebase | Add a pre-release RTDB rules emulator matrix. | Fewer permission-denied device regressions. | [[Rules Strategy]], TASK-005 | Add to hard release gate. |
| OPT-003 | Release | Split artifact workflows into fast-test and hard-gated releases with visible labels. | Less tester fatigue. | [[Release Gates]], TASK-015, TASK-016 | Make gate status visible in release notes. |
| OPT-004 | UI Performance | Add low-power static visual mode verification. | Better ARMv7 usability. | [[Performance Debt]], TASK-021 | Add tests around reduced animation/effects. |
| OPT-005 | Database | Add paginated message timeline controller. | Faster chat with large histories. | [[Index Strategy]], [[Pagination Strategy]] | Execute [[Message Loading Refactor Plan]]. |
| OPT-006 | File Transfer | Use streaming sinks and backpressure gates. | Safer large file transfers. | [[Streaming Architecture]], [[Backpressure Strategy]] | Execute [[File Transfer Runtime Refactor Plan]]. |
| OPT-007 | Knowledge | Require lesson capture and recommended next action updates after completed tasks. | Less repeated context recovery. | [[Continuous Learning Rules]] | Add to Definition of Done. |
| OPT-008 | QA | Stabilize a minimal Appium smoke test as optional evidence before making it a hard gate. | Better Android confidence without blocking too early. | [[Emulator Test Matrix]], TASK-018 | Keep non-blocking until repeatable. |

## Opportunity Scoring

Score opportunities by:

- repeated failure reduction,
- release confidence,
- user impact,
- cost to implement,
- automation potential.

Top current opportunities: OPT-001, OPT-002, OPT-003, OPT-007.

