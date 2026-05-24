# Rain Sound Manual Device Gate - 2026-05-24

Gate status: NOT RUN

This gate covers app sound effects, ringtone/ringback loops, and active-call
sound suppression. It is intentionally separate from automated tests because
Android OEM audio focus, Bluetooth routing, and Windows audio device behavior
must be verified on real hardware.

## Build Under Test

```text
Branch: codex/video-call-v2
Baseline commit before Phase 09: 2b3b3b1
Recorded at: 2026-05-24T08:49:07+03:00
```

## Automated Assertions

- Short Rain sound effects use `AudioContextConfigFocus.mixWithOthers`.
- Looped ringtone/ringback sounds use `AudioContextConfigFocus.mixWithOthers`.
- Android audio focus for app sounds maps to `AndroidAudioFocus.none`.
- No app sound path requests `AudioContextConfigFocus.gain`.
- Looped sounds are stopped and disposed by `stopAllLoops()` and service
  disposal.
- Active WebRTC calls suppress non-critical chat/action sounds through the
  sound event router; call-control sounds remain quiet.

## Manual Matrix

| Row | Platform | Scenario | Expected Result | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | Android | Spotify/YouTube playing, then send/receive/action/error sounds | Music keeps playing; Rain sounds mix without pausing the other app | NOT RUN | Device required |
| 2 | Android | Incoming ringtone while music plays | Music continues or only ducks if the OS forces it; ringtone remains audible | NOT RUN | Device required |
| 3 | Android | Outgoing ringback while music plays | Music continues or only ducks if the OS forces it; ringback remains audible | NOT RUN | Device required |
| 4 | Android | Active WebRTC call, then incoming/outgoing chat messages | Chat sounds are suppressed while call is active | NOT RUN | Device required |
| 5 | Android | Active WebRTC call, then mute/unmute/deafen/undeafen | Control sounds play quietly and do not overpower call audio | NOT RUN | Device required |
| 6 | Android | Bluetooth earbuds connected, incoming ringtone | Ringtone routes acceptably and does not break call setup | NOT RUN | Device required |
| 7 | Android | Bluetooth earbuds connected, call controls during active call | Control sounds are audible but quiet; call audio route remains stable | NOT RUN | Device required |
| 8 | Android | Network loss during ringing | Ringtone stops; no stale ringing or busy state remains | NOT RUN | Device required |
| 9 | Android | Network loss during active call | Terminal sound is not stuck; no stale call loop remains | NOT RUN | Device required |
| 10 | Windows | Speakers active, repeated send/receive/action/error | Sounds play once per policy and do not stack noisily | NOT RUN | Windows runtime required |
| 11 | Windows | Headset active, call controls during active call | Control sounds are audible but not loud | NOT RUN | Windows runtime required |
| 12 | Windows | Repeated incoming/outgoing call attempts | Ring loops start once, stop on terminal state, and do not survive retry | NOT RUN | Windows runtime required |

## Release Rule

This gate must be rerun against the exact APK/EXE commit intended for release.
If any Android OEM pauses music despite the mixed audio context, keep the mixed
context and tune ringtone volume first; do not switch short app sounds to
exclusive audio focus without a separate architecture decision.
