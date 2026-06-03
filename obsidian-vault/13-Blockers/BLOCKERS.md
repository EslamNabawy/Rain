# BLOCKERS

Last updated: 2026-06-03

## Active Blockers

### BLK-001: Call setup reliability is not production proven

- Status: [ ] Open
- Severity: Critical
- Related: [[Signaling Reliability Epic]], [[VoiceCallRuntime Refactor]], [[Call State Machine]]
- Impact: Voice/video cannot be trusted until PC-to-mobile, mobile-to-PC, Android-to-Android, and retry paths pass deterministic tests.
- Current workaround: Keep releases as test builds only.
- Exit criteria: Automated call-state tests pass and diagnostics distinguish permission, Firebase, ICE, TURN, and media failures.

### BLK-002: Firebase rules and app behavior must stay Spark-safe

- Status: [ ] Open
- Severity: High
- Related: [[Firebase Architecture]], [[Rules Strategy]], [[Emulator Coverage]]
- Impact: No Cloud Functions can be required for core flows while Firebase free tier remains mandatory.
- Current workaround: Use RTDB rules, client-side TTL cleanup, and emulator validation.
- Exit criteria: Emulator rules cover call rooms, locks, presence, requests, messages, file metadata, and update policy reads.

### BLK-003: Update prompts have reported version-comparison failures

- Status: [ ] Open
- Severity: Critical
- Related: [[Production Readiness]], [[Release Gates]], [[Version And Updates]]
- Impact: Users can remain on broken versions after rules or protocol changes.
- Current workaround: Manual reinstall and direct release download.
- Exit criteria: Old-version simulation widget/unit tests prove required and optional update prompts.

### BLK-004: Appium/local Android QA harness is not stable yet

- Status: [/] In Progress
- Severity: Medium
- Related: [[Emulator Test Matrix]], [[CI-CD Roadmap]]
- Impact: External black-box smoke automation cannot yet be treated as a release blocker.
- Current workaround: Flutter unit/widget tests and cloud build artifacts.
- Exit criteria: A minimal Appium smoke test is repeatable on `QA_Medium_API_36_1`.

Related: [[Project Home]], [[Risk Register]], [[Active Sprint]].
