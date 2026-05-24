# Rain App Rebrand Phased Rollout Spec

## Purpose

This spec converts the Rain brand identity work into an implementation rollout for the Flutter app. It builds on:

- `docs/superpowers/specs/2026-05-24-rain-brand-identity-design.md`
- `apps/rain/assets/branding/source/`
- `apps/rain/assets/branding/generated/`
- `apps/rain/assets/branding/source/animation/`

The goal is to rebrand the maintained Rain app with the locked `Signal Mist` direction while keeping the app practical, readable, and production-safe.

## Current Asset Pack

Static source assets:

- `apps/rain/assets/branding/source/peer_core_mark.svg`
- `apps/rain/assets/branding/source/peer_core_mark_tiny.svg`
- `apps/rain/assets/branding/source/peer_core_mark_mono.svg`
- `apps/rain/assets/branding/source/peer_core_app_icon.svg`
- `apps/rain/assets/branding/source/peer_core_splash_lockup.svg`
- `apps/rain/assets/branding/source/rain_streak_treatment.svg`
- `apps/rain/assets/branding/source/peer_core_preview_sheet.svg`

Animation-ready source assets:

- `apps/rain/assets/branding/source/animation/peer_core_animatable.svg`
- `apps/rain/assets/branding/source/animation/peer_core_animation_manifest.json`
- `apps/rain/assets/branding/source/animation/layers/app_icon_shell.svg`
- `apps/rain/assets/branding/source/animation/layers/rain_streaks.svg`
- `apps/rain/assets/branding/source/animation/layers/wave_inner.svg`
- `apps/rain/assets/branding/source/animation/layers/wave_middle.svg`
- `apps/rain/assets/branding/source/animation/layers/wave_outer.svg`
- `apps/rain/assets/branding/source/animation/layers/ring.svg`
- `apps/rain/assets/branding/source/animation/layers/link_node_a_node_b.svg`
- `apps/rain/assets/branding/source/animation/layers/link_node_b_node_c.svg`
- `apps/rain/assets/branding/source/animation/layers/link_node_c_node_a.svg`
- `apps/rain/assets/branding/source/animation/layers/node_a.svg`
- `apps/rain/assets/branding/source/animation/layers/node_b.svg`
- `apps/rain/assets/branding/source/animation/layers/node_c.svg`

Generated preview/runtime candidate assets:

- `apps/rain/assets/branding/generated/peer_core_app_icon_1024.png`
- `apps/rain/assets/branding/generated/peer_core_app_icon_512.png`
- `apps/rain/assets/branding/generated/peer_core_app_icon_256.png`
- `apps/rain/assets/branding/generated/peer_core_app_icon_192.png`
- `apps/rain/assets/branding/generated/peer_core_mark_1024.png`
- `apps/rain/assets/branding/generated/peer_core_mark_192.png`
- `apps/rain/assets/branding/generated/peer_core_mark_48.png`
- `apps/rain/assets/branding/generated/peer_core_mark_24.png`
- `apps/rain/assets/branding/generated/peer_core_mark_16.png`
- `apps/rain/assets/branding/generated/peer_core_mark_tiny_192.png`
- `apps/rain/assets/branding/generated/peer_core_mark_tiny_48.png`
- `apps/rain/assets/branding/generated/peer_core_mark_tiny_24.png`
- `apps/rain/assets/branding/generated/peer_core_mark_tiny_16.png`
- `apps/rain/assets/branding/generated/peer_core_preview_sheet.png`
- `apps/rain/assets/branding/generated/peer_core_size_check.png`

The generator is:

```powershell
powershell -ExecutionPolicy Bypass -File apps/rain/assets/branding/source/render_peer_core_assets.ps1
```

## Locked Brand Decisions

- Direction: `Signal Mist`
- Logo: `Peer Core`, dot/ripple mark with peer-node triangle
- Tiny logo: simplified ring plus core dot
- Splash: mark + `Rain` + `Private peer link`; no loading bar
- Motion: event-bound wave emission only
- Icons: mature action icons stay recognizable
- Rainy icon treatment: `Rain Streak Active States`
- Empty/loading/error: `Mist State Cards`
- Palette: `Ink, Mist, Mint`
- Typography: `Space Grotesk` + `Inter`

## Phases

### Phase 0: Asset Hygiene And Runtime Boundaries

Create a clear separation between editable source assets and Flutter runtime assets.

Requirements:

- Keep `apps/rain/assets/branding/source/` as editable design source.
- Keep `apps/rain/assets/branding/generated/` as generated previews and PNG runtime candidates.
- Create a runtime layer asset folder only if Flutter needs stacked SVG animation layers.
- Narrow `apps/rain/pubspec.yaml` so source scripts, manifests, and preview-only files are not bundled in production.
- Add a Dart asset registry so all UI code references one source of truth.

### Phase 1: Brand Foundation In Flutter

Add runtime primitives:

- `RainBrandAssets`
- `RainPeerCoreMark`
- `RainPeerCoreAnimatedMark`
- `RainStreakSurface`
- `RainMistBackdrop`

Requirements:

- Static rendering must work even if animation is disabled.
- Reduced-motion mode must hide waves and freeze nodes.
- The app must not depend on source design files at runtime.

### Phase 2: Shell And Startup

Apply the identity to first-contact surfaces:

- splash screen
- startup failure screen
- home shell header mark
- app backdrop

Requirements:

- Remove splash loading bar.
- Replace current water/drop fallback with Peer Core.
- Replace glow-blob backdrop feel with restrained mist/signal traces.
- Keep compact Android and Windows layout behavior unchanged.

### Phase 3: Empty, Loading, And Error States

Introduce reusable state surfaces:

- Mist State Card
- Rain Streak skeleton rows
- compact inline state variant for settings rows

Apply to:

- friends empty/error/loading
- chat empty/error/loading
- search empty/error/loading
- root startup error/loading
- settings async row errors

Requirements:

- No mascots or illustrations.
- No raw long errors in normal UI where a human-readable message exists.
- Every recoverable error has an action when a recovery action exists.

### Phase 4: In-App Icon And Active-State Treatment

Keep action icons familiar; add Rain Streak only to active/primary/state surfaces.

Apply to:

- active bottom navigation item
- active navigation rail item
- primary send button
- direct/relay/connecting/disconnected chips
- active call controls
- selected settings option

Requirements:

- Do not create a custom icon set for common actions.
- Neutral icons remain plain.
- Rain Streak overlay never reduces icon contrast below accessibility needs.

### Phase 5: Conversation, File Transfer, And Calls

Apply the brand system to user-facing workflows:

- chat empty state
- connection banner/chips
- file transfer progress and failed states
- voice/video call overlay status
- call failed/retry surface

Requirements:

- Chat remains usable during active calls.
- File transfer states stay clear and operational.
- Call controls remain obvious under stress.
- Motion is event-bound and does not loop in chat.

### Phase 6: Platform And Release Polish

Prepare platform assets and release materials after the in-app identity is accepted.

Targets:

- Android launcher icons
- Windows `app_icon.ico`
- Linux `app_icon.png`
- macOS app icon set
- README/app metadata visuals
- screenshot set

Requirements:

- Do not replace platform icons until the Peer Core mark is approved in-app.
- Validate icon legibility at 16, 24, 48, 192, and 1024 px.
- Use a repeatable generator or documented manual export path for every platform output.

## Validation

Normal code validation:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

Visual validation:

- inspect `peer_core_preview_sheet.png`
- inspect `peer_core_size_check.png`
- run the app on Windows
- inspect Android small-screen layouts when Android tooling is available

Manual release validation remains required for call/audio behavior.

## Non-Goals

- No backend changes.
- No new runtime backend.
- No full custom in-app icon set.
- No platform builds unless explicitly requested.
- No always-on decorative animation.
- No landing page or marketing redesign.
