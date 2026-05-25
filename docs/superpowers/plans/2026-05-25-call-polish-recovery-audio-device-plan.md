# Call Polish, Recovery, Audio, And Device Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix call UX regressions and stability gaps without damaging working voice/video/Firebase signaling.

**Architecture:** Build from lower dependencies upward: connection intent and call failure semantics first, then media device inventory and route capabilities, then UI surfaces, then sound assets/policy. Keep Riverpod as the app state layer, keep WebRTC/platform operations behind `peer_core` and `MediaDeviceSettings`, and keep widgets display-only.

**Tech Stack:** Flutter, Dart, Riverpod, Melos, `flutter_webrtc`, `audioplayers`, Firebase voice signaling, existing Rain design-system widgets.

---

## Phase 00: Evidence Lock And Baseline Contracts

**Why First:** Every later phase depends on knowing which behavior is current, which behavior is desired, and which tests must not regress.

**Files:**
- Modify: `apps/rain/test/friend_flow_test.dart`
- Modify: `apps/rain/test/rain_chat_widgets_test.dart`
- Modify: `apps/rain/test/rain_call_manager_bar_test.dart`
- Modify: `apps/rain/test/sound_event_router_test.dart`
- Modify: `apps/rain/test/settings_screen_test.dart`
- Modify: `packages/protocol_brain/test/protocol_brain_test.dart`
- Modify: `packages/peer_core/test/voice_media_connection_test.dart`

- [ ] **Step 1: Add failing regression names before behavior changes**

Add or rename tests so failures map directly to user reports:

```dart
test('manual disconnect suppresses remote recovery and interactive reconnect restarts cleanly', () async {});
test('weak call transport enters reconnecting grace instead of immediate failed disconnect', () async {});
testWidgets('ripple halo wraps the component bounds instead of only the icon glyph', (tester) async {});
testWidgets('call overlay respects top safe area and does not overlap Android status bar', (tester) async {});
testWidgets('video stage shows remote video as primary and local video as preview', (tester) async {});
testWidgets('tapping local preview swaps primary and preview video roles', (tester) async {});
test('sound router preserves burst feedback without disabling message sounds', () async {});
testWidgets('output route control hides bluetooth unless bluetooth output is available', (tester) async {});
testWidgets('settings microphone picker shows real audio inputs including wired headset labels', (tester) async {});
```

- [ ] **Step 2: Run targeted tests to capture red state**

Run:

```powershell
dart run melos exec --scope rain -- flutter test test/friend_flow_test.dart test/rain_chat_widgets_test.dart test/rain_call_manager_bar_test.dart test/sound_event_router_test.dart test/settings_screen_test.dart
dart run melos exec --scope protocol_brain -- flutter test test/protocol_brain_test.dart
dart run melos exec --scope peer_core -- flutter test test/voice_media_connection_test.dart
```

Expected: new or renamed tests fail until later phases implement behavior.

- [ ] **Step 3: Commit baseline tests**

```powershell
git add apps/rain/test/friend_flow_test.dart apps/rain/test/rain_chat_widgets_test.dart apps/rain/test/rain_call_manager_bar_test.dart apps/rain/test/sound_event_router_test.dart apps/rain/test/settings_screen_test.dart packages/protocol_brain/test/protocol_brain_test.dart packages/peer_core/test/voice_media_connection_test.dart
git commit -m "test: lock call polish and recovery regressions"
```

---

## Phase 01: Manual Disconnect And Reconnect Intent Model

**Why Here:** The user cannot trust calls if base peer connection intent is wrong. Fix this before media-call resilience.

**Files:**
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Modify: `apps/rain/lib/application/runtime/connection_attempt_coordinator.dart`
- Modify: `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
- Test: `apps/rain/test/friend_flow_test.dart`
- Test: `packages/protocol_brain/test/protocol_brain_test.dart`

**Design:**
- Add explicit disconnect reason: `manualLocal`, `manualRemote`, `transportLost`, `networkLost`.
- Local manual disconnect must:
  - stop local reconnect attempts,
  - unregister local passive listener for that peer,
  - tell runtime this is user intent,
  - allow next interactive Connect to remove manual intent and force a fresh connect.
- Remote sees peer close as remote manual/terminal, not a transient failure loop.

- [ ] **Step 1: Add protocol/runtime tests**

Expected state:

```dart
expect(runtime.connectionCoordinatorSnapshotFor('bob').manualDisconnect, isTrue);
await runtime.connectPeer('bob', interactive: true, waitForConnected: true);
expect(runtime.connectionCoordinatorSnapshotFor('bob').manualDisconnect, isFalse);
expect(brain.getSession('bob')?.state, SessionState.connected);
```

- [ ] **Step 2: Implement intent classification**

Add a typed intent enum in app runtime, not UI:

```dart
enum PeerDisconnectIntent {
  localManual,
  remoteManual,
  transportLost,
  networkLost,
}
```

Keep mapping private unless tests need a public snapshot.

- [ ] **Step 3: Force interactive reconnect to destroy stale reconnecting sessions**

In `connectPeer`, after manual intent is cleared, if current session is `connecting` or `reconnecting`, disconnect it first when `interactive == true` and `bypassRetryBackoff == true`.

- [ ] **Step 4: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/friend_flow_test.dart
dart run melos exec --scope protocol_brain -- flutter test test/protocol_brain_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/runtime/rain_runtime_controller.dart apps/rain/lib/application/runtime/connection_attempt_coordinator.dart packages/protocol_brain/lib/src/protocol_brain_impl.dart apps/rain/test/friend_flow_test.dart packages/protocol_brain/test/protocol_brain_test.dart
git commit -m "fix: make manual disconnect and reconnect deterministic"
```

---

## Phase 02: Call Transport Weakness Grace Model

**Why Here:** Voice/video failures in the middle of calls may be real network drops or short WebRTC reconnect windows. UI should not instantly show failed unless the call is truly terminal.

**Files:**
- Modify: `apps/rain/lib/application/runtime/voice_call_state.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Modify: `packages/protocol_brain/lib/src/voice_call_session.dart`
- Test: `apps/rain/test/friend_flow_test.dart`
- Test: `packages/protocol_brain/test/voice_call_session_test.dart`

**Design:**
- Add call-level `reconnecting` display state without ending Firebase room immediately.
- Short peer/session disconnect during active call becomes `active + detail: Reconnecting...` or a new phase if needed.
- Terminal failure only after timeout, explicit remote hangup, Firebase failed room, or confirmed network lost.
- Do not hide hard errors like mic denied, camera denied, media renderer failure, or explicit peer busy.

- [ ] **Step 1: Add failing call resilience test**

```dart
expect(aliceRuntime.voiceCallState.phase, VoiceCallPhase.active);
bobBrain.emitTransientPeerDisconnect('alice');
expect(aliceRuntime.voiceCallState.phase, VoiceCallPhase.active);
expect(aliceRuntime.voiceCallState.detail, contains('Reconnecting'));
```

- [ ] **Step 2: Add call reconnect metadata**

Extend `VoiceCallState` with fields:

```dart
final bool mediaReconnecting;
final int? reconnectingSince;
```

Update constructor, `idle`, and `copyWith`.

- [ ] **Step 3: Use grace timeout**

Set a single timeout owned by `RainRuntimeController`, not widgets:

```dart
static const Duration _activeCallReconnectGrace = Duration(seconds: 8);
```

If session recovers before timeout, clear `mediaReconnecting`. If not, end call with `VoiceCallFailureReason.networkLost`.

- [ ] **Step 4: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/friend_flow_test.dart test/rain_chat_widgets_test.dart
dart run melos exec --scope protocol_brain -- flutter test test/voice_call_session_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/runtime/voice_call_state.dart apps/rain/lib/application/runtime/voice_call_runtime.dart apps/rain/lib/application/runtime/rain_runtime_controller.dart packages/protocol_brain/lib/src/voice_call_session.dart apps/rain/test/friend_flow_test.dart packages/protocol_brain/test/voice_call_session_test.dart
git commit -m "fix: add active call reconnect grace"
```

---

## Phase 03: Media Device Inventory Contract

**Why Here:** Speaker/Bluetooth UI and microphone settings depend on reliable typed device inventory.

**Files:**
- Modify: `packages/peer_core/lib/src/platform_bridge.dart`
- Modify: `apps/rain/lib/application/runtime/media_device_settings.dart`
- Modify: `apps/rain/lib/application/state/settings_providers.dart`
- Modify: `apps/rain/lib/infrastructure/services/app_settings_store.dart`
- Test: `apps/rain/test/media_device_settings_test.dart`
- Test: `apps/rain/test/settings_screen_test.dart`
- Test: `packages/peer_core/test/voice_media_connection_test.dart`

**Design:**
- Keep `flutter_webrtc.navigator.mediaDevices.enumerateDevices()` as base.
- Classify devices by `audioinput`, `audiooutput`, `videoinput`.
- Add label inference for wired/Bluetooth/headset/mic when labels are available after permission.
- Store selected mic by device id; if missing, fall back to default and show warning.
- Keep Windows/Android behavior separate only where platform APIs differ.

- [ ] **Step 1: Add typed output capability state**

Add:

```dart
final class AudioOutputCapabilityState {
  const AudioOutputCapabilityState({
    required this.devices,
    this.selectedRoute = VoiceCallOutputRoute.systemDefault,
  });

  final List<RainMediaDevice> devices;
  final VoiceCallOutputRoute selectedRoute;

  bool get hasBluetoothOutput => devices.any((device) => device.isBluetoothAudioOutput);
  bool get hasWiredOutput => devices.any((device) => device.isWiredAudioOutput);
}
```

- [ ] **Step 2: Add classification helpers**

In `RainMediaDevice`:

```dart
bool get isBluetoothAudioOutput =>
    isAudioOutput && _hasAnyToken(_labelTokens(label), const {'bluetooth', 'airpods', 'earpods', 'headset', 'buds'});

bool get isWiredAudioInput =>
    isAudioInput && _hasAnyToken(_labelTokens(label), const {'wired', 'headset', 'headphones', 'earpods', 'usb'});
```

- [ ] **Step 3: Add providers**

Add `audioOutputCapabilityProvider` beside `microphoneSelectionProvider`.

- [ ] **Step 4: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/media_device_settings_test.dart test/settings_screen_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add packages/peer_core/lib/src/platform_bridge.dart apps/rain/lib/application/runtime/media_device_settings.dart apps/rain/lib/application/state/settings_providers.dart apps/rain/lib/infrastructure/services/app_settings_store.dart apps/rain/test/media_device_settings_test.dart apps/rain/test/settings_screen_test.dart packages/peer_core/test/voice_media_connection_test.dart
git commit -m "feat: add typed media device inventory"
```

---

## Phase 04: Output Route Capability And Toggle Behavior

**Why Here:** UI route controls must be driven by Phase 03 inventory, not hardcoded menu options.

**Files:**
- Modify: `apps/rain/lib/application/runtime/voice_call_state.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Modify: `apps/rain/lib/presentation/screens/settings_screen.dart`
- Test: `apps/rain/test/rain_chat_widgets_test.dart`
- Test: `apps/rain/test/settings_screen_test.dart`

**Design:**
- During active calls:
  - no Bluetooth device: route control toggles between system/default and speaker, or shows only Default/Speaker.
  - Bluetooth output available: show Bluetooth as an option.
  - wired headset plugged: do not label it Bluetooth; allow system default to use it.
- Do not promise exact Android output switching beyond `flutter_webrtc.Helper` support. Show warning if helper fails.

- [ ] **Step 1: Add route option model**

```dart
final class VoiceCallOutputRouteOption {
  const VoiceCallOutputRouteOption({
    required this.route,
    required this.label,
    required this.icon,
  });

  final VoiceCallOutputRoute route;
  final String label;
  final IconData icon;
}
```

- [ ] **Step 2: Filter controls with capability state**

Pass output route options into `RainCallControls`, replacing hardcoded Bluetooth menu entries.

- [ ] **Step 3: Update route selection behavior**

If user taps route button and only two options exist, toggle. If three exist, open menu.

- [ ] **Step 4: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/rain_chat_widgets_test.dart test/settings_screen_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/runtime/voice_call_state.dart apps/rain/lib/application/runtime/voice_call_runtime.dart apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart apps/rain/lib/presentation/screens/settings_screen.dart apps/rain/test/rain_chat_widgets_test.dart apps/rain/test/settings_screen_test.dart
git commit -m "fix: make call output routes device-aware"
```

---

## Phase 05: Settings Microphone Selection Polish

**Why Here:** It depends on typed inventory and must be done before final audio/device QA.

**Files:**
- Modify: `apps/rain/lib/presentation/screens/settings_screen.dart`
- Modify: `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`
- Modify: `apps/rain/lib/application/state/settings_providers.dart`
- Test: `apps/rain/test/settings_screen_test.dart`
- Test: `apps/rain/test/media_device_settings_test.dart`

**Design:**
- Show real mic names after permission warmup.
- Show labels like `Wired headset mic`, `Bluetooth mic`, `USB microphone`, `Default microphone`.
- Keep selected unavailable mic visible as warning until user chooses another.
- Settings change applies to next call. Do not hot-swap mic mid-call in this phase.

- [ ] **Step 1: Add display label tests**

```dart
expect(device.displayLabel(0), 'Wired headset mic');
expect(selection.hasMissingSelection, isTrue);
```

- [ ] **Step 2: Improve settings copy**

Use concise user text:

```text
Applies to the next call.
Selected microphone unavailable. Using default.
```

- [ ] **Step 3: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/settings_screen_test.dart test/media_device_settings_test.dart
```

- [ ] **Step 4: Commit**

```powershell
git add apps/rain/lib/presentation/screens/settings_screen.dart apps/rain/lib/presentation/widgets/rain_chat_widgets.dart apps/rain/lib/application/state/settings_providers.dart apps/rain/test/settings_screen_test.dart apps/rain/test/media_device_settings_test.dart
git commit -m "feat: polish microphone device selection"
```

---

## Phase 06: Ripple Halo Surface Geometry Fix

**Why Here:** Visual fix is independent once runtime-critical phases are safe.

**Files:**
- Modify: `apps/rain/lib/presentation/branding/rain_ripple_halo_surface.dart`
- Modify: `apps/rain/lib/presentation/navigation/rain_navigation_shell.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/link_status.dart`
- Test: `apps/rain/test/rain_theme_test.dart`
- Test: `apps/rain/test/rain_chat_widgets_test.dart`
- Test: `apps/rain/test/rain_navigation_shell_test.dart`

**Design:**
- Halo belongs around component container, not icon glyph.
- `RainRippleHaloSurface` should not clip pulse to icon-sized child when child is an `IconButton`.
- Add explicit `minSize` or require wrapper dimensions for icon controls.
- Keep static halo subtle; only one pulse on state change; respect reduced motion.

- [ ] **Step 1: Add min-size API**

```dart
class RainRippleHaloSurface extends StatefulWidget {
  const RainRippleHaloSurface({
    super.key,
    required this.child,
    this.enabled = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.color,
    this.origin = Alignment.center,
    this.pulseKey,
    this.pulseOnMount = false,
    this.minSize,
  });

  final Size? minSize;
}
```

- [ ] **Step 2: Wrap child with constraints before painting**

```dart
final constrainedChild = widget.minSize == null
    ? widget.child
    : ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minSize!.width,
          minHeight: widget.minSize!.height,
        ),
        child: widget.child,
      );
```

- [ ] **Step 3: Apply component-level sizes**

Use `minSize: const Size(48, 48)` for call control buttons, nav items, status chips, and selected settings pills.

- [ ] **Step 4: Run widget tests**

```powershell
dart run melos exec --scope rain -- flutter test test/rain_theme_test.dart test/rain_chat_widgets_test.dart test/rain_navigation_shell_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/presentation/branding/rain_ripple_halo_surface.dart apps/rain/lib/presentation/navigation/rain_navigation_shell.dart apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart apps/rain/lib/presentation/widgets/home/link_status.dart apps/rain/test/rain_theme_test.dart apps/rain/test/rain_chat_widgets_test.dart apps/rain/test/rain_navigation_shell_test.dart
git commit -m "fix: align ripple halos to component bounds"
```

---

## Phase 07: Call Overlay Safe Area And Layout Contract

**Why Here:** It depends on stable call surface state but not audio routing.

**Files:**
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_manager_bar.dart`
- Modify: `apps/rain/lib/application/state/call_surface_providers.dart`
- Test: `apps/rain/test/rain_chat_widgets_test.dart`
- Test: `apps/rain/test/rain_call_manager_bar_test.dart`
- Test: `apps/rain/test/call_surface_providers_test.dart`

**Design:**
- Expanded popup and fullscreen video must use `SafeArea`.
- Manager bar remains top-only when popup is minimized.
- When popup is open, manager bar hidden.
- On Android, top padding must include status bar.
- On desktop, safe area should not add fake status padding.

- [ ] **Step 1: Add safe-area widget tests**

Set test surface:

```dart
tester.view.padding = FakeViewPadding(top: 36);
```

Assert popup top is below safe area.

- [ ] **Step 2: Wrap overlay root**

Use:

```dart
SafeArea(
  minimum: const EdgeInsets.all(12),
  child: ...
)
```

For fullscreen video:

```dart
Stack(
  children: [
    Positioned.fill(child: RainVideoCallStage(...)),
    SafeArea(child: controls),
  ],
)
```

- [ ] **Step 3: Enforce manager/popup exclusivity**

In call surface provider tests:

```dart
expect(surface.showsExpandedOverlay, isTrue);
expect(surface.showsManagerBar, isFalse);
```

- [ ] **Step 4: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/rain_chat_widgets_test.dart test/rain_call_manager_bar_test.dart test/call_surface_providers_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart apps/rain/lib/presentation/widgets/calls/rain_call_manager_bar.dart apps/rain/lib/application/state/call_surface_providers.dart apps/rain/test/rain_chat_widgets_test.dart apps/rain/test/rain_call_manager_bar_test.dart apps/rain/test/call_surface_providers_test.dart
git commit -m "fix: keep call surfaces inside safe areas"
```

---

## Phase 08: Video Primary/Preview Role Model

**Why Here:** Video UI behavior depends on call overlay being spatially correct.

**Files:**
- Modify: `apps/rain/lib/application/state/call_surface_providers.dart`
- Modify: `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- Test: `apps/rain/test/call_surface_providers_test.dart`
- Test: `apps/rain/test/rain_chat_widgets_test.dart`

**Design:**
- Default: remote video primary, local video preview.
- Tap preview: swap primary/preview.
- Preview tap is UI state only; it must not affect WebRTC tracks.
- In PIP mode, prefer remote as visible content unless user swapped.
- Persist swap only for current call id.

- [ ] **Step 1: Add role enum**

```dart
enum VideoPrimaryRole { remote, local }
```

Add to `CallSurfaceState`:

```dart
final VideoPrimaryRole videoPrimaryRole;
```

- [ ] **Step 2: Add action**

```dart
void toggleVideoPrimaryRole(String callId) {
  state = state.copyWith(
    videoPrimaryRole: state.videoPrimaryRole == VideoPrimaryRole.remote
        ? VideoPrimaryRole.local
        : VideoPrimaryRole.remote,
  );
}
```

- [ ] **Step 3: Render by role**

`RainVideoCallStage` gets:

```dart
final VideoPrimaryRole primaryRole;
final VoidCallback? onTogglePrimaryRole;
```

When `primaryRole == remote`, main = `_RainRemoteVideoSurface`, preview = `_RainLocalVideoPreview`. When local, swap widgets and use correct mirror only for local renderer.

- [ ] **Step 4: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/call_surface_providers_test.dart test/rain_chat_widgets_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/state/call_surface_providers.dart apps/rain/lib/presentation/widgets/rain_chat_widgets.dart apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart apps/rain/test/call_surface_providers_test.dart apps/rain/test/rain_chat_widgets_test.dart
git commit -m "feat: support video primary preview switching"
```

---

## Phase 09: Sound Asset Replacement

**Why Here:** Sound policy should be stable before judging new sound assets.

**Files:**
- Replace assets under: `apps/rain/assets/sounds/`
- Modify: `apps/rain/pubspec.yaml` only if asset paths change
- Test: `apps/rain/test/sound_effects_service_test.dart`
- Test: `packages/protocol_brain/test/release_contract_test.dart`

**Design Direction:**
- Replace every effect with short, restrained rain/water/glass-inspired audio:
  - send: tiny soft drop
  - receive: slightly lower soft drop
  - action: muted tap
  - error: low dull water-glass thud
  - incoming loop: calm premium ring, not harsh alarm
  - outgoing loop: quieter ringback pulse
  - connected/end: tiny confirmation/decay
  - mute/deafen: very short filtered tick
- Keep files short and compressed WAV/OGG based on package support. Prefer small `.wav` if current pipeline assumes WAV.
- Normalize loudness so no sound jumps above call audio.

- [ ] **Step 1: Add asset contract test**

Verify every path in `rainSoundEffectAssetPaths` exists and is non-empty.

- [ ] **Step 2: Replace assets**

Keep exact file names unless changing format is intentionally tested:

```text
apps/rain/assets/sounds/send.wav
apps/rain/assets/sounds/receive.wav
apps/rain/assets/sounds/action.wav
apps/rain/assets/sounds/error.wav
apps/rain/assets/sounds/call_incoming.wav
apps/rain/assets/sounds/call_outgoing.wav
apps/rain/assets/sounds/call_connected.wav
apps/rain/assets/sounds/call_ended.wav
apps/rain/assets/sounds/call_failed.wav
apps/rain/assets/sounds/mute.wav
apps/rain/assets/sounds/unmute.wav
apps/rain/assets/sounds/deafen.wav
apps/rain/assets/sounds/undeafen.wav
apps/rain/assets/sounds/call_incoming_loop.wav
apps/rain/assets/sounds/call_outgoing_loop.wav
```

- [ ] **Step 3: Run sound tests**

```powershell
dart run melos exec --scope rain -- flutter test test/sound_effects_service_test.dart
```

- [ ] **Step 4: Commit**

```powershell
git add apps/rain/assets/sounds apps/rain/pubspec.yaml apps/rain/test/sound_effects_service_test.dart packages/protocol_brain/test/release_contract_test.dart
git commit -m "assets: replace Rain sound effects"
```

---

## Phase 10: Sound Burst Policy And Playback Reliability

**Why Here:** Asset replacement alone will not fix message bursts or bad suppression.

**Files:**
- Modify: `apps/rain/lib/application/audio/sound_event_router.dart`
- Modify: `apps/rain/lib/infrastructure/services/sound_effects_service.dart`
- Test: `apps/rain/test/sound_event_router_test.dart`
- Test: `apps/rain/test/sound_effects_service_test.dart`

**Design:**
- Sending many messages quickly should not become silence.
- Compress bursts into controlled feedback:
  - first send plays immediately,
  - later sends inside burst window schedule one soft trailing tick,
  - receive burst allows occasional grouped sound without abuse.
- Playback failure for one player should not permanently disable all sounds unless plugin is missing.

- [ ] **Step 1: Add scheduled trailing event state**

```dart
Timer? _pendingSendBurstTick;
DateTime? _lastSendBurstSuppressedAt;
```

- [ ] **Step 2: Change send suppression**

Instead of suppressing all sends in `_sendBurstWindow`, schedule one trailing `RainSoundEffect.send`.

- [ ] **Step 3: Narrow disable behavior**

Keep global disable for `MissingPluginException`; for transient playback error, record diagnostics and skip only current effect.

- [ ] **Step 4: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/sound_event_router_test.dart test/sound_effects_service_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/audio/sound_event_router.dart apps/rain/lib/infrastructure/services/sound_effects_service.dart apps/rain/test/sound_event_router_test.dart apps/rain/test/sound_effects_service_test.dart
git commit -m "fix: preserve sound feedback during message bursts"
```

---

## Phase 11: Integrated Call UX QA Gate

**Why Here:** This phase verifies all dependent UI/runtime/audio changes together.

**Files:**
- Modify: `docs/qa/voice-call-manual-device-gate.md`
- Modify: `docs/qa/video-call-manual-device-gate.md` if present; otherwise create it.
- Test: existing full automated suite.

- [ ] **Step 1: Add manual scenarios**

Manual gate must include:

```text
1. Android status bar visible; call popup never overlaps it.
2. PC -> Android voice call stays active during short network weakness.
3. Android -> PC video call shows remote as main and self as preview.
4. Tap preview swaps video roles.
5. Bluetooth disconnected: no Bluetooth output option.
6. Bluetooth connected: Bluetooth option appears.
7. Wired headset connected: headset mic appears in settings.
8. Send 10 messages quickly: sound feedback remains controlled, not silent.
9. Manual disconnect on one peer does not cause endless remote recovery.
10. Press Connect after manual disconnect creates a fresh session.
```

- [ ] **Step 2: Run full validation**

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

- [ ] **Step 3: Commit**

```powershell
git add docs/qa/voice-call-manual-device-gate.md docs/qa/video-call-manual-device-gate.md
git commit -m "docs: expand call UX manual gate"
```

---

## Phase 12: Final Build And Release Gate

**Why Last:** Build only after all automated tests pass and manual checklist is updated.

**Files:**
- No source changes expected.
- Artifacts from GitHub Actions or local release scripts.

- [ ] **Step 1: Confirm no unrelated dirty files are staged**

```powershell
git status --short
git diff --cached --name-only
```

- [ ] **Step 2: Trigger cloud build**

Demo/device-test build:

```powershell
gh workflow run build-artifacts.yml --ref <branch> -f platform=all -f build_profile=demo -f publish_test_release=true
```

Production release build only after Android signing secrets exist:

```powershell
gh workflow run build-artifacts.yml --ref <branch> -f platform=all -f build_profile=production -f publish_test_release=true
```

- [ ] **Step 3: Verify artifacts**

Expected direct assets:

```text
Rain-Demo-Android-v7a.apk
Rain-Demo-Android-v8-v9.apk
Rain-Demo-Windows-x64.zip
```

or production equivalents:

```text
Rain-Release-Android-v7a.apk
Rain-Release-Android-v8-v9.apk
Rain-Release-Windows-x64.zip
```

- [ ] **Step 4: Commit only if docs changed**

```powershell
git status --short
```

No commit needed if build-only phase changed no files.

---

## Dependency Order Summary

1. Phase 00 locks evidence.
2. Phase 01 fixes base peer intent.
3. Phase 02 fixes call weakness semantics on top of peer intent.
4. Phase 03 builds typed device inventory.
5. Phase 04 uses inventory for output routing.
6. Phase 05 polishes mic settings using same inventory.
7. Phase 06 fixes halo geometry.
8. Phase 07 fixes safe-area call surfaces.
9. Phase 08 fixes video layout after surface contract.
10. Phase 09 replaces bad assets.
11. Phase 10 fixes burst playback policy.
12. Phase 11 validates all behavior.
13. Phase 12 builds and releases.

## Non-Goals

- No new call signaling schema unless a later evidence phase proves Firebase call state is still insufficient.
- No background ringing.
- No hot microphone switching mid-call in this plan.
- No new audio engine unless `audioplayers` cannot satisfy non-interrupting, burst-safe playback after Phase 10.
- No production Android release build until signing secrets exist.

## Review Notes

- Most dangerous phases: Phase 01 and Phase 02. They touch peer and call lifecycle. Keep commits small and test after each phase.
- Most likely UX regressions: Phase 06, Phase 07, Phase 08. Use widget tests with constrained mobile sizes.
- Most platform-dependent phase: Phase 04. Android Bluetooth routing behavior must be manually verified on actual Bluetooth device.
- Sound quality cannot be proven by unit tests. Tests prove presence, routing, and burst policy; human listening still required.
