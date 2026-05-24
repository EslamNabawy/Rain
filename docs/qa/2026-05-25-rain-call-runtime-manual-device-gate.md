# Rain Call Runtime Manual Device Gate - 2026-05-25

Gate status: BLOCKED

This Phase 13 attempt did not execute the manual matrix because the current
machine cannot see a physical Android device and `adb` is not available on
`PATH`. The gate must not be marked as passed until the exact same commit is
installed on the required Android and Windows devices and every scenario below
has evidence.

## Build And Validation Context

```text
Git branch: codex/rain-rebrand-implementation
Gate commit: 74d3710
Phase 12 validation: PASS
Local artifacts built in this attempt: none
Cloud build triggered in this attempt: no
```

Phase 12 passed before this gate:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

## Local Device Discovery

```text
flutter devices:
  Windows (desktop) - windows-x64
  Chrome (web)
  Edge (web)

adb devices -l:
  BLOCKED - adb is not recognized as a cmdlet, function, script file, or executable program.
```

## Required Before Rerun

1. Install Android platform-tools or add `adb` to `PATH`.
2. Connect at least two physical Android phones for the Android-to-Android rows.
3. Use Windows plus at least one physical Android phone for cross-platform rows.
4. Build or download Android v7a, Android v8/v9, and Windows artifacts from the
   same commit that is being tested.
5. Record SHA256 hashes for every installed artifact before running calls.
6. Keep both apps foregrounded unless the row is explicitly testing app close.
7. Export diagnostics for every failure before reinstalling or retrying.

## Matrix Result

| Row | Scenario | Required result | Result | Evidence |
| --- | --- | --- | --- | --- |
| 1 | Android phone A -> Android phone B voice | Call reaches active, audio both directions, clean hangup | NOT RUN | Android device unavailable |
| 2 | Android phone B -> Android phone A voice | Call reaches active, audio both directions, clean hangup | NOT RUN | Android device unavailable |
| 3 | Android phone A -> Android phone B video | Call reaches active, video and audio both directions, clean hangup | NOT RUN | Android device unavailable |
| 4 | Android phone B -> Android phone A video | Call reaches active, video and audio both directions, clean hangup | NOT RUN | Android device unavailable |
| 5 | Windows -> Android voice | First attempt reaches active, audio both directions | NOT RUN | Android device unavailable |
| 6 | Android -> Windows voice | First attempt reaches active, audio both directions | NOT RUN | Android device unavailable |
| 7 | Windows -> Android video | First attempt reaches active, Windows app does not crash | NOT RUN | Android device unavailable |
| 8 | Android -> Windows video | First attempt reaches active, Android does not keep stale running-call state | NOT RUN | Android device unavailable |
| 9 | Caller hangup both platforms | Peer exits call, chat remains usable, no stale busy state | NOT RUN | Android device unavailable |
| 10 | Callee hangup both platforms | Peer exits call, chat remains usable, no stale busy state | NOT RUN | Android device unavailable |
| 11 | App close during active call | Remote call state clears and media is disposed | NOT RUN | Android device unavailable |
| 12 | Disconnect then reconnect on Android | Connect button becomes usable again and peer reconnects | NOT RUN | Android device unavailable |
| 13 | Laptop camera controls | No rear-camera flip icon on single-camera laptop | NOT RUN | Requires app artifact/manual UI check |
| 14 | Multi-camera Android controls | Flip control appears only when supported | NOT RUN | Android device unavailable |
| 15 | Startup splash loading | Bottom navigation never appears during splash loading | NOT RUN | Requires installed artifact/manual startup check |

## Gate Decision

Do not proceed to the final release gate from this attempt. The automated gate is
green, but the manual device evidence is missing.
