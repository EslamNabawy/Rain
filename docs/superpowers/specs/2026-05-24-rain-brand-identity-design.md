# Rain Brand Identity Design

## Final Brief

Rain needs a creative, minimal, premium identity for a private peer-to-peer chat app. The brand should reference rain through hints only: mist, signal traces, ripple/wave emission, wet highlights, and calm motion. It should not become a weather app, a cute illustration system, or a decorative marketing shell.

The maintained app targets Android and Windows first. Brand work must improve the existing Flutter app surfaces without changing backend direction or adding unnecessary runtime dependencies.

## Locked Direction

Name: Signal Mist

Rain should feel like a quiet private signal between trusted peers. The UI should remain compact, operational, and readable. Brand expression belongs in the shell, splash, state surfaces, connection feedback, motion, and primary active states.

Avoid:

- literal rain scenes
- mascot or cartoon-style icons
- decorative weather illustrations
- custom pictograms for every action
- always-on animation
- loading bars on splash
- glow blobs as the default background treatment

## Logo System

Primary mark: Peer Core

The logo is a dot/ripple mark, not a droplet. It uses a circular signal ring with three small peer nodes inside it. The full-size mark shows the peer-node triangle. Tiny-size variants simplify to a ring plus a core dot so the icon remains legible at 16-24 px.

Required variants:

- full-color app mark
- monochrome mark
- tiny simplified mark
- wordmark lockup: mark + `Rain`
- splash lockup: mark + `Rain` + short promise
- platform icon exports for Android, Windows, Linux, and macOS

Launcher icons may use OS-required rounded-square or adaptive shapes, but the internal mark remains circular.

## Splash And Loading

Splash uses:

- Peer Core mark
- `Rain`
- short supporting line: `Private peer link`
- no loading bar

The splash mark may emit 1-3 soft circular waves during startup. Motion must be brief and restrained. If animation is disabled or reduced motion is requested, the static mark must still look complete.

General loading states should not use full-screen spinners unless there is no content context. Prefer rain-streak skeleton rows for lists and panels, with optional small pulse dots for short loading moments.

## In-App Icons

Normal action icons should stay mature and recognizable. Do not create a full custom icon set.

Use a Material Symbols Rounded-style icon language for common actions:

- chat
- search
- settings
- send
- attach file
- call
- microphone
- volume
- close
- retry
- block
- logout

Rain treatment applies only to active or stateful surfaces:

- active navigation item
- primary send/action button
- direct, relay, connecting, disconnected status chips
- active call controls
- selected settings option

Locked treatment: Rain Streak Active States

Selected/primary/state surfaces get a subtle diagonal rain-streak overlay. Neutral icons stay plain. This keeps the app rainy without turning icons into childish drawings.

## Empty, Loading, And Error States

Locked state system: Mist State Cards

Empty and error states use calm centered cards with short text and optional action. Loading states use rain-streak skeletons and minimal pulse dots.

State principles:

- No illustrations.
- No mascots.
- No long raw error text in normal UI.
- Empty states should tell the user what to do next.
- Error states should be recoverable when there is a recovery path.
- Loading states should preserve layout and avoid jarring full-screen changes.

Examples:

- `No friends yet` + `Find someone by username to start a private link.`
- `No messages yet` + `Start the first message when the link is ready.`
- `Find failed` + `Connection dropped. Try again when Rain is online.`
- `Call failed` + `Call media could not connect. Try again.`

## Color System

Locked palette: Ink, Mist, Mint

Dark base:

- Ink: `#061017`
- Deep surface: `#0A1E26`
- Raised surface: `#11222B`
- Quiet line: `#28424D`

Brand and states:

- Mist cyan: `#7DEBFF`
- Primary cyan: `#46C6D6`
- Peer mint: `#2DD4A3`
- Signal green: `#50C878`
- Warning amber: `#FFBF00`
- Error coral: `#FF6B6B`

Light mode remains cool and quiet:

- Background: `#F5F9FB`
- Surface: `#FCFEFF`
- Surface line: `#C9D8DF`
- Primary: `#086B78`
- Secondary: `#16714B`
- Amber: `#8A5A00`

Accent rules:

- Cyan is brand/action.
- Mint/green is healthy peer or direct connection.
- Amber is waiting/warning.
- Coral/error is failed or destructive.
- Do not flood the UI with cyan or mint.

## Typography

Locked stack:

- `Space Grotesk` for brand, titles, labels, buttons, and compact status text.
- `Inter` for body copy, chat text, settings content, and error messages.

Do not add a third app font. If release determinism becomes a concern, bundle fonts as assets instead of depending on runtime fetching behavior.

## Motion

Motion should feel like signal feedback, not decoration.

Allowed:

- event-bound logo wave emission
- short ripple on connect/send/call state changes
- page transitions already in `RainMotion`
- short status pulse for active connecting/loading states

Avoid:

- always-on rain loops
- decorative background animation in chat
- wave effects on every tap
- slow theatrical transitions

Suggested timing:

- quick feedback: 110 ms
- standard state transition: 150 ms
- slow emphasis: 220 ms

Respect reduced motion.

## Sound

Sound should support the same identity but stay operational.

Direction:

- short glass, mist, and soft-tap UI cues
- soft call tones
- sparse warning sounds
- no ambient rain beds
- no sounds that compete with voice-call audio

Existing app sound events can be mapped into this identity later. Sound changes require real Android and Windows checks, especially during active calls.

## Implementation Surfaces

Brand changes should be applied in phases:

1. Brand foundations
   - logo source assets
   - platform icon exports
   - color token cleanup
   - typography rules

2. Shell and startup
   - splash without loading bar
   - Peer Core wave emission
   - Rain backdrop replacing glow-blob feel with restrained mist/signal traces
   - header logo replacement

3. State surfaces
   - reusable Mist State Card
   - rain-streak skeleton loading rows
   - consistent error/empty copy

4. Icon and control treatment
   - Material Symbols Rounded-style action icons
   - Rain Streak overlay for active/primary/state surfaces only
   - branded direct/relay/disconnected status glyphs

5. Conversation and calls
   - chat empty state
   - connection banner/chips
   - file-transfer states
   - call overlay status and controls

6. Release polish
   - app icons per platform
   - README/app metadata visuals
   - screenshots
   - QA checklist

## Acceptance Criteria

- Logo remains recognizable at 16, 24, 48, 192, and 1024 px.
- Tiny logo variant does not depend on three-node detail.
- Splash has no loading bar.
- Rain is suggested through mist, streaks, ripples, and signal behavior without literal weather scenes.
- Common action icons remain instantly recognizable.
- Rain Streak treatment appears only on active/primary/state surfaces.
- Empty/error states use short actionable copy.
- Loading states preserve layout and avoid full-screen disruption when context exists.
- Dark and light themes meet contrast requirements for text, chips, buttons, and errors.
- Android small screens remain usable with keyboard open.
- Windows layouts remain dense and mouse-friendly.
- Motion is event-bound and respects reduced motion.
- Sound changes do not interfere with active calls.

## Risks And Tradeoffs

- A Peer Core logo can become busy at small sizes. Mitigation: simplified tiny variant.
- Rain Streak treatment can become gimmicky if overused. Mitigation: active/primary/state surfaces only.
- Mist/glass surfaces can reduce contrast. Mitigation: validate text, icon, and disabled states in dark and light mode.
- Custom state components can sprawl. Mitigation: one reusable state-card component and one skeleton loading pattern.
- Font dependence can affect deterministic release builds. Mitigation: bundle font assets later if needed.
- Sound identity needs device validation, not just desktop playback.

## Deferred Decisions

- Exact final SVG geometry for Peer Core.
- Whether to bundle fonts as app assets.
- Exact platform icon generation tooling.
- Final sound asset replacement set.
- Whether to apply glass-style surfaces broadly or only to splash/call/status areas.
