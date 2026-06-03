# Lessons Learned

Last updated: 2026-06-03

## Purpose

This note is the operating log for learning after every completed task. It turns completed work, failures, delays, and regressions into durable process, architecture, testing, and automation improvements.

Related: [[Lessons Learned Index]], [[Engineering Insights]], [[Continuous Learning Rules]], [[Improvement Backlog]], [[Project Metrics]], [[Recommended Next Actions]], [[Project Memory]].

## Continuous Learning Rule

After every completed task, record:

- What was learned.
- What caused delays.
- What failed.
- What succeeded.
- What should change.
- Which recurring pattern this confirms or disproves.
- Which improvement item should be created or updated.

No task is fully complete until the lesson check is done or explicitly marked "no new lesson."

## Lesson Entry Template

```markdown
## LESSON-YYYYMMDD-###

- Date:
- Related task:
- Related system:
- Related risk/debt:
- What was learned:
- What caused delays:
- What failed:
- What succeeded:
- What should change:
- Pattern:
- Follow-up improvement:
- Owner:
- Status:
```

## Initial Lessons

### LESSON-20260603-001: Debugging Without Failure Taxonomy Causes Repeated Call Fix Attempts

- Related task: TASK-004, TASK-001, TASK-013
- Related system: [[Voice Calls]], [[Video Calls]], [[CallDiagnosticsRecorder]]
- Related risk/debt: R-001, R-004, TD-016
- What was learned: Generic "call failed" states are not enough to fix WebRTC failures reliably.
- What caused delays: Firebase, media permission, ICE/TURN, renderer, and terminal-state failures were often collapsed into similar UI messages.
- What failed: Repeated fixes that did not first isolate the failure source.
- What succeeded: Moving toward diagnostics taxonomy and call setup timeline planning.
- What should change: Require failure classification before call reliability fixes are declared complete.
- Pattern: Symptom-first debugging.
- Follow-up improvement: IMP-001 in [[Improvement Backlog]].
- Owner: Engineering
- Status: Open

### LESSON-20260603-002: Firebase Rules Must Be Tested Before APK Testing

- Related task: TASK-005, TASK-018
- Related system: [[Rules Strategy]], [[Emulator Coverage]], [[Firebase Architecture]]
- Related risk/debt: R-014, TD-009, TD-011
- What was learned: Permission-denied failures can make new APKs look broken even when app code is not the only cause.
- What caused delays: Rules/app payload drift reached device testing.
- What failed: Relying on manual Firebase rule confidence.
- What succeeded: Planning emulator allow/deny coverage and rule gates.
- What should change: Rules tests must run before release artifacts are treated as useful device builds.
- Pattern: Backend-contract drift.
- Follow-up improvement: IMP-002 in [[Improvement Backlog]].
- Owner: Security/Engineering
- Status: Open

### LESSON-20260603-003: Release Speed Without Gate Clarity Creates Tester Fatigue

- Related task: TASK-015, TASK-016
- Related system: [[Release Gates]], [[CI-CD Roadmap]]
- Related risk/debt: R-018, TD-017
- What was learned: Fast artifacts are useful only when their validation level is obvious.
- What caused delays: Testers installed many builds without knowing whether hard gates had passed.
- What failed: Treating all release artifacts as equally trustworthy.
- What succeeded: Separating fast test artifacts from hard release gates in the roadmap.
- What should change: Every artifact must state commit, channel, version, and gate status.
- Pattern: Artifact trust ambiguity.
- Follow-up improvement: IMP-006 in [[Improvement Backlog]].
- Owner: DevOps
- Status: Open

### LESSON-20260603-004: Documentation Must Be Required, Not Optional

- Related task: TASK-022
- Related system: [[Project Memory]], [[Knowledge Graph Index]], [[Technical Debt Register]], [[Risk Register]]
- Related risk/debt: TD-020
- What was learned: Future AI sessions need one durable source of project truth to avoid rediscovery.
- What caused delays: Context split across chat history, source, old docs, and generated plans.
- What failed: Relying on memory outside the repo.
- What succeeded: Obsidian vault validation and required-file checks.
- What should change: Every implementation cycle must update affected vault notes.
- Pattern: Knowledge loss between sessions.
- Follow-up improvement: IMP-010 in [[Improvement Backlog]].
- Owner: Engineering
- Status: Open

## Review Cadence

- Review lessons at the end of every completed task.
- Review recurring patterns weekly.
- Convert repeated patterns into items in [[Improvement Backlog]].
- Promote major process decisions into ADRs when they affect architecture or release policy.

