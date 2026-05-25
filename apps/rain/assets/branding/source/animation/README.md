# Rain Peer Core Animation Assets

This folder prepares the Peer Core logo for future animation work.

Use `peer_core_animatable.svg` when the animation tool can target named SVG groups. Use `layers/*.svg` when the runtime prefers stacking independent full-viewBox assets.

Important rules:

- Keep common UI action icons separate from this logo animation system.
- Animate waves only for startup, connect, send, and call state events.
- Keep node movement small unless connectors are redrawn from live node positions.
- Respect reduced motion by hiding waves and freezing nodes.
- Do not animate the mark continuously in chat.

Layer pivots, file names, and timing hints are documented in `peer_core_animation_manifest.json`.
