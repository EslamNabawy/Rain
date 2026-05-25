# Rain Branding Source Assets

This folder contains the editable source assets for the Rain `Signal Mist` identity.

## Source Files

- `peer_core_mark.svg` - full Peer Core mark.
- `peer_core_mark_tiny.svg` - simplified tiny-size mark.
- `peer_core_mark_mono.svg` - monochrome mark using `currentColor`.
- `peer_core_app_icon.svg` - app icon source.
- `peer_core_splash_lockup.svg` - splash lockup with mark, name, and tagline.
- `rain_streak_treatment.svg` - Rain Streak active-state treatment reference.
- `peer_core_preview_sheet.svg` - overview sheet.
- `animation/peer_core_animatable.svg` - named SVG groups for animation.
- `animation/layers/*.svg` - independent full-viewBox layer files for stacked animation.
- `animation/peer_core_animation_manifest.json` - pivots, timing, and motion hints.

## Generated Files

Generated PNGs are written to `../generated/`.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File apps/rain/assets/branding/source/render_peer_core_assets.ps1
```

Do not hand-edit generated PNGs. Update the SVG/source geometry or generator, then regenerate.

## Runtime Note

Source files and generator scripts are not intended to ship in production builds. When these assets are wired into the app, narrow `pubspec.yaml` asset includes to the specific generated/runtime assets needed by Flutter.
