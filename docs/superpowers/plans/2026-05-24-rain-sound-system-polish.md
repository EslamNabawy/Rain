# Rain Sound System Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Rain sound into a calm, reliable, water-themed app sound system that handles chat bursts, call ringing, active-call audio, settings, and failure cases without stuck sounds, sound spam, or music interruption.

**Architecture:** Keep WebRTC call audio separate from app sound effects. Add one central app-scoped sound event router above the existing `SoundEffectsService`; screens dispatch typed sound events and the router decides priority, grouping, cooldowns, ringtone lifecycle, volume, and suppression. Keep all policy local to the app; do not send sound settings, device names, or playback state to Firebase.

**Tech Stack:** Flutter, Riverpod, `audioplayers` 6.6.0, existing Rain assets under `apps/rain/assets/sounds/`, existing local settings in `AppSettingsStore`, Melos validation, Android and Windows manual audio checks.

---

## Hard Rules

- Do not move WebRTC voice/video call packets through Dart, Firebase, Drift, chat data channels, file channels, or the sound-effects service.
- Do not let any ringtone or looping sound survive accept, reject, busy, fail, hangup, timeout, logout, app dispose, or provider disposal.
- Do not request exclusive Android audio focus for short UI sound effects; app sounds must mix with music players whenever the platform allows it.
- Do not treat fast real messaging as abuse. Compress burst feedback, but never block messages or punish users for sending many messages.
- Do not stack many players for repeated events. One sound event owner decides when to play, merge, lower, or skip.
- Do not show raw sound/audio plugin exceptions in the UI.
- Do not add a new dependency unless the implementation phase proves the existing `audioplayers` stack cannot do the job.
- Do not break the working voice/video call path, file transfer blocking during calls, or existing sound settings.
- Keep this feature inside `apps/rain` unless a real platform audio API gap proves `peer_core`, `protocol_brain`, Firebase, or `rain_core` must change.
- Do not add background ringing in this pass; proper background ringing needs a foreground-service/notification design, not just sounds.
- Commit after every completed phase.
- Build only at the final release gate unless a phase explicitly needs a platform audio check.

## Existing Facts

- Current low-level sound service: `apps/rain/lib/infrastructure/services/sound_effects_service.dart`.
- Current service already uses `AudioContextConfigFocus.mixWithOthers`, `PlayerMode.lowLatency`, per-effect throttles, and local settings.
- Current provider: `soundEffectsProvider` in `apps/rain/lib/application/state/core_providers.dart`.
- Current local sound settings: `AppAudioSettings` and `AppSettingsStore` in `apps/rain/lib/infrastructure/services/app_settings_store.dart`.
- Current settings controller: `voiceAudioSettingsProvider` in `apps/rain/lib/application/state/settings_providers.dart`.
- Current settings UI: `apps/rain/lib/presentation/screens/settings_screen.dart`.
- Current call sound calls are spread through `apps/rain/lib/presentation/screens/home_screen.dart`.
- Current chat send/receive/error/action sounds are spread through `apps/rain/lib/presentation/widgets/home/chat_panel.dart` and onboarding.
- Current assets are mono 44.1 kHz 16-bit WAV files under `apps/rain/assets/sounds/`.
- Current asset test: `apps/rain/test/sound_effects_assets_test.dart`.
- Current service test: `apps/rain/test/sound_effects_service_test.dart`.
- Current call state includes `callId`, `sessionEpoch`, and `mediaMode` in `apps/rain/lib/application/runtime/voice_call_state.dart`.
- Current full validation commands are:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

## File Map

New app-layer sound policy files:

- `apps/rain/lib/application/audio/rain_sound_event.dart`
  - Typed event contract for chat, UI, warning, and call sound events.
- `apps/rain/lib/application/audio/sound_event_router.dart`
  - Central policy owner for priority, burst compression, ringtone lifecycle, settings, and call-context suppression.
- `apps/rain/lib/application/state/sound_event_providers.dart`
  - Riverpod wiring for `SoundEventRouter`, keeping sound policy out of widgets.
- `apps/rain/test/rain_sound_event_test.dart`
  - Contract tests for event normalization and required call IDs.
- `apps/rain/test/sound_event_router_test.dart`
  - Policy tests for mapping, bursts, priority, ringtone lifecycle, settings, and disposal.

Existing files to keep focused:

- `apps/rain/lib/infrastructure/services/sound_effects_service.dart`
  - Low-level asset playback, player lifecycle, audio context, volume, loops, and disposal only.
  - No `VoiceCallState`, Riverpod, chat policy, or Firebase awareness.
- `apps/rain/lib/presentation/screens/home_screen.dart`
  - Converts call-state transitions and explicit command failures into typed sound events.
- `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
  - Converts chat/file/user-action outcomes into typed sound events.
- `apps/rain/lib/infrastructure/services/app_settings_store.dart`
  - Local sound settings only.

## Sound Identity

Rain should sound clean, soft, and technical. The theme is water as a signature, not a nature soundboard.

- Send: tiny upward droplet tap.
- Receive: softer downward ripple.
- Generic action: clean glassy ripple click.
- Error: dampened low droplet, never alarm-like.
- Incoming call: gentle repeating rain-ripple motif.
- Outgoing call: sparse soft pulse.
- Connected: small bright two-step ripple.
- Ended: short falling ripple.
- Failed: broken/dampened ripple.
- Mute/deafen: covered low-pass tap.
- Unmute/undeafen: brighter open tap.

Asset constraints:

- WAV only for v1 of this polish pass.
- Mono, 44.1 kHz, 16-bit PCM.
- Short UI sounds: 80-260 ms.
- Call connect/end/fail: 150-500 ms.
- Ringtone loop: 3-6 s, seamless or cleanly restartable.
- Outgoing ringback loop: 2-5 s, quieter than incoming.
- No clipped peaks.
- No long rain beds behind calls.
- No sound should feel louder than call audio.

## Policy Model

Use typed events instead of direct `RainSoundEffect` calls from widgets:

```dart
enum RainSoundEventKind {
  chatSend,
  chatReceive,
  uiAction,
  warning,
  callIncomingStarted,
  callOutgoingStarted,
  callConnected,
  callEnded,
  callFailed,
  callControlMute,
  callControlUnmute,
  callControlDeafen,
  callControlUndeafen,
  callControlCameraMute,
  callControlCameraUnmute,
  callRouteChanged,
}
```

Each event carries only local context:

- `conversationId` when the event belongs to one chat.
- `peerId` when the event belongs to one call.
- `callId` when the event belongs to a specific call lifecycle.
- `sessionEpoch` when the event comes from `VoiceCallState` and needs stale-transition dedupe.
- `mediaMode` for audio/video compatibility.
- `isCallActive` and `isRinging` from current app state.
- `errorKey` for repeated failure compression.
- `occurredAt` from injected clock in tests.

Initial policy numbers:

- `chatSend`: play first immediately, then at most one grouped send tick every 300 ms.
- `chatReceive` same conversation: play first immediately, then at most one grouped receive tick every 900 ms.
- `chatReceive` different conversations: allow one every 350 ms globally, with max 4 receive sounds in 3 seconds.
- `uiAction`: per-action cooldown 140 ms.
- `warning`: per-error-key cooldown 1500 ms.
- `callIncomingStarted`: start ringtone once per `callId`; suppress chat sounds while ringing.
- `callOutgoingStarted`: start outgoing ringback once per `callId`; suppress chat sounds while ringing.
- `callConnected`: stop ringing first, then play connected sound once per `callId + sessionEpoch`.
- `callEnded` and `callFailed`: stop ringing first, then play terminal sound once per `callId + sessionEpoch`.
- Active call controls: allow mute/unmute/deafen/undeafen, but reduce volume through existing settings.

---

## Phase 00: Architecture Lock And Baseline

**Purpose:** Protect the working sound and call paths before adding policy.

**Files:**
- Read: `apps/rain/lib/infrastructure/services/sound_effects_service.dart`
- Read: `apps/rain/lib/application/state/core_providers.dart`
- Read: `apps/rain/lib/presentation/screens/home_screen.dart`
- Read: `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
- Read: `apps/rain/test/sound_effects_service_test.dart`
- Modify: `docs/superpowers/plans/2026-05-24-rain-sound-system-polish.md`

- [x] Confirm current sound service still maps to mixed audio focus.
- [x] Confirm current call media still uses WebRTC media tracks, not app sound service.
- [x] Confirm current settings remain local preferences.
- [x] Run focused baseline:

```powershell
flutter test apps\rain\test\sound_effects_service_test.dart
flutter test apps\rain\test\sound_effects_assets_test.dart
flutter test apps\rain\test\settings_screen_test.dart
flutter test apps\rain\test\rain_chat_widgets_test.dart
```

- [x] Commit plan/baseline docs only:

```powershell
git add docs\superpowers\plans\2026-05-24-rain-sound-system-polish.md
git commit -m "docs: plan rain sound system polish"
```

## Phase 01: Sound Event Contract

**Purpose:** Add typed sound events so UI no longer talks directly in raw asset effects.

**Status:** Complete.

**Files:**
- Create: `apps/rain/lib/application/audio/rain_sound_event.dart`
- Create: `apps/rain/test/rain_sound_event_test.dart`

**Design:**
- Add `RainSoundEventKind`.
- Add immutable `RainSoundEvent` with `kind`, `conversationId`, `peerId`, `callId`, `sessionEpoch`, `mediaMode`, `errorKey`, `occurredAt`.
- Add factories for common events:
  - `RainSoundEvent.chatSend(conversationId: ...)`
  - `RainSoundEvent.chatReceive(conversationId: ...)`
  - `RainSoundEvent.callIncomingStarted(callId: ..., peerId: ...)`
  - `RainSoundEvent.callOutgoingStarted(callId: ..., peerId: ...)`
  - `RainSoundEvent.callConnected(callId: ..., peerId: ...)`
  - `RainSoundEvent.callEnded(callId: ..., peerId: ...)`
  - `RainSoundEvent.callFailed(callId: ..., peerId: ..., errorKey: ...)`
- Normalize blank IDs to `null`.
- Do not put display names, device labels, message text, or raw error text in the event.

**Tests:**
- Blank IDs normalize to `null`.
- `errorKey` is stable and does not require raw UI text.
- Call lifecycle events require `callId`.
- Call-state lifecycle events include `sessionEpoch` when available.
- Camera-control events remain call-control events so they are allowed during active video calls.
- Chat events allow missing conversation only for global/system use.

**Validation:**

```powershell
flutter test apps\rain\test\rain_sound_event_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib\application\audio\rain_sound_event.dart apps\rain\test\rain_sound_event_test.dart
git commit -m "feat: add typed rain sound events"
```

## Phase 02: Central Sound Event Router

**Purpose:** Move sound decisions into one app-scoped owner.

**Status:** Complete.

**Files:**
- Create: `apps/rain/lib/application/audio/sound_event_router.dart`
- Create: `apps/rain/test/sound_event_router_test.dart`
- Create: `apps/rain/lib/application/state/sound_event_providers.dart`
- Modify: `apps/rain/lib/infrastructure/services/sound_effects_service.dart` only if the low-level API needs small support methods.

**Design:**
- Keep `SoundEffectsService` as the low-level player and asset map.
- Add `SoundEventRouter` as the policy layer.
- Router dependencies:
  - `SoundEffectsService effects`
  - `FutureOr<AppAudioSettings> Function() settingsLoader`
  - `VoiceCallState Function() callStateReader`
  - injected `DateTime Function() clock`
- Router public API:
  - `Future<void> dispatch(RainSoundEvent event)`
  - `Future<void> stopAllLoops()`
  - `Future<void> dispose()`
- Add `soundEventRouterProvider` in `sound_event_providers.dart`; keep `core_providers.dart` as the owner of low-level infrastructure providers only.
- Keep existing `soundEffectsProvider` for low-level playback and tests.

**Tests:**
- Dispatching `chatSend` plays `RainSoundEffect.send`.
- Dispatching `chatReceive` plays `RainSoundEffect.receive`.
- Dispatching `warning` plays `RainSoundEffect.error`.
- Dispatching call controls maps to mute/unmute/deafen/undeafen effects.
- Dispatching camera controls maps to a quiet call-control action and is allowed during active video calls.
- Router catches sound-service failures and does not throw into UI flows.

**Validation:**

```powershell
flutter test apps\rain\test\sound_event_router_test.dart
flutter test apps\rain\test\sound_effects_service_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib\application\audio apps\rain\lib\application\state\sound_event_providers.dart apps\rain\lib\infrastructure\services\sound_effects_service.dart apps\rain\test\sound_event_router_test.dart
git commit -m "feat: route rain sound events centrally"
```

## Phase 03: Burst Compression Without Abuse

**Purpose:** Let fast messaging feel responsive without creating sound spam or many overlapping players.

**Files:**
- Modify: `apps/rain/lib/application/audio/sound_event_router.dart`
- Modify: `apps/rain/test/sound_event_router_test.dart`

**Design:**
- Track last play time by event kind.
- Track last play time by conversation for receive bursts.
- Track recent receive plays in a rolling 3-second window.
- Compress repeated sends into one soft send tick per 300 ms.
- Compress same-conversation receives into one receive tick per 900 ms.
- Allow different-conversation receives more often, but cap globally.
- Throttle warnings by `errorKey`, not by raw exception text.
- Do not block or delay message sends; only sound feedback is compressed.

**Tests:**
- Five sends in 200 ms produce one send sound.
- Five sends over 1200 ms produce several spaced send sounds.
- Ten receives in one chat produce grouped receive sounds, not silence forever.
- Receives from two chats can both sound, but global cap applies.
- Same error repeated rapidly plays one warning sound.
- Different errors use separate warning keys but still respect a global warning ceiling.
- Self/history replayed message updates do not emit receive sounds.

**Validation:**

```powershell
flutter test apps\rain\test\sound_event_router_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib\application\audio\sound_event_router.dart apps\rain\test\sound_event_router_test.dart
git commit -m "feat: compress rain sound bursts"
```

## Phase 04: Ringtone And Ringback Lifecycle

**Purpose:** Add safe looped call sounds with strict ownership and cleanup.

**Files:**
- Modify: `apps/rain/lib/infrastructure/services/sound_effects_service.dart`
- Modify: `apps/rain/lib/application/audio/sound_event_router.dart`
- Modify: `apps/rain/test/sound_effects_service_test.dart`
- Modify: `apps/rain/test/sound_event_router_test.dart`

**Design:**
- Verify installed `audioplayers` loop API from the local package before implementation.
- Add low-level loop support behind project-owned methods:
  - `startLoop(RainSoundEffect effect, {required String loopId, required double volume})`
  - `stopLoop(String loopId)`
  - `stopAllLoops()`
- Maintain exactly one incoming ringtone loop and one outgoing ringback loop at most.
- Starting a new loop with the same `loopId` is idempotent.
- `callConnected`, `callEnded`, `callFailed`, `reject`, `busy`, `timeout`, remote cancel, network loss, logout, app close, and `dispose` stop loops before terminal sounds.
- `callSoundsEnabled=false` prevents new loops and stops existing call loops.
- `soundEffectsEnabled=false` stops all loops.

**Tests:**
- Incoming call starts ringtone once for a call ID.
- Repeated incoming state updates do not start duplicate loops.
- Accept stops ringtone and plays connected once.
- Reject/hangup/timeout/failure stop ringtone.
- Network loss, remote cancel, app close, logout, and router disposal stop ringtone.
- Outgoing call starts ringback once and stops on connected/failure.
- Disposing router stops all loops and disposes players.
- Disabling call sounds stops active call loops.

**Validation:**

```powershell
flutter test apps\rain\test\sound_effects_service_test.dart
flutter test apps\rain\test\sound_event_router_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib\infrastructure\services\sound_effects_service.dart apps\rain\lib\application\audio\sound_event_router.dart apps\rain\test\sound_effects_service_test.dart apps\rain\test\sound_event_router_test.dart
git commit -m "feat: add safe rain call ringtone loops"
```

## Phase 05: Call-State Priority Integration

**Purpose:** Replace direct call sound calls with router events and make call state the source of truth.

**Files:**
- Modify: `apps/rain/lib/presentation/screens/home_screen.dart`
- Modify: `apps/rain/test/rain_chat_widgets_test.dart`
- Modify: `apps/rain/test/friend_flow_test.dart`

**Design:**
- `_handleVoiceCallSound` dispatches typed lifecycle events instead of direct `RainSoundEffect` calls.
- Call-state transition events dedupe by `callId + sessionEpoch + phase`.
- `start`, `startVideo`, `accept`, `reject`, and `hangUp` do not play lifecycle sounds directly if a state transition will produce the same sound.
- Command handlers dispatch failure sounds only for command failures that do not produce a `VoiceCallPhase.failed` state.
- Mute, deafen, camera, and output-route actions dispatch typed call-control events after successful command completion.
- Router suppresses chat sounds during incoming/outgoing ringing.
- Router suppresses non-critical chat/action sounds during active calls when `reduceSoundsDuringCall=true`.
- Mute/deafen/unmute/undeafen remain allowed during calls at reduced volume.
- Video calls reuse the same call sound policy; no voice-only naming in the router API.
- Stop ringtone before accepting a call so it cannot overlap WebRTC communication audio setup.

**Tests:**
- Incoming call starts ringtone through router.
- Accept stops ringtone and plays connected.
- Hangup plays ended once.
- Accept does not double-play connected when both command handler and state listener run.
- Failed call plays failed once.
- Active call suppresses chat send/receive sounds.
- Mute/deafen still play during active call.
- Video call lifecycle uses the same sound router events.

**Validation:**

```powershell
flutter test apps\rain\test\rain_chat_widgets_test.dart
flutter test apps\rain\test\friend_flow_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib\presentation\screens\home_screen.dart apps\rain\test\rain_chat_widgets_test.dart apps\rain\test\friend_flow_test.dart
git commit -m "feat: route call sounds from call state"
```

## Phase 06: Chat And UI Sound Integration

**Purpose:** Replace direct chat/onboarding sound calls with typed events.

**Files:**
- Modify: `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
- Modify: `apps/rain/lib/presentation/screens/onboarding_screen.dart`
- Modify: `apps/rain/test/rain_chat_widgets_test.dart`
- Modify: `apps/rain/test/chat_panel` tests if split later.

**Design:**
- Chat receive listener dispatches `chatReceive(conversationId: peerId)`.
- Chat receive listener compares previous and next latest incoming IDs so initial history load and self/outgoing messages do not play receive sounds.
- Message send success dispatches `chatSend(conversationId: peerId)`.
- File send/accept/reject success uses `uiAction` or `chatSend` only when user-visible.
- Recoverable user errors dispatch `warning(errorKey: stableKey)`.
- Onboarding button success uses `uiAction`; validation failures use `warning`.
- Do not play a sound for every file-transfer progress update.

**Tests:**
- Rapid incoming messages dispatch grouped receive sounds.
- Initial message history load does not emit receive sounds.
- Outgoing/self messages do not emit receive sounds.
- Send success dispatches send event.
- File transfer progress does not emit repeated sounds.
- File transfer error emits throttled warning.
- Onboarding validation emits warning and respects settings.

**Validation:**

```powershell
flutter test apps\rain\test\rain_chat_widgets_test.dart
flutter test apps\rain\test\onboarding_screen_test.dart
```

If `onboarding_screen_test.dart` does not exist, add focused widget tests to the nearest existing onboarding/auth test file instead of creating a broad fixture.

**Commit:**

```powershell
git add apps\rain\lib\presentation\widgets\home\chat_panel.dart apps\rain\lib\presentation\screens\onboarding_screen.dart apps\rain\test
git commit -m "feat: route chat and ui sounds through policy"
```

## Phase 07: Rain-Themed Asset Pass

**Purpose:** Replace or refine sounds so the product has one calm water identity.

**Files:**
- Modify: `apps/rain/assets/sounds/*.wav`
- Modify: `apps/rain/test/sound_effects_assets_test.dart`
- Optional create: `apps/rain/tool/generate_rain_sound_assets.dart`
- Optional create: `apps/rain/assets/sounds/README.md`

**Design:**
- Prefer deterministic generation or documented asset provenance so future edits are repeatable.
- Keep all existing asset names unless the router adds ringtone/ringback loops.
- If adding loop assets, use explicit names:
  - `call_incoming_loop.wav`
  - `call_outgoing_loop.wav`
- Keep old short call sounds for terminal feedback even when ringtone loops exist.
- Asset tests enforce channels, sample rate, bit depth, duration, peak ceiling, RMS floor, and max file size.
- Add loop-specific checks that loop files are long enough and not clipped.

**Tests:**
- Every asset in `rainSoundEffectAssetPaths` exists.
- Every loop asset exists if referenced by `startLoop`.
- UI sounds remain under 260 ms unless explicitly categorized as call feedback.
- Ringtone/ringback loops stay under 6 seconds each.
- WAV metadata stays mono 44.1 kHz 16-bit.
- Peaks are below clipping.
- Total sound asset size remains small enough for APK impact.

**Validation:**

```powershell
flutter test apps\rain\test\sound_effects_assets_test.dart
```

**Commit:**

```powershell
git add apps\rain\assets\sounds apps\rain\test\sound_effects_assets_test.dart apps\rain\tool apps\rain\assets\sounds\README.md
git commit -m "feat: polish rain themed sound assets"
```

If optional files are not created, omit them from `git add`.

## Phase 08: Settings And Diagnostics Polish

**Purpose:** Make sound behavior controllable and debuggable without clutter.

**Files:**
- Modify: `apps/rain/lib/infrastructure/services/app_settings_store.dart`
- Modify: `apps/rain/lib/application/state/settings_providers.dart`
- Modify: `apps/rain/lib/presentation/screens/settings_screen.dart`
- Modify: `apps/rain/test/app_settings_store_test.dart`
- Modify: `apps/rain/test/settings_screen_test.dart`
- Optional modify: `apps/rain/lib/infrastructure/services/crash_diagnostics_service.dart`

**Design:**
- Keep settings simple:
  - Sound effects on/off.
  - Sound effects volume.
  - Call sounds on/off.
  - Reduce sounds during calls.
- Do not add per-sound settings in this pass.
- Add debug-only or diagnostics-only counters:
  - last sound event kind
  - last suppressed reason
  - active loop IDs
  - sound service disabled reason
- Do not show raw plugin exceptions to normal users.
- Do not persist diagnostics to Firebase.

**Tests:**
- Sound effects off stops all new sounds and loops.
- Call sounds off stops call loops but allows non-call UI sounds when sound effects are on.
- Reduce during calls suppresses chat events while active call is true.
- Settings screen remains usable on narrow mobile.
- Diagnostics sanitize plugin errors.

**Validation:**

```powershell
flutter test apps\rain\test\app_settings_store_test.dart
flutter test apps\rain\test\settings_screen_test.dart
flutter test apps\rain\test\sound_event_router_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib\infrastructure\services\app_settings_store.dart apps\rain\lib\application\state\settings_providers.dart apps\rain\lib\presentation\screens\settings_screen.dart apps\rain\test\app_settings_store_test.dart apps\rain\test\settings_screen_test.dart apps\rain\test\sound_event_router_test.dart
git commit -m "feat: polish rain sound settings"
```

## Phase 09: Audio Focus And Platform Safety

**Purpose:** Make Android/Windows behavior predictable around music, calls, speakers, and Bluetooth.

**Files:**
- Modify: `apps/rain/lib/infrastructure/services/sound_effects_service.dart`
- Modify: `apps/rain/test/sound_effects_service_test.dart`
- Modify: `docs/qa/voice-call-manual-device-gate-2026-05-24.md` or create `docs/qa/rain-sound-manual-device-gate-2026-05-24.md`

**Design:**
- Keep short SFX context on `AudioContextConfigFocus.mixWithOthers`.
- Verify looped ringtone context also does not request exclusive focus unless a platform proves it is required.
- If ringtone audibility conflicts with music, prefer a slightly louder mixed ringtone over pausing user music.
- Ensure `stopAllLoops()` runs on provider dispose and app logout cleanup.
- Document platform behavior separately from automated unit assertions.

**Manual checks:**
- Android phone with Spotify/YouTube playing: send/receive/action/error does not pause music.
- Android incoming ringtone with music playing: music continues or ducks only if the OS forces it.
- Android active WebRTC call: chat sounds are suppressed, mute/deafen sounds are quiet.
- Android Bluetooth earbuds: ringtone and call control sounds route acceptably.
- Android network loss during ringing and active call: ringtone stops and no stale busy/ringing state remains.
- Windows speakers: send/receive/action/error play once and do not stack.
- Windows headset: call controls remain audible but not loud.

**Validation:**

```powershell
flutter test apps\rain\test\sound_effects_service_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib\infrastructure\services\sound_effects_service.dart apps\rain\test\sound_effects_service_test.dart docs\qa
git commit -m "test: record rain sound platform gate"
```

## Phase 10: Full Automated Gate

**Purpose:** Prove the sound system did not regress calls, chat, settings, or assets.

**Files:**
- Modify: tests only if a gate exposes a missing regression.

**Required commands:**

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

**Acceptance:**
- All tests pass.
- No direct UI call site uses `soundEffectsProvider.play(...)` except low-level tests or deliberately documented compatibility shims.
- No ringtone loop can be started without a call ID.
- Every terminal call state stops loops.
- `callId + sessionEpoch` dedupe prevents stale Firebase/call retry snapshots from replaying ringtone or connected sounds.
- App sounds still mix with other audio by config.
- Asset tests cover every referenced WAV.

**Commit if test-only fixes are needed:**

```powershell
git add apps packages docs
git commit -m "test: complete rain sound validation gate"
```

## Phase 11: Final Build And Release Gate

**Purpose:** Package only after policy, assets, and tests are stable.

**Files:**
- Modify: `docs/qa/rain-sound-manual-device-gate-2026-05-24.md` if manual results are recorded.
- Modify: CI/build docs only if artifact expectations change.

**Build commands only when requested for release:**

```powershell
pwsh -NoProfile -File scripts\build_release.ps1 -Platform android -AndroidArtifactSet mobile -OutputDir artifacts -DartDefinesFile apps\rain\tool\dart_defines.example.json -AllowPublicTurnForDemo -UseDemoAndroidSigningKey -Clean
pwsh -NoProfile -File scripts\build_release.ps1 -Platform windows -OutputDir artifacts -DartDefinesFile apps\rain\tool\dart_defines.example.json -AllowPublicTurnForDemo -Clean
```

**Release acceptance:**
- Android v7 APK launches.
- Android v8/v9 APK launches.
- Windows exe launches.
- Sound settings survive restart.
- Incoming ringtone stops on accept/reject/hangup/timeout.
- Rapid chat messages do not create sound spam.
- Music playback is not paused by short Rain UI sounds on tested Android devices.
- Voice/video calls still connect and call media remains WebRTC-native.
- Manual QA records the tested commit hash, Android APK names, Windows artifact name, and any platform-specific audio limitation.

**Commit final gate docs:**

```powershell
git add docs\qa
git commit -m "docs: record rain sound release gate"
```

---

## Open Assumptions

- Rain can keep `audioplayers` for this pass; no native platform channel is planned unless loop/focus behavior fails real-device tests.
- User-facing sound theme should remain subtle and premium, not realistic heavy rainfall.
- Manual Android checks can be performed by installing the generated APKs on available phones.
- No Firebase schema change is needed for sound polish.

## Critical Risks

- Some Android OEMs may still pause or duck other audio despite mixed focus configuration.
- A looped ringtone can become stuck if lifecycle ownership is split between UI and runtime.
- Too-aggressive throttling can make real chat bursts feel dead.
- Too-loose throttling can make group-like conversations annoying.
- Asset replacement can accidentally increase APK size or sound harsh on phone speakers.

## Self-Review Checklist

- [ ] Every current direct sound call has a target router event.
- [ ] Every call terminal state stops ringtone/ringback loops.
- [ ] Burst compression distinguishes fast real messaging from abusive repeated playback.
- [ ] Settings remain simple and local.
- [ ] Tests cover policy, service, assets, settings, call lifecycle, and chat integration.
- [ ] Manual gate covers Android music playback, Android Bluetooth, Android speaker, Windows speaker, and Windows headset.
