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

### LESSON-20260603-005: Governance Rules Need Enforcement, Not Just Good Intentions

- Related task: [[Engineering System Flaw Remediation Plan]]
- Related system: [[Project Memory]], [[Knowledge Graph Index]], [[Improvement Backlog]], [[Project Metrics]]
- Related risk/debt: IMP-013, IMP-014, IMP-015, IMP-016, IMP-017
- What was learned: A strong repository operating manual is not enough if validation cannot detect skipped evidence, stale metrics, duplicate source notes, or missing lessons.
- What caused delays: The vault checker validates structure and links, but not the semantic truth of the operating model.
- What failed: Treating "single source of truth" as a written rule while allowing duplicate note titles and manual-only status updates.
- What succeeded: The flaw analysis identified a dependency order: canonicalize source notes first, then add schema, evidence, metrics, and automation gates.
- What should change: Execute [[Engineering System Flaw Remediation Plan]] before building Phase 9 automation.
- Pattern: Manual governance drift and ambiguous knowledge graph sources.
- Follow-up improvement: IMP-013 through IMP-017 in [[Improvement Backlog]].
- Owner: Engineering
- Status: Open

### LESSON-20260603-006: Evidence Must Correlate Across Devices Before Call Fixes

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md)
- Related system: [[Voice Calls]], [[Video Calls]], [[Presence Management]], [[Rules Strategy]], [[Diagnostics Sanitization]], [[Version And Updates]]
- Related risk/debt: R-001, R-003, R-006, R-014, TD-003, TD-004, TD-016, TD-018
- What was learned: The 2026-06-03 evidence shows several visible failures share deeper causes: split call terminal authority, Firebase `signaling.endCall` permission denial, presence freshness races, terminal inbox exposure before cleanup, Android diagnostics export failure, and update build-number inconsistency.
- What caused delays: Prior debugging often treated voice failure, video failure, false busy, stale presence, update prompts, and diagnostics export as separate issues.
- What failed: Release-build retries without a correlated root-cause tree and without emulator proof for Firebase end-call rules.
- What succeeded: Correlating the Windows diagnostic JSON with the Android screenshot proved the failures are primarily signaling/presence/rules/cleanup issues before proven ICE or TURN failure.
- What should change: No more call reliability patch should be accepted until it maps to the RCA evidence and adds validation for the exact root-cause cluster it claims to fix.
- Pattern: Multi-device symptoms from one fragmented lifecycle.
- Follow-up improvement: Prioritize Firebase end-call emulator reproduction, terminal-state reconciliation, presence snapshot unification, and Android diagnostics export repair in [[Recommended Next Actions]].
- Owner: Engineering
- Status: Open

### LESSON-20260603-007: Canonical Sources Must Be Locked Before Automation

- Related task: [[Engineering System Flaw Remediation Plan]] Phase 00 and Phase 01
- Related system: [[Knowledge Graph Index]], [[Project Home]], [[Project Metrics]]
- Related risk/debt: IMP-013, IMP-014
- What was learned: Automation should not be added on top of ambiguous note titles because it would make the wrong structure harder to unwind.
- What caused delays: Several canonical domains had duplicate note titles even though one note was only a view or index.
- What failed: The previous validator allowed duplicate titles because its note-title map overwrote earlier paths.
- What succeeded: Secondary notes were renamed into unique view/index names, the canonical source map was documented, and the validator now fails on duplicate titles.
- What should change: Future vault bootstrapping must check duplicate titles before link validation.
- Pattern: Ambiguous knowledge graph sources.
- Follow-up improvement: IMP-013 completed; IMP-014 remains in progress for deeper semantic validation.
- Owner: Engineering
- Status: Open

### LESSON-20260603-008: Expected Terminal Races Must Not Be Crash Diagnostics

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) first mitigation
- Related system: [[Voice Calls]], [[CallDiagnosticsRecorder]], [[Diagnostics And Logging]]
- Related risk/debt: TD-004, TD-016
- What was learned: The latest diagnostic export showed a benign late voice signaling state after terminal cleanup being stored as `lastCrash`, which hid the real call failure evidence.
- What caused delays: The runtime treated an expected cleanup race as a non-fatal error instead of a structured diagnostic event.
- What failed: Exported diagnostics became misleading because the "last Flutter error" pointed to `Ignored late voice signaling...` rather than the deeper signaling/media failure.
- What succeeded: A regression now locks `_recordLateVoiceFrame` to emit `late_frame_ignored` without calling the crash/error recorder.
- What should change: Expected races, cleanup echoes, and already-terminal state must be warning/info events unless they break user-visible behavior.
- Pattern: Observability pollution from expected async races.
- Follow-up improvement: Continue with Firebase end-call permission reproduction and richer call failure taxonomy.
- Owner: Engineering
- Status: Open

### LESSON-20260603-009: Terminal Source Of Truth Must Not Depend On Mirror Rows

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) second mitigation
- Related system: [[Voice Calls]], [[Firebase Architecture]], [[Rules Strategy]], [[CallTerminalReconciler]]
- Related risk/debt: TD-003, TD-009, TD-011
- What was learned: `voiceCallInboxes` is a callee-facing invite mirror, not the authoritative terminal call record. When `endCall` wrote terminal room state and terminal inbox state in one multi-path update, a cleaned inbox row could make Firebase deny the whole terminal write.
- What caused delays: The app treated room state and inbox mirror state as one atomic artifact even though the rules intentionally allow new inbox rows only for `ringing`.
- What failed: A valid `endCall` could become `[firebase_database/unknown] Permission denied` when the callee inbox had already been removed by cleanup or watcher repair.
- What succeeded: A Firebase emulator regression reproduced the exact denied write, then the adapter was changed to write terminal `voiceCalls/{callId}` state first and update the inbox mirror only if it still exists.
- What should change: Authoritative state writes must be isolated from optional mirror cleanup. Mirror rows can be best-effort, but they must never block terminal state, lock release, or user-visible cleanup.
- Pattern: Authoritative state coupled to optional mirror row.
- Follow-up improvement: Continue terminal reconciliation hardening for every voice/video cleanup path and add more emulator cases for already-terminal/missing-room/idempotent cleanup.
- Owner: Engineering
- Status: Open

### LESSON-20260603-010: Picker Return Values Are Not Always Filesystem Paths

- Related task: [ROOT_CAUSE_ANALYSIS.md](../../ROOT_CAUSE_ANALYSIS.md) Android diagnostics export mitigation
- Related system: [[Diagnostics And Logging]], [[Diagnostics Sanitization]]
- Related risk/debt: TD-010, TD-016
- What was learned: Android SAF picker outputs can look like `/document/1282` instead of a `content://...` URI. Treating that value as a `dart:io` file path caused `PathNotFoundException` and blocked diagnostic exports.
- What caused delays: The code already handled `content://` URIs but did not classify bare SAF handles as platform-managed outputs.
- What failed: Export fallback tried to open `/document/1282` directly even though the picker had already received the JSON bytes.
- What succeeded: A regression now locks `/document/...` handling so diagnostics export returns success without filesystem fallback.
- What should change: Any file picker/save picker integration must distinguish platform-managed handles from real filesystem paths before using `File`.
- Pattern: Platform handle mistaken for local path.
- Follow-up improvement: Extend file-transfer save/export flows with similar SAF-handle tests if they accept picker results.
- Owner: Engineering
- Status: Open

## Review Cadence

- Review lessons at the end of every completed task.
- Review recurring patterns weekly.
- Convert repeated patterns into items in [[Improvement Backlog]].
- Promote major process decisions into ADRs when they affect architecture or release policy.
