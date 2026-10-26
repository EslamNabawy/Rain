# UI Inventory (T0.3, 2026-10-11, base 02e02f2)

Read-only. Sections 1-3 restate the verified facts from `rain-uiux-orchestrator.xml`; sections 4-7 come from Grep/scripts on `apps/rain/lib`.

## 1. Loading and startup states (facts)

- `main.dart` `RainStartupApp` shows a bare `MaterialApp(home: RainSplashScreen())` without theme during bootstrap; `BootstrapFailureApp` uses `ThemeData.dark()`; then `RainApp` shows `RainStartupSurface` per `AppStartupPhase`.
- Every loading phase renders the same splash with no caption. The splash is re-mounted in up to 3 MaterialApps, so the 520 ms intro and orbital mark restart at each hand-off. No cross-fade into onboarding/home.
- `RainStartupFailureScreen` shows raw `error.toString()`, no retry. Force-update gate is a plain `Card`. Account deletion is a bare `CircularProgressIndicator`.
- Android native splash is a flat `#061017` rectangle with no mark; no `values-v31` styles.
- `RainStreakSkeleton` is static grey bars. One `LinearProgressIndicator` (file transfer) jumps without tween.
- Two empty/error widgets: `AppStateMessage` (12 uses) and `RainMistStateCard` (2 uses).
- Five copies of the "make error readable" helper; raw `error.toString()` reaches the UI in `search_screen.dart` and `chat_panel.dart`.

## 2. Sound (facts)

- 15 generated WAVs (mono 44.1 kHz 16-bit) from `tool/generate_rain_sound_assets.dart`; contract test `sound_effects_assets_test.dart`.
- Shared cues today: camera on/off, route change and "request accepted" all play `action.wav`; inbound connection request plays `receive.wav`; rejected/expired play `error.wav`. File transfers are silent.
- Lazy player creation (first-play latency); loops stop abruptly; volume slider gives no preview.

## 3. Theme (facts)

- `rain_theme.dart`: `RainColors`, `RainTextureTokens`, `RainMotion`, `RainTheme.dark()/light()`; Inter + Space Grotesk fetched at runtime via google_fonts.
- Dark theme has no `snackBarTheme`. No spacing/radius tokens. Reduced motion computed ad hoc.

## 4. Loading, progress, empty and error states

| Site | Waiting for | Current visual | Target |
|---|---|---|---|
| widgets/chat_composer.dart:153 | message send | CircularProgressIndicator | T1.6, T2.7 |
| widgets/chat_composer.dart:225 | attachment/send busy | CircularProgressIndicator | T1.6, T2.7 |
| widgets/home/file_transfer_bubble.dart:105 | file transfer progress | LinearProgressIndicator, value jumps | T2.7 |
| widgets/home/link_status.dart:170 | link connecting | CircularProgressIndicator | T1.6 |
| widgets/rain_chat_widgets.dart:233 | busy control | CircularProgressIndicator | T1.6 |
| widgets/rain_chat_widgets.dart:529 | busy control | CircularProgressIndicator | T1.6 |
| widgets/rain_chat_widgets.dart:1259 | busy action | CircularProgressIndicator | T1.6 |
| widgets/rain_chat_widgets.dart:1371 | busy action | CircularProgressIndicator | T1.6 |
| widgets/home/friends_list.dart:96-99 | friends loading | RainStreakSkeleton(rows: 4) in Center | T2.6 |
| widgets/home/friends_list.dart:191 | friend action busy | CircularProgressIndicator | T1.6 |
| widgets/home/friends_list.dart:56, :90 | empty friends / error | AppStateMessage | T1.5, T4.4 |
| widgets/home/chat_panel.dart:900-908 | messages loading | RainStreakSkeleton(rows: 5) | T2.6 |
| widgets/home/chat_panel.dart:883-897 | messages failed | AppStateMessage + raw error text | T1.4 |
| widgets/home/chat_panel.dart:188, :784, :1387 | empty/offline chat states | AppStateMessage | T1.5, T4.4 |
| screens/search_screen.dart:243, :305 | search loading | `_SearchLoading` + RainStreakSkeleton(rows: 4) | T2.6 |
| screens/search_screen.dart:241 | search failed | raw `error.toString()` | T1.4 |
| screens/search_screen.dart:265, :321, :352 | idle / no results | AppStateMessage | T4.4 |
| screens/search_screen.dart:428 | add friend busy | CircularProgressIndicator | T1.6 |
| screens/onboarding_screen.dart:541 | sign-in/up busy | CircularProgressIndicator | T1.6 |
| screens/home_screen.dart:1156 | home empty state | AppStateMessage | T1.5, T4.4 |
| screens/friend_profile_screen.dart:36 | profile error | AppStateMessage | T1.4, T1.5 |
| screens/settings_screen.dart:186-348 (6 async tiles) | device lists/settings loading | `loading:` builds real tile, `error:` ListTile | T1.4 |
| screens/settings_screen.dart:450-475 | settings loading/busy | ListTile + CircularProgressIndicator | T1.6 |
| screens/settings_screen.dart:1400-1416, :1492 | settings loading/busy | ListTile + CircularProgressIndicator | T1.6 |
| screens/settings_screen.dart:1856-1868 | section loading | AppSectionCard + RainStreakSkeleton(rows: 2) | T2.6 |
| screens/splash_screen.dart:81 | startup phase | CircularProgressIndicator(strokeWidth: 4) | T2.2, T2.4 |
| branding/rain_state_surfaces.dart:8, :113 | definitions | RainMistStateCard / RainStreakSkeleton | T1.5, T2.6 |
| widgets/app_components.dart:184, :212 | definitions | AppStateMessage wraps RainMistStateCard | T1.5 |

Note: a `loading:` count in settings_screen.dart (lines 199, 237, 279, 319, 348) builds the full control with defaults, not a spinner.

## 5. IconButtons without a tooltip

All in `widgets/calls/rain_call_manager_bar.dart`: lines 217, 225, 404, 412, 419, 483, 488 (7 hits). All other `IconButton(` sites have `tooltip:` within 12 lines. Target: T4.3.

## 6. Hard-coded styling hot spots (top 10 in presentation/)

| File | BorderRadius.circular | Color(0x | TextStyle( |
|---|---|---|---|
| theme/rain_theme.dart | 18 | 53 | 16 |
| screens/home_screen.dart | 1 | 13 | 0 |
| widgets/rain_chat_widgets.dart | 12 | 2 | 0 |
| widgets/home/friends_list.dart | 6 | 6 | 0 |
| widgets/calls/rain_call_overlay.dart | 8 | 0 | 0 |
| widgets/home/chat_panel.dart | 1 | 4 | 2 |
| widgets/rain_backdrop.dart | 0 | 7 | 0 |
| widgets/calls/rain_call_stage.dart | 5 | 0 | 0 |
| screens/splash_screen.dart | 0 | 0 | 4 |
| widgets/home/link_status.dart | 4 | 0 | 0 |

## 7. Sound triggers

Throttle constants: `sound_event_router.dart:14-33`. Effect mapping: `_effectFor` at :629.

| Event kind | Dispatch site | Effect file | Throttle rule |
|---|---|---|---|
| chatSend | home_screen.dart:243 (via chat composer), chat_panel.dart:301 | send.wav | 300 ms send burst, trailing volume x0.62 |
| chatReceive | home_screen.dart:239 | receive.wav | 900 ms same conversation, 350 ms global, max 4 per 3 s |
| uiAction | home_screen.dart:247, :1404; onboarding_screen.dart:669 | action.wav | 140 ms |
| warning | home_screen.dart:251, :345; onboarding_screen.dart:688 | error.wav | 1.5 s per key, max 3 per 5 s |
| callIncomingStarted | home_screen.dart:145 | call_incoming loop | loop id rain-call-incoming, volume 0.42, 10 min dedupe |
| callOutgoingStarted | home_screen.dart:151 | call_outgoing loop | loop id rain-call-outgoing, volume 0.34, 10 min dedupe |
| callConnected | home_screen.dart:157 | call_connected.wav | 10 min lifecycle dedupe |
| callEnded | home_screen.dart:183, :189 | call_ended.wav | 10 min lifecycle dedupe |
| callFailed | home_screen.dart:163, :172, :351 | call_failed.wav | 1.2 s failure window |
| callControlMute / Unmute | home_screen.dart:396, :405 | mute.wav / unmute.wav | per router policy |
| callControlDeafen / Undeafen | home_screen.dart:414, :423 | deafen.wav / undeafen.wav | per router policy |
| callControlCameraMute / Unmute | home_screen.dart:432, :441 | action.wav (shared) | per router policy |
| callRouteChanged | home_screen.dart:450 | action.wav (shared) | per router policy |
| connectionRequestInbound | home_screen.dart:269 | receive.wav (shared with chat) | 1.4 s window, max 3 per 8 s |
| connectionRequestOutboundAccepted | home_screen.dart:289 | action.wav (shared) | 500 ms terminal window |
| connectionRequestOutboundRejected / Expired | home_screen.dart:294, :299 | error.wav | 500 ms terminal window |
| file transfer completed/failed | none | none | missing (T3.3, T3.4) |
