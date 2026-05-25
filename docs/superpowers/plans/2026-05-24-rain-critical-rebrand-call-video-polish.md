# Rain Critical Rebrand Call Video Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan phase by phase. Use `superpowers:subagent-driven-development` when splitting visual audit, sound asset work, call UI, and platform icon work across agents.

**Goal:** Finish the Rain rebrand and rebuild the call/video presentation layer so the app feels coherent, branded, and production-ready without destabilizing the now-working WebRTC/Firebase media path.

**Architecture:** Keep the working media/signaling implementation intact. This plan changes presentation, branding assets, platform icons, sound assets/policies, and call-surface state/UI. The call experience becomes app-scoped: a top call manager bar remains visible while the call is active, video supports expanded/fullscreen/picture-in-picture/hidden modes, and the chat stays usable behind it.

**Tech Stack:** Flutter, Riverpod, Material 3, flutter_svg, flutter_webrtc renderers, audioplayers, Android/Windows platform icon assets, Melos validation, GitHub Actions release workflow.

**Critical Rule:** Commit after every completed phase. Build only at the final gate unless a phase explicitly needs a local visual smoke check.

---

## Phase 00: Visual Audit And Acceptance Lock

**Purpose:** Freeze what is currently wrong before changing code, so the work does not become subjective or drift into unrelated refactors.

- [x] Capture the current Android splash, login, home, chat, call, video call, settings, and app icon states.
- [x] Capture the current Windows splash, home, chat, call, video call, settings, and app icon states.
- [x] Create `docs/qa/2026-05-24-rain-critical-polish-audit.md`.
- [x] In the QA doc, list every still-old surface with file candidates:
  - `apps/rain/lib/presentation/screens/splash_screen.dart`
  - `apps/rain/lib/presentation/screens/home_screen.dart`
  - `apps/rain/lib/presentation/widgets/rain_backdrop.dart`
  - `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
  - `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`
  - `apps/rain/lib/presentation/theme/rain_theme.dart`
  - Android `mipmap-*` launcher icons
  - Windows `windows/runner/resources/app_icon.ico`
- [x] Define acceptance screenshots for the final gate:
  - Splash shows animated Rain mark and visible mist/texture.
  - App launcher icon is the new Peer Core mark on Android and Windows.
  - No major screen keeps the old flat dark-card treatment without Rain texture/state treatment.
  - Call manager is pinned at the top while a call is active.
  - Expanded call popup is centered and polished.
  - Video can enter fullscreen, minimize to a small window, and hide while the top manager remains.
- [x] Commit with message: `docs: audit critical Rain polish gaps`.

## Phase 01: Brand Token And Texture Upgrade

**Purpose:** Make the texture theme visible and reusable instead of being a subtle background that disappears on real devices.

- [x] Update `apps/rain/lib/presentation/theme/rain_theme.dart` with stronger Rain texture tokens:
  - Mist opacity levels for splash, app shell, panels, and call surfaces.
  - Signal-line colors separate from card borders.
  - Motion durations for ambient loops, splash intro, call transitions, and fullscreen transitions.
- [x] Update `apps/rain/lib/presentation/widgets/rain_backdrop.dart`:
  - Add named variants: `splash`, `shell`, `call`, and `settings`.
  - Make `splash` visibly textured on low-brightness Android screenshots.
  - Keep contrast high enough for text and controls.
- [x] Replace one-off background gradients in major screens with `RainBackdrop` variants.
- [x] Add/adjust tests:
  - `apps/rain/test/rain_theme_test.dart`
  - `apps/rain/test/rain_state_surfaces_test.dart`
- [x] Run focused tests for changed files.
- [x] Commit with message: `feat: strengthen Rain texture theme`.

## Phase 02: Platform App Icon Application

**Purpose:** Replace the old app icon everywhere users install or launch the app.

- [x] Verify source icon exists:
  - `apps/rain/assets/branding/generated/peer_core_app_icon_1024.png`
- [x] Apply platform icons with:
  - `powershell -ExecutionPolicy Bypass -File scripts/generate_rain_platform_icons.ps1 -Apply -Approved`
- [x] Verify Android outputs changed:
  - `apps/rain/android/app/src/main/res/mipmap-mdpi/ic_launcher.png`
  - `apps/rain/android/app/src/main/res/mipmap-hdpi/ic_launcher.png`
  - `apps/rain/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png`
  - `apps/rain/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png`
  - `apps/rain/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
- [x] Verify Windows output changed:
  - `apps/rain/windows/runner/resources/app_icon.ico`
- [x] Update platform labels where still lowercase or old:
  - Android launcher label should be `Rain`.
  - Windows window/app metadata should be `Rain` where supported by existing files.
- [x] Add a short note to the QA doc with icon source and generated outputs.
- [x] Commit with message: `feat: apply Rain platform icons`.

## Phase 03: Splash Logo Motion System

**Purpose:** Replace the static splash with a Rain-branded animation that works on Android and Windows without adding fragile dependencies.

- [x] Extend `apps/rain/lib/presentation/branding/rain_peer_core_mark.dart`.
- [x] Add an animation mode for the Peer Core mark:
  - Outer ring stays stable.
  - Inner three-dot mesh rotates inside the circle.
  - Dot path stays visually tangent to the inner circle instead of floating randomly.
  - Optional soft wave pulse emits from the ring during startup only.
- [x] Add reduced-motion support:
  - If animations are disabled, show the final mark state without looping motion.
- [x] Update `apps/rain/lib/presentation/screens/splash_screen.dart`:
  - Use the new animated Peer Core mark.
  - Apply `RainBackdrop.splash`.
  - Remove any old loading-bar behavior.
  - Keep startup timing tied to real app initialization, not fake delays.
- [x] Add widget tests:
  - Splash uses animated mark.
  - Reduced-motion path renders without animation controller leaks.
  - Splash text and logo fit small Android logical heights.
- [x] Commit with message: `feat: animate Rain splash mark`.

## Phase 04: Full Rebrand Surface Pass

**Purpose:** Remove remaining old visual language from the maintained app without touching obsolete scaffolding.

- [x] Search for hardcoded old colors, gradients, and card styles in `apps/rain/lib/presentation`.
- [x] Rebrand these surfaces first:
  - Login/auth card.
  - Home shell header.
  - Chat empty state.
  - Friend/profile panels.
  - Settings panels.
  - Connection status card.
  - File transfer rows.
  - Call failure banners.
- [x] Prefer existing Rain components:
  - `RainStreakSurface`
  - `RainStateSurface`
  - `RainBackdrop`
  - `RainPeerCoreMark`
- [x] Avoid nested cards and oversized decorative panels.
- [x] Add focused widget tests for at least the auth screen, chat empty state, and call banner.
- [x] Commit with message: `feat: complete Rain surface rebrand`.

## Phase 05: Rain Sound Asset Replacement

**Purpose:** Replace the current bad sound effects with clean, short, water-themed sounds that do not feel harsh or cheap.

- [x] Define final sound style in `apps/rain/assets/sounds/README.md`:
  - Light water-drop send.
  - Softer incoming ripple.
  - Low, non-alarming error splash.
  - Calm call outgoing loop.
  - Distinct but not annoying incoming ringtone.
  - Short call connected and ended sounds.
  - Quiet mute/deafen toggles.
- [x] Replace runtime assets in `apps/rain/assets/sounds/`:
  - `action.wav`
  - `send.wav`
  - `receive.wav`
  - `error.wav`
  - `call_incoming.wav`
  - `call_incoming_loop.wav`
  - `call_outgoing.wav`
  - `call_outgoing_loop.wav`
  - `call_connected.wav`
  - `call_ended.wav`
  - `call_failed.wav`
  - `mute.wav`
  - `unmute.wav`
  - `deafen.wav`
  - `undeafen.wav`
- [x] Keep files small and decode-friendly:
  - WAV or app-supported compressed format only.
  - UI effects under one second.
  - Loops must be seamless and not click at boundaries.
  - No copyrighted or unlicensed tracks.
- [x] Confirm `pubspec.yaml` asset declarations still include the sound folder.
- [x] Commit with message: `feat: refresh Rain sound assets`.

## Phase 06: Sound Playback Policy And QA Gate

**Purpose:** Make sounds reliable under real chat/call behavior, including message bursts and music playing on the phone.

- [x] Review `apps/rain/lib/application/audio/sound_event_router.dart`.
- [x] Review `apps/rain/lib/infrastructure/services/sound_effects_service.dart`.
- [x] Tune policies for:
  - Message burst compression without treating normal fast chat as abuse.
  - No overlapping ringtone/ringback loops.
  - No repeated failure sounds spamming the user.
  - No UI click sounds during active voice/video call unless explicitly allowed.
  - Audio focus mixing that does not pause external music for short UI sounds.
- [x] Add or update tests for:
  - Consecutive incoming messages compress into a tasteful sound pattern.
  - Call ringing owns the ringtone loop until accept/reject/hangup/timeout.
  - Call connected stops ringback before playing connected sound.
  - Failure sounds throttle correctly.
  - Deafen/mute sounds do not play when global sound is disabled.
- [x] Add QA notes for Android music playback while Rain sounds play.
- [x] Commit with message: `fix: harden Rain sound playback policy`.

## Phase 07: Call Surface State Model Rewrite

**Purpose:** Stop overloading "minimized" and make the call UI modes explicit.

- [x] Update `apps/rain/lib/application/state/call_surface_providers.dart`.
- [x] Replace the current minimized/bottom dock behavior with explicit state:
  - `managerOnly`: top call manager visible, media panel hidden.
  - `expanded`: centered call popup visible.
  - `fullscreen`: video takes the full app viewport.
  - `pip`: small floating video preview visible.
- [x] Remove `bottomSafe` as the default minimized behavior.
- [x] Define transitions:
  - Start voice call: `expanded`.
  - Start video call: `expanded`.
  - Tap minimize once during video: `pip`.
  - Tap minimize again: `managerOnly`.
  - Tap top manager: restore previous useful mode.
  - Tap fullscreen: `fullscreen`.
  - Back/Escape from fullscreen: return to `pip` or `expanded`.
- [x] Preserve current active call lifecycle and do not change signaling/media code.
- [x] Update `apps/rain/test/call_surface_providers_test.dart`.
- [x] Commit with message: `feat: model explicit call surface modes`.

## Phase 08: Top Call Manager Bar

**Purpose:** Keep call controls reachable without burying them at the bottom of chat.

- [x] Add `apps/rain/lib/presentation/widgets/calls/rain_call_manager_bar.dart`.
- [x] The top manager bar must show:
  - Peer display name/avatar.
  - Voice/video state.
  - Elapsed time or ringing state.
  - Mic toggle.
  - Camera toggle for video calls.
  - Deafen toggle.
  - Expand/restore.
  - Fullscreen for video.
  - Hangup.
- [x] Integrate it in `apps/rain/lib/presentation/screens/home_screen.dart` as an app-scoped overlay above chat content.
- [x] Ensure it respects safe areas on Android and window title/header spacing on Windows.
- [x] Remove the old bottom minimized chip behavior from `rain_call_overlay.dart`.
- [x] Add widget tests:
  - Active call renders top manager.
  - Manager remains visible when media panel is hidden.
  - Hangup and toggles dispatch existing runtime actions.
- [x] Commit with message: `feat: add top call manager bar`.

## Phase 09: Video Layout Modes

**Purpose:** Make video calls usable: expanded, fullscreen, picture-in-picture, then hidden while the manager remains.

- [x] Update `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`.
- [x] Update `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`.
- [x] Keep `apps/rain/lib/application/runtime/video_call_renderers.dart` focused on renderer lifecycle only.
- [x] Implement layout modes:
  - `expanded`: centered video/call popup.
  - `fullscreen`: remote video fills viewport with safe top controls.
  - `pip`: small draggable or fixed floating video window above chat content.
  - `managerOnly`: no video window, top manager still visible.
- [x] Local preview:
  - Show as a small preview in expanded/fullscreen.
  - Hide or shrink in pip.
  - Never cover the hangup/control area.
- [x] Empty/camera-off states:
  - Use Peer Core animated/audio meter surface.
  - Show clear camera-off/mic-only state.
- [x] Add tests for all layout transitions.
- [x] Commit with message: `feat: add video call layout modes`.

## Phase 10: Expanded Call Popup Redesign

**Purpose:** Make the central call popup feel like a real call surface, not a generic error/card panel.

- [x] Redesign `_RainExpandedCallPanel` in `rain_call_overlay.dart`.
- [x] Voice call popup:
  - Square or near-square central panel.
  - Peer identity at top.
  - Center audio activity visual using the Peer Core mark.
  - Real audio meter drives waves when available.
  - Controls dock at bottom with consistent icon buttons.
- [x] Video call popup:
  - Remote video is the main content.
  - Local preview has stable size and placement.
  - Controls are readable over video without blocking faces.
  - Fullscreen button is obvious.
- [x] Failure state:
  - Clear reason text.
  - Dismiss action.
  - No giant blocking banner that hides the whole chat longer than needed.
- [x] Add widget tests for voice active, video active, failed, ringing, and connecting states.
- [x] Commit with message: `feat: redesign call popup surface`.

## Phase 11: Mobile And Desktop Interaction Polish

**Purpose:** Make the new UI feel reliable on real Android phones and Windows desktops.

- [x] Android behavior:
  - Safe-area top manager never overlaps status bar.
  - Back button exits fullscreen before minimizing, and minimizes before ending only if that is already the app convention.
  - PiP window does not block message composer or bottom navigation.
  - Orientation changes do not lose renderer state.
- [x] Windows behavior:
  - Fullscreen respects app window bounds.
  - Escape exits fullscreen.
  - Top manager remains reachable at small desktop window sizes.
- [x] Keyboard behavior:
  - Chat composer remains usable while call manager is visible.
  - Call manager does not fight auth/login keyboard layout.
- [x] Add tests for compact width/height constraints.
- [x] Commit with message: `fix: polish call UI interactions`.

## Phase 12: Automated Test And Visual Harness Gate

**Purpose:** Catch regressions before producing installable builds.

- [x] Run formatting where needed.
- [x] Run focused tests for changed areas:
  - `dart run melos exec --scope rain -- flutter test test/call_surface_providers_test.dart`
  - `dart run melos exec --scope rain -- flutter test test/rain_brand_mark_test.dart`
  - `dart run melos exec --scope rain -- flutter test test/rain_chat_widgets_test.dart`
  - Any new call overlay/sound tests.
- [x] Run standard validation:
  - `dart pub get`
  - `dart run melos run analyze`
  - `dart run melos run test`
- [x] Create or update QA document:
  - `docs/qa/2026-05-24-rain-critical-polish-validation.md`
- [x] Commit with message: `test: validate Rain critical polish`.

## Phase 13: Final Build And Release Gate

**Purpose:** Produce installable artifacts only after the polished UI and tests pass.

- [x] Build only at this phase.
- [x] Build Android v7 and v8/v9 packages using the existing release scripts/workflow.
- [x] Build Windows executable/package using the existing release scripts/workflow.
- [x] Trigger the GitHub Actions release workflow with individual APK assets enabled.
- [x] Confirm release artifacts are individually downloadable:
  - v7 APK.
  - v8/v9 APK.
  - Windows artifact.
- [x] Add release notes:
  - Completed rebrand.
  - New splash animation.
  - New app icons.
  - Replaced sound effects.
  - Top call manager.
  - Video fullscreen/PiP/hidden modes.
- [x] Commit any final workflow/doc updates with message: `chore: prepare Rain polish release`.

---

## Non-Negotiable Guardrails

- Do not change Firebase signaling or WebRTC media negotiation unless a test proves the UI work exposed a runtime bug.
- Do not regress voice calls that already work.
- Do not remove v7 builds.
- Do not introduce copyrighted sounds.
- Do not add heavy animation dependencies.
- Do not hide call controls behind chat content.
- Do not place the active call manager at the bottom of the chat.
- Do not ship without Android and Windows artifact verification.

## Execution Notes

- Each phase should end with a commit and a short QA note.
- Prefer small, reviewable commits over one giant UI rewrite.
- If a phase discovers a runtime media bug, stop and create a separate fix plan before touching the working call stack.
- Use final screenshots from Android and Windows as the acceptance proof, because the main failures reported here are visual and interaction quality failures.
