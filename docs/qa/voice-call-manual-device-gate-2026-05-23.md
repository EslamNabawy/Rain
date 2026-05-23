# Voice Call Manual Device Gate - 2026-05-23

Gate status: BLOCKED

The automated release gate built fresh demo release artifacts, but this run did
not execute the manual matrix. The current Codex session cannot see a physical
Android device and cannot run `adb`.

## Local Discovery

```text
Git branch: dev
Artifact build commit: a4cba12
flutter devices: Windows, Chrome, Edge only
adb devices -l: adb is not recognized on PATH
```

## Built Artifacts

```text
final product\Rain-Demo-Android-ARM-v7a-Build.apk
  Size: 28.83 MB
  SHA256: BC0C25360CB2C7F515DD36769BCC2753226E6DE2A102761CC5079F81AB0DB2E1
  Native ABI: armeabi-v7a only

final product\Rain-Demo-Android-ARM-v8-v9-Build.apk
  Size: 36.07 MB
  SHA256: EA207E21D0DAD016481D8F3DABEB2793FD602E3EA8B10F500D7AF1DDC191B19D
  Native ABI: arm64-v8a only

final product\Rain-Demo-Windows-x64-Build.zip
  Size: 25.68 MB
  SHA256: D33522D471A583B2F665403E6E971F250195EEBF311512857F167DC14B975577
```

The Android APKs contain the expected WebRTC and SQLite native runtimes:
`libjingle_peerconnection_so.so` and `libsqlite3.so`.

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
