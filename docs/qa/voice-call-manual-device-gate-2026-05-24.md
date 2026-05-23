# Voice Call Manual Device Gate - 2026-05-24

Gate status: BLOCKED

Phase 12 could not be passed in this run. The gate requires the same current
commit installed on a physical Android device and Windows, then real call
evidence for every manual matrix row. This machine currently has no Android
device visible to Flutter or adb.

## Local Discovery

```text
Tester: Codex
Date: 2026-05-24T01:37:32+03:00
Git branch: dev
Git commit: 2abcc2e
flutter devices: Windows, Chrome, Edge only
adb path: C:\Users\eslam\AppData\Local\Android\Sdk\platform-tools\adb.exe
adb devices -l: no devices attached
```

## Available Artifacts

These artifacts exist locally, but they were produced on 2026-05-23 and must be
treated as stale for this gate unless rebuilt from commit `2abcc2e`.

```text
final product\Rain-Demo-Android-ARM-v7a-Build.apk
  SHA256: BC0C25360CB2C7F515DD36769BCC2753226E6DE2A102761CC5079F81AB0DB2E1

final product\Rain-Demo-Android-ARM-v8-v9-Build.apk
  SHA256: EA207E21D0DAD016481D8F3DABEB2793FD602E3EA8B10F500D7AF1DDC191B19D

final product\Rain-Demo-Windows-x64-Build.zip
  SHA256: D33522D471A583B2F665403E6E971F250195EEBF311512857F167DC14B975577
```

## Blockers

1. No physical Android device is attached or authorized.
2. Flutter sees only Windows and web devices.
3. The existing Android and Windows artifacts are not proven to be built from
   current commit `2abcc2e`.

## Required Before Rerun

1. Connect a physical Android device with USB debugging enabled.
2. Confirm `adb devices -l` shows the device as `device`, not `unauthorized`.
3. Rebuild or download Android and Windows artifacts from the same current
   commit and the same release defines.
4. Install the Android APK and run the Windows portable build.
5. Complete the matrix in `docs/qa/voice-call-manual-device-gate.md`.

## Phase 12 Matrix Result

| Row | Scenario | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Music playing in another app, then Rain send/receive/call sounds | NOT RUN | Android device unavailable |
| 2 | Incoming call sound while music plays | NOT RUN | Android device unavailable |
| 3 | Outgoing call sound while music plays | NOT RUN | Android device unavailable |
| 4 | Android to Android voice call | NOT RUN | Android device unavailable |
| 5 | Android to Windows voice call | NOT RUN | Android device unavailable |
| 6 | Windows to Android voice call | NOT RUN | Android device unavailable |
| 7 | Minimize overlay, send chat, restore overlay | NOT RUN | Android device unavailable |
| 8 | Mute/unmute mic | NOT RUN | Android device unavailable |
| 9 | Deafen/undeafen remote audio | NOT RUN | Android device unavailable |
| 10 | Real sound-wave activity behavior | NOT RUN | Android device unavailable |
| 11 | Select default mic, restart app, confirm selection persists | NOT RUN | Android device unavailable |
| 12 | Missing/disconnected selected mic falls back to default | NOT RUN | Android device unavailable |
| 13 | Switch conversation during active call; overlay remains available | NOT RUN | Android device unavailable |
| 14 | Hangup from caller | NOT RUN | Android device unavailable |
| 15 | Hangup from callee | NOT RUN | Android device unavailable |
| 16 | Failed call followed by successful retry | NOT RUN | Android device unavailable |
| 17 | Windows default mic call | NOT RUN | Android counterpart unavailable |
| 18 | Windows external mic if available | NOT RUN | Android counterpart unavailable |
| 19 | Windows deafen/undeafen | NOT RUN | Android counterpart unavailable |
| 20 | Windows overlay minimize/restore | NOT RUN | Android counterpart unavailable |
| 21 | Windows repeat calls without app restart | NOT RUN | Android counterpart unavailable |

## Acceptance Status

```text
At least 3 successful Android-to-Android calls: NOT RUN
At least 3 successful Android-to-Windows calls: NOT RUN
At least 3 successful Windows-to-Android calls: NOT RUN
No stuck "peer busy" after hangup/failure: NOT RUN
No lost chat/file-transfer behavior outside active call blocking: NOT RUN
External music keeps playing while Rain SFX plays: NOT RUN
```

This gate remains a release blocker until rerun with real devices.
