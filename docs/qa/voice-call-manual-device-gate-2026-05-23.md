# Voice Call Manual Device Gate - 2026-05-23

Gate status: BLOCKED

This run did not execute the manual matrix. The current Codex session cannot
see a physical Android device and cannot run `adb`.

## Local Discovery

```text
Git branch: dev
Code candidate at discovery time: 308c10a
flutter devices: Windows, Chrome, Edge only
adb devices -l: adb is not recognized on PATH
```

Existing local `final product` APKs are not accepted for this gate because they
are stale and include obsolete universal, ARM v7, and x86_64 APK outputs from
before the current artifact policy.

## Required Before Rerun

1. Install Android platform-tools or add `adb` to `PATH`.
2. Connect a physical Android device with USB debugging enabled.
3. Build or download Android and Windows artifacts from the same current commit.
4. Run the full matrix in `docs/qa/voice-call-manual-device-gate.md`.
5. Update this record with pass/fail evidence for every row.

## Matrix Result

| Row | Scenario | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Windows -> Android direct route | NOT RUN | Android device unavailable |
| 2 | Android -> Windows direct route | NOT RUN | Android device unavailable |
| 3 | Windows -> Android TURN relay | NOT RUN | Android device unavailable |
| 4 | Android -> Windows TURN relay | NOT RUN | Android device unavailable |
| 5 | Android mic permission denied | NOT RUN | Android device unavailable |
| 6 | Windows mic unavailable or blocked | NOT RUN | Android device unavailable |
| 7 | Caller hangup | NOT RUN | Android device unavailable |
| 8 | Callee hangup | NOT RUN | Android device unavailable |
| 9 | Network loss during ringing | NOT RUN | Android device unavailable |
| 10 | Network loss during active call | NOT RUN | Android device unavailable |
| 11 | Five repeated calls without app restart | NOT RUN | Android device unavailable |
| 12 | Chat send during active call | NOT RUN | Android device unavailable |
| 13 | File send blocked during active call | NOT RUN | Android device unavailable |
