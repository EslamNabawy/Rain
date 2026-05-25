# Video Call Manual Device Gate

This gate is a release blocker for video calling. Automated tests prove widget
and runtime contracts, but this gate requires the exact same build installed on
real Android and Windows devices.

## Required Evidence

Record these before starting:

```text
Gate status: BLOCKED | PASS | FAIL
Tester:
Date:
Git commit:
Android v7a artifact:
Android v7a SHA256:
Android v8/v9 artifact:
Android v8/v9 SHA256:
Windows artifact:
Windows artifact SHA256:
Android device model and Android version:
Windows version and camera count:
External camera, headset, Bluetooth devices used:
ICE config used for direct route:
ICE config used for TURN relay:
Rain accounts:
```

Use artifacts from the same commit only. Do not mix APKs or Windows builds from
different workflow runs.

## Setup

1. Install the Android and Windows artifacts from the same Git commit.
2. Confirm hashes for every artifact that will be installed.
3. Sign in two accepted friend accounts.
4. Keep both apps foregrounded unless a row explicitly tests app close.
5. Verify the link banner route before each direct or relay row.
6. Export diagnostics for every failed row before retrying or reinstalling.

## Core Video Matrix

Every row must include result, route shown in UI, caller device, callee device,
failure text if any, and diagnostics reference.

| Row | Scenario | Required result | Evidence |
| --- | --- | --- | --- |
| 1 | Windows -> Android direct route video call | Call reaches active, remote video and audio work both directions, Windows app does not crash | |
| 2 | Android -> Windows direct route video call | Call reaches active, remote video and audio work both directions, Android does not keep stale running-call state | |
| 3 | Windows -> Android TURN relay video call | Call reaches active, remote video and audio work both directions | |
| 4 | Android -> Windows TURN relay video call | Call reaches active, remote video and audio work both directions | |
| 5 | Android camera permission denied | Typed camera-required failure, no accepted active call, no stale busy state | |
| 6 | Windows camera unavailable or blocked | Typed camera-required failure, no accepted active call, no stale busy state | |
| 7 | Caller hangup from expanded video popup | Peer exits call, camera indicator clears, chat remains usable | |
| 8 | Callee hangup from minimized call manager | Peer exits call, camera indicator clears, chat remains usable | |
| 9 | App close during active video call | Remote call state clears and media is disposed | |
| 10 | Five repeated video calls without app restart | Every call reaches active and releases camera/mic cleanly | |

## Integrated Call UX Regression Matrix

Run these rows on the same build after the core matrix. They cover shared call
surfaces, device controls, and sound behavior.

| Row | Scenario | Required result | Evidence |
| --- | --- | --- | --- |
| UX-1 | Android status bar visible during ringing, connecting, active, fullscreen, PiP, and failed states | Call popup and video controls never overlap the status bar or camera cutout | |
| UX-2 | PC -> Android video call, then briefly weaken network for 3-8 seconds | Call stays active or enters recoverable weak-transport state without crash or stale busy state | |
| UX-3 | Android -> PC video call | Remote peer video is the main view and self video is the preview | |
| UX-4 | Tap the preview during active video | Main and preview roles swap immediately without renegotiation or call drop | |
| UX-5 | Laptop with only one camera | Flip-camera control is hidden | |
| UX-6 | Android phone with front and rear cameras | Flip-camera control appears and camera switch keeps the call alive | |
| UX-7 | Bluetooth disconnected | Bluetooth output option is hidden; only available output routes are shown | |
| UX-8 | Bluetooth connected | Bluetooth output option appears and route switching keeps the call alive | |
| UX-9 | Wired headset connected | Headset microphone appears in settings and can be selected before the next call | |
| UX-10 | Send 10 messages quickly before and after a video call | Sound feedback remains controlled and audible; the app must not become silent after the first message | |
| UX-11 | Manual disconnect on one peer while both peers are connected | The remote peer does not enter endless recovery | |
| UX-12 | Press Connect after manual disconnect | A fresh peer session is created and the Connect button is not stuck disabled | |
| UX-13 | Expanded popup open, then minimize twice | Top call manager appears only while minimized; video can become PiP, then manager-only, without hiding required controls | |

## Pass Criteria

All criteria must hold:

- Remote video is visible in the main view by default.
- Self video is preview by default and can swap with the main view.
- Audio works both directions during video calls.
- Camera and microphone indicators clear after hangup or failure.
- No stale `Peer is busy` or running-call state remains after failure, retry,
  app close, or hangup.
- Fullscreen and minimized states remain inside safe areas.
- Device controls match real hardware capabilities.
- Sound feedback remains audible but controlled during message bursts.
- Diagnostics keep the full native failure reason for forced failures.

## Failure Rule

If any row fails, mark the gate `FAIL`, keep the artifacts installed, capture
the exact user-facing message and diagnostics, and do not proceed to release.
