# UI UX Level-Up

## Purpose

Level up Rain's consistency, motion, loading/startup states, sound and tactile feedback without changing its identity. Work ran on branch `ui/level-up` (worktree `D:\Rain-uiux`) next to the hardening program, under `audit/prompts/rain-uiux-orchestrator.xml`. Task log, decisions and evidence: `audit/ui/STATE.md`, final report `audit/ui/04-report.md`.

Related: [[Branding And UI]], [[Sound System]], [[Frontend Architecture]], [[Feature Index]].

## Design Direction

- Keep the dark "signal mist" identity: cyan/mint on deep ink, Space Grotesk titles and Inter body. No rebrand, no new palette.
- Motion budget: UI transitions 110-240 ms, ease-out in and ease-in out. Only the splash mark, skeleton pulse and call-connecting pulse loop, and all of them stop under reduced motion or the low-power tier.
- Sound stays in the generated "water droplet" family. Every distinct meaning gets a distinct cue, and nothing is louder than the incoming ringtone.

## Tokens And Motion Policy

- `presentation/theme/rain_tokens.dart`: `RainSpace`, `RainRadius`, `RainShadows`. `RainMotion` adds enter/exit/emphasized curves and named durations (`loadingRevealDelay`, `splashCaptionDelay`, `skeletonPulse`, `messageEnter`, `progressTween`, `connectingPulse`, `pressScale`).
- `presentation/performance/rain_motion_policy.dart`: `RainMotionPolicy.of(context)` is the single reduced-motion answer (OS "remove animations" or the low-power tier). Reduced code renders the end state with `Duration.zero` and starts no repeating ticker.
- Fonts: Inter and Space Grotesk are bundled under `apps/rain/assets/google_fonts/`, and runtime font fetching is off (no request to fonts.googleapis.com).
- Buttons get hover/focus/press overlays through a value-equal overlay property, so rebuilt themes stay equal and MaterialApp does not re-animate them.

## Loading And Startup States

- The splash mark keeps its loop phase across the three startup hand-offs, and the intro scale plays once per process.
- Phase captions appear after 600 ms ("Checking for updates", "Restoring your session", "Starting secure link"). Startup cross-fades into the app keyed by surface kind.
- The startup failure screen shows sanitized text (`rainUserFacingError`), offers Try again when a retry exists, and has Copy details.
- Force update shows a warning panel with installed/required chips. Account deletion shows the brand mark.
- Android 12+ native splash shows the Rain mark on `#061017` (values-v31). Pre-31 launch backgrounds stay plain `#061017`, as the release contract requires.
- Skeletons have message and friend-row shapes with a pulse. `RainDelayedReveal` hides loaders for quick loads. `RainBusyIndicator` replaces ad-hoc spinners.
- Transfer progress glides, waiting states are indeterminate, and completion swaps in a check. Calls show a connecting pulse around the peer glyph (warning colour while media reconnects).

## Sound Map Summary

- Full table with measured peak/RMS and throttle rules: `audit/ui/02-sound-map.md`.
- New generated cues: `camera_on`, `camera_off`, `route_change`, `request_inbound`, `request_accepted`, `transfer_complete`. Transfer completed/failed events play for the open conversation, deduped per transfer and spaced at least 1.5 s apart.
- Frequent cues are preloaded. Ringing loops fade out over 120 ms (app exit still stops immediately). Settings previews the volume.
- `sound_effects_assets_test.dart` keeps every cue group (chat/ui/state/alert) within 3 dB of its median. The total asset budget is 620 KB.

## Haptics

- `presentation/feedback/rain_haptics.dart`: Android only, behind the `Haptic feedback` setting (default on, `qa.settings.haptics`). Send = light; answer/decline/hang-up = medium; dock mic/camera and settings switches = selection. A setting that is still loading counts as off.

## Accessibility Rules

- Dock mic/camera/deafen controls announce label, On/Off value and toggled state.
- `RainPressable`: press scale, desktop hover overlay, visible focus ring, Enter/Space activation.
- New messages fade and slide in once. Messages present at first load do not animate.
- `test/ui_resilience_test.dart` checks for no overflow at 360x740 with 130 % text in both themes, and checks body and muted text contrast of at least 4.5:1.
- `showRainSnack`: one snackbar style with a severity icon, 4 s duration (6 s for errors).

## Open Items

- Handoff: expose a startup retry on `appStartupStateProvider` so the in-app failed phase can offer Try again.
- Handoff: emit a runtime event for transfer completion so cues can play when the chat is not open.
- Handoff: relax the pre-31 launch-background release contract if the Rain mark should show on Android 8-11.
- Fixed 2026-10-27 (`fix/button-font-family`): button, input-label and navigation label styles used the literal family `'Space Grotesk'`, which google_fonts never registers (it loads bundled weights as `SpaceGrotesk_<weight>`), so they fell back to the platform font. They now go through `RainTheme._grotesk` (`GoogleFonts.spaceGrotesk`). Only w500/w600/w700 are bundled, so never request w400 Space Grotesk (it would look for the missing `SpaceGrotesk-Regular.ttf`). `rain_theme_test.dart` pins the families.
- Owner device checks: Android 11/13 cold start, listen to every cue on speaker/headphones/Windows, feel haptics, reduced-motion walkthrough.

## Last Updated

2026-10-27 - UI/UX level-up program T0.1-T5.3 on `ui/level-up`.
