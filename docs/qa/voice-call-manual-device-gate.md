# Voice Call Manual Device Gate

This gate is a release blocker for voice calling. Automated tests, emulator
checks, and local desktop-only checks do not pass it. Mark the gate `PASS` only
after the exact same commit is installed on one physical Android device and one
Windows machine and every matrix row below has evidence.

## Required Evidence

Record these before starting:

```text
Gate status: BLOCKED | PASS | FAIL
Tester:
Date:
Git commit:
Android artifact:
Android artifact SHA256:
Windows artifact:
Windows artifact SHA256:
Android device model and Android version:
Windows version:
ICE config used for direct route:
ICE config used for TURN relay:
Rain accounts:
```

Use current voice-call artifacts only:

- Android: `Rain-Demo-Android-ARM-v8-v9-Build.apk`
- Windows: `Rain-Demo-Windows-x64-Build`

Do not use stale universal, x86_64, or ARM v7 APKs for this gate unless the
release plan explicitly adds those artifacts again.

## Setup

1. Build or download Android and Windows artifacts from the same Git commit.
2. Confirm hashes:

```powershell
Get-FileHash .\artifacts\Rain-Demo-Android-ARM-v8-v9-Build.apk -Algorithm SHA256
Get-FileHash .\artifacts\Rain-Demo-Windows-x64-Build\rain.exe -Algorithm SHA256
```

3. Confirm device visibility:

```powershell
flutter devices
adb devices -l
```

4. Install Android:

```powershell
adb install -r .\artifacts\Rain-Demo-Android-ARM-v8-v9-Build.apk
```

5. Start Windows from the portable artifact:

```powershell
.\artifacts\Rain-Demo-Windows-x64-Build\rain.exe
```

6. Sign in two accepted friend accounts. Keep both apps foregrounded for v1.
7. For direct route checks, use normal ICE config and verify the link banner
   reports `Direct`.
8. For TURN relay checks, use an ICE config containing only TURN/TURNS servers
   and verify the link banner reports `Relay`.

## Matrix

Every row must include result, route shown in UI, caller device, callee device,
failure text if any, and diagnostics reference.

| Row | Scenario | Required result | Evidence |
| --- | --- | --- | --- |
| 1 | Windows -> Android direct route | Remote voice audible both directions | |
| 2 | Android -> Windows direct route | Remote voice audible both directions | |
| 3 | Windows -> Android TURN relay | Remote voice audible both directions | |
| 4 | Android -> Windows TURN relay | Remote voice audible both directions | |
| 5 | Android mic permission denied | Typed microphone-required failure, no invite accepted | |
| 6 | Windows mic unavailable or blocked | Typed microphone-required failure, no active call | |
| 7 | Caller hangup | Peer exits call, chat remains connected | |
| 8 | Callee hangup | Peer exits call, chat remains connected | |
| 9 | Network loss during ringing | Ringing ends cleanly, no stale busy state | |
| 10 | Network loss during active call | Call ends cleanly, chat reconnects or reports network state | |
| 11 | Five repeated calls without app restart | Every call reaches active and releases cleanly | |
| 12 | Chat send during active call | Message sends while call remains active | |
| 13 | File send blocked during active call | Clear "Finish the call first" message | |

## Integrated Call UX Regression Matrix

Run these rows on the same build after the voice matrix. They cover the shared
call UI, connection, sound, and device-routing behavior that can regress voice
even when media negotiation still passes.

| Row | Scenario | Required result | Evidence |
| --- | --- | --- | --- |
| UX-1 | Android status bar visible during ringing, connecting, active, and failed call states | Call popup and controls never overlap the status bar or camera cutout | |
| UX-2 | Windows -> Android voice call, then briefly weaken network for 3-8 seconds | Call remains active or enters a recoverable weak-transport state without ending for a transient blip | |
| UX-3 | Send 10 messages quickly before and after a voice call | Sound feedback remains controlled and audible; the app must not become silent after the first message | |
| UX-4 | Manual disconnect on one peer while both peers are connected | The remote peer does not enter endless recovery and the local peer clearly stays manually disconnected | |
| UX-5 | Press Connect after a manual disconnect | A fresh peer session is created and the Connect button is not stuck disabled | |
| UX-6 | Start voice call while Bluetooth is disconnected | Bluetooth output option is hidden; available options match real device capabilities | |
| UX-7 | Start voice call while Bluetooth audio is connected | Bluetooth output option appears and route switching keeps the call alive | |
| UX-8 | Plug in wired headset before opening settings | Headset microphone appears in microphone settings and can be selected | |
| UX-9 | Open expanded call popup, then minimize it | Top call manager appears only when popup is minimized; controls and icons stay consistent | |
| UX-10 | Trigger a typed call failure | Failure message is clear, dismissible, and does not leave stale busy or running-call state | |

## Pass Criteria

All criteria must hold:

- Remote voice is audible both directions.
- Call reaches active only after media readiness.
- Hangup releases the Android microphone indicator.
- The next call works without restarting either app.
- Chat remains connected during and after calls.
- No stale `Peer is busy` state remains after failure or hangup.
- No `RTCRtpTransceiver has been disposed` errors appear.
- Forced failures show typed user-facing messages.
- Diagnostics keep the full native WebRTC failure reason for forced failures.
- Integrated call UX rows `UX-1` through `UX-10` pass on the same build.

## Failure Rule

If any row fails, mark the gate `FAIL`, keep the artifacts installed, capture
the exact user-facing message and diagnostics, and do not proceed to Phase 08.
