# Sound map

Measured 2026-10-26 from `apps/rain/assets/sounds/*.wav` (mono 44.1 kHz 16-bit) with a throwaway script outside the repo. Peak is the absolute sample peak (full scale 32767). RMS is over the whole file. Volume scale is `_volumeFor` in `infrastructure/services/sound_effects_service.dart:484`; the result is then multiplied by `soundEffectsVolume`, and by 0.55 during an active call for non-critical effects that are not allowed during calls. Throttle rules come from `application/audio/sound_event_router.dart:14-33` (see `00-ui-inventory.md` section 7).

## Current cues

| Event kind | Effect | File | Duration ms | Peak | RMS (dBFS) | Volume scale | Throttle / suppression |
|---|---|---|---|---|---|---|---|
| chatSend | send | send.wav | 156 | 9000 | 2072 (-24.0) | 0.30 | 300 ms burst, trailing x0.62 |
| chatReceive | receive | receive.wav | 190 | 9200 | 2204 (-23.4) | 0.32 | 900 ms per conversation, 350 ms global, max 4 per 3 s |
| uiAction | action | action.wav | 120 | 8600 | 1820 (-25.1) | 0.36 | 140 ms |
| warning | error | error.wav | 236 | 10400 | 2594 (-22.0) | 0.34 | 1.5 s per key, max 3 per 5 s |
| callIncomingStarted | callIncoming | call_incoming_loop.wav (loop) / call_incoming.wav | 1600 / 320 | 9200 / 9600 | 1295 (-28.1) / 2385 (-22.8) | 0.42 | loop id rain-call-incoming, 10 min dedupe |
| callOutgoingStarted | callOutgoing | call_outgoing_loop.wav (loop) / call_outgoing.wav | 1500 / 240 | 8400 / 8800 | 1054 (-29.9) / 1961 (-24.5) | 0.34 | loop id rain-call-outgoing, 10 min dedupe |
| callConnected | callConnected | call_connected.wav | 180 | 9200 | 2110 (-23.8) | 0.34 | 10 min lifecycle dedupe |
| callEnded | callEnded | call_ended.wav | 160 | 8400 | 1922 (-24.6) | 0.30 | 10 min lifecycle dedupe |
| callFailed | callFailed | call_failed.wav | 250 | 10400 | 2553 (-22.2) | 0.34 | 1.2 s failure window |
| callControlMute | mute | mute.wav | 110 | 8200 | 1974 (-24.4) | 0.26 | router policy |
| callControlUnmute | unmute | unmute.wav | 120 | 8400 | 1963 (-24.4) | 0.28 | router policy |
| callControlDeafen | deafen | deafen.wav | 130 | 8400 | 2076 (-24.0) | 0.26 | router policy |
| callControlUndeafen | undeafen | undeafen.wav | 130 | 8600 | 2129 (-23.7) | 0.28 | router policy |
| callControlCameraMute / Unmute | action (shared) | action.wav | 120 | 8600 | 1820 (-25.1) | 0.36 | router policy |
| callRouteChanged | action (shared) | action.wav | 120 | 8600 | 1820 (-25.1) | 0.36 | router policy |
| connectionRequestInbound | receive (shared) | receive.wav | 190 | 9200 | 2204 (-23.4) | 0.32 | 1.4 s window, max 3 per 8 s |
| connectionRequestOutboundAccepted | action (shared) | action.wav | 120 | 8600 | 1820 (-25.1) | 0.36 | 500 ms terminal window |
| connectionRequestOutboundRejected / Expired | error | error.wav | 236 | 10400 | 2594 (-22.0) | 0.34 | 500 ms terminal window |

Loudest one-shot: error.wav and call_failed.wav (peak 10400). Ringtone reference for U-D4: call_incoming (peak 9600 one-shot, 9200 loop, highest base volume 0.42).

## Shared cues and gaps

| Problem | Today | Fixed by |
|---|---|---|
| Camera on and off sound the same as any button | action.wav | T3.2 camera_on.wav / camera_off.wav, mapped in T3.3 |
| Audio route change sounds like a button | action.wav | T3.2 route_change.wav, T3.3 |
| Inbound connection request sounds like a chat message | receive.wav | T3.2 request_inbound.wav, T3.3 |
| Request accepted sounds like a button | action.wav | T3.2 request_accepted.wav, T3.3 |
| File transfer complete has no sound | none | T3.2 transfer_complete.wav, T3.3 event + mapping, T3.4 dispatch |
| File transfer failed has no sound | none | T3.3 maps fileTransferFailed to error.wav, T3.4 dispatch |
| First play has load latency | players created lazily | T3.5 warm-up |
| Ringing loops stop abruptly | stop() | T3.6 fade-out |
| Volume slider gives no feedback | silent | T3.7 preview |
