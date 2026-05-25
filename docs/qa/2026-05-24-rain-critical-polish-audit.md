# Rain Critical Polish Phase 00 Audit

Date: 2026-05-24
Branch: `codex/rain-rebrand-implementation`
Commit audited before Phase 00 changes: `d18293f`

## Scope

This audit locks the baseline for the critical polish pass requested after the Rain rebrand. Phase 00 does not change runtime behavior, WebRTC signaling, Firebase signaling, or media negotiation. It documents what still looks or behaves wrong so later phases stay focused.

## Evidence Captured

### Android

Source screenshot:

- `C:/Users/eslam/OneDrive/Desktop/Screenshot_20260524_173511.jpg`

Observed current state:

- Splash shows the Peer Core mark, app name `Rain`, and subtitle `Private peer link`.
- The logo appears static in the screenshot.
- The background reads as a mostly flat dark screen; the Rain mist/texture treatment is not strong enough to be visible.
- No app-launch animation evidence is visible from the captured state.

### Windows

No runnable Windows build exists at `apps/rain/build/windows/x64/runner/Release/rain.exe`, and this phase intentionally does not build. The Windows baseline is captured from platform source files:

- `apps/rain/windows/runner/main.cpp` creates the window title as `rain`.
- `apps/rain/windows/runner/Runner.rc` still uses lowercase `rain` for file description, internal name, original filename, and product name.
- `apps/rain/windows/runner/resources/app_icon.ico` exists, but must be regenerated from the current Peer Core app icon source in Phase 02.

## Critical Findings

### 1. Splash Rebrand Is Incomplete

Files:

- `apps/rain/lib/presentation/screens/splash_screen.dart`
- `apps/rain/lib/presentation/branding/rain_peer_core_mark.dart`
- `apps/rain/lib/presentation/widgets/rain_backdrop.dart`

Current behavior:

- `splash_screen.dart` still hardcodes subtitle text as `Private peer link`.
- Splash uses `RainPeerCoreAnimatedMark(size: 112)`, but the current animation is a short one-shot wave/scale animation, not the planned rotating mesh or persistent startup motion.
- `RainBackdrop` is present, but the texture is too subtle on the Android screenshot to read as an intentional theme.

Required final state:

- Splash must visibly use the Rain texture/backdrop.
- Peer Core mark must animate during startup.
- Preferred animation: stable outer circle with the three connected mesh dots rotating inside the circle, optionally with a soft startup wave.
- Reduced-motion mode must render a clean static mark without animation leaks.

### 2. Platform App Icon And App Metadata Are Not Fully Rebranded

Files:

- `scripts/generate_rain_platform_icons.ps1`
- `apps/rain/assets/branding/generated/peer_core_app_icon_1024.png`
- `apps/rain/android/app/src/main/AndroidManifest.xml`
- `apps/rain/android/app/src/main/res/mipmap-*/ic_launcher.png`
- `apps/rain/windows/runner/resources/app_icon.ico`
- `apps/rain/windows/runner/main.cpp`
- `apps/rain/windows/runner/Runner.rc`

Current behavior:

- Android manifest still sets `android:label="rain"`.
- Windows title and resource metadata still use lowercase `rain`.
- Android and Windows launcher icon outputs need to be regenerated/applied from the Peer Core icon source.

Required final state:

- Android launcher label is `Rain`.
- Windows app title and visible metadata are `Rain` where supported by existing project files.
- Android launcher icons and Windows ICO are generated from `peer_core_app_icon_1024.png`.

Phase 02 application note:

- Source icon verified: `apps/rain/assets/branding/generated/peer_core_app_icon_1024.png` at `1024x1024`.
- Applied with `scripts/generate_rain_platform_icons.ps1 -Apply -Approved`.
- Android outputs verified:
  - `mipmap-mdpi/ic_launcher.png` at `48x48`.
  - `mipmap-hdpi/ic_launcher.png` at `72x72`.
  - `mipmap-xhdpi/ic_launcher.png` at `96x96`.
  - `mipmap-xxhdpi/ic_launcher.png` at `144x144`.
  - `mipmap-xxxhdpi/ic_launcher.png` at `192x192`.
- Windows output verified: `apps/rain/windows/runner/resources/app_icon.ico` exists after regeneration.
- The same approved script also refreshed existing Linux and macOS runner icon outputs; those files are kept with this phase because they are owned by the icon generation script.

### 3. Texture Theme Is Too Subtle And Not Variant-Based

Files:

- `apps/rain/lib/presentation/widgets/rain_backdrop.dart`
- `apps/rain/lib/presentation/theme/rain_theme.dart`
- Major presentation screens under `apps/rain/lib/presentation/screens/`
- Major home widgets under `apps/rain/lib/presentation/widgets/home/`

Current behavior:

- `RainBackdrop` has a single implementation.
- Signal mist line opacity is low (`0.055`/`0.070` for lines, lower for accents).
- There are no explicit variants for splash, shell, call, and settings surfaces.

Required final state:

- Texture is visible enough on Android low-brightness screenshots.
- Splash, app shell, call surface, and settings use suitable texture variants.
- Text and controls remain readable.

### 4. Call And Video Surface Model Is Still Bottom-Minimized

Files:

- `apps/rain/lib/application/state/call_surface_providers.dart`
- `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- `apps/rain/lib/presentation/screens/home_screen.dart`
- `apps/rain/test/call_surface_providers_test.dart`
- `apps/rain/test/rain_chat_widgets_test.dart`

Current behavior:

- `CallSurfaceMode` only supports `expanded` and `minimized`.
- `CallSurfaceDock` includes `bottomSafe`.
- `minimize()` defaults to `CallSurfaceDock.bottomSafe`.
- `rain_call_overlay.dart` renders `_RainMinimizedCallChip` at `Alignment.bottomCenter` with bottom padding.
- Existing tests assert the bottom minimized behavior.

Required final state:

- Active calls always keep a top call manager available.
- Minimized video first becomes a small PiP-style window.
- Minimizing again hides the media window while keeping the top manager.
- Fullscreen video is supported.
- The old bottom minimized chip behavior is removed or no longer the default.

### 5. Expanded Call Popup Needs UX Redesign

Files:

- `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`
- `apps/rain/lib/application/runtime/video_call_renderers.dart`

Current behavior:

- The expanded call panel is still a generic overlay/card-style surface.
- Voice and video states share too much of the same generic layout.
- Video has no explicit fullscreen/PiP/hidden surface model.
- The user cannot rely on a persistent top manager while working in chat.

Required final state:

- Voice call popup is a polished central square or near-square surface.
- Voice state uses a real audio activity visual, ideally driven by the existing Peer Core mark.
- Video call popup prioritizes remote video, stable local preview, and visible controls.
- Fullscreen/PiP/hidden transitions are clear and reversible.

### 6. Sound Effects Need Replacement And QA

Files:

- `apps/rain/assets/sounds/`
- `apps/rain/assets/sounds/README.md`
- `apps/rain/lib/application/audio/sound_event_router.dart`
- `apps/rain/lib/infrastructure/services/sound_effects_service.dart`

Current behavior:

- Runtime sound files exist and routing/policy code exists, but the current assets were rejected in real use as unpleasant.
- This is now an asset-quality problem plus a playback policy QA problem.

Required final state:

- Use clean, light, Rain/water-themed sounds.
- Short UI sounds should not pause external phone music.
- Ringing/ringback loops must not overlap or continue after state changes.
- Message bursts should compress tastefully without suppressing normal fast chat.

## Final Acceptance Screenshot Set

Final gate must capture and attach screenshots or QA notes for:

- Android splash with visible texture and animated mark.
- Android launcher showing new Rain icon.
- Android login/auth surface with rebrand treatment.
- Android home/chat empty state with rebrand treatment.
- Android active voice call with top manager and central popup.
- Android active video call expanded.
- Android active video call fullscreen.
- Android active video call PiP/minimized.
- Android manager-only state after media window is hidden.
- Windows splash with visible texture and animated mark.
- Windows launcher/window icon and title.
- Windows active voice call with top manager.
- Windows active video call fullscreen or app-window fullscreen mode.

## Guardrails For Later Phases

- Do not touch working Firebase/WebRTC media negotiation for visual polish.
- Do not rework the voice/video runtime unless a test proves the presentation layer exposes a real lifecycle bug.
- Do not replace the sound router with scattered direct audio calls.
- Do not ship icon changes until both Android and Windows outputs are verified.
- Do not build per phase; build only at the final gate unless an explicit phase says otherwise.
