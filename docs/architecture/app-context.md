# Rain App Context

Status: reference context

Last analyzed: 2026-05-25

This document gives future agents and contributors enough context to work on
Rain without rediscovering the product, architecture, release rules, and current
quality risks from scratch.

## Product

Rain is a private peer-to-peer chat app for Android and Windows. It is centered
on accepted friends, direct conversation, file sharing, voice calls, and video
calls.

The product direction is calm, premium, minimal, and reliable. The user should
always understand:

- who they are talking to
- whether the peer is connected
- whether the route is direct or relay
- what call/file/message action is currently possible
- what went wrong and how to recover

## Supported Platforms

Current maintained targets:

- Android phone builds
- Windows desktop builds

Unsupported or not release-proven:

- macOS
- Linux
- web
- background mobile calling
- push-notification ringing
- group calling

## Monorepo Layout

```text
apps/rain/              Flutter Android/Windows app
packages/rain_core/     Drift storage, identity, friends, messages, files
packages/protocol_brain/ Firebase signaling, sessions, retry, voice signaling
packages/peer_core/     WebRTC data/media primitives and platform bridge
backend/firebase/       Realtime Database rules and cleanup functions
docs/                   Architecture, plans, QA, CI/CD docs
scripts/                Local automation and build helpers
final product/          User-facing local build outputs and archives
```

## Architecture Style

Rain is intentionally split into small layers:

```text
presentation widgets
  -> Riverpod state providers
  -> app runtime controllers/services
  -> rain_core/protocol_brain/peer_core packages
  -> Firebase, Drift, Flutter WebRTC, platform APIs
```

Guiding rules:

- UI stays in `apps/rain/lib/presentation`.
- Runtime orchestration stays in `apps/rain/lib/application/runtime`.
- Riverpod provider composition stays in `apps/rain/lib/application/state`.
- Local persistence rules stay in `packages/rain_core`.
- Signaling and session policy stay in `packages/protocol_brain`.
- Raw WebRTC and platform media work stays in `packages/peer_core`.
- Firebase backend rules/functions stay in `backend/firebase`.

## State Management

Rain uses Riverpod for app/UI state composition. Runtime controllers own side
effects and expose state through providers. Drift persists local app data.
Firebase owns remote auth, presence, friendship, signaling, and ephemeral call
coordination.

Important state categories:

- authentication and identity
- accepted friends and blocked users
- selected chat peer
- peer session state
- message streams
- file transfer view state
- voice/video call runtime state
- media device settings
- app sound settings
- diagnostics and crash data

## Backend And Data

Rain uses Firebase as the active remote backend:

- Firebase Auth for account identity
- Firebase Realtime Database for user search, presence, friendships, signaling,
  and ephemeral call state
- Firebase cleanup functions for stale ephemeral data

Rain also supports a noop/demo backend path for development surfaces. Production
release builds must not use demo signaling encryption keys.

Local data is stored with Drift:

- identity/profile data
- friends and relationship cache
- messages and sequence tracking
- offline outgoing queue
- file transfer records
- connection memory
- settings where applicable

## Core User Flows

### Auth

Users can register or sign in with username/password. Username input is
normalized. The Android keyboard must not cover active credential fields.

### Friendship

Users search for other users, send requests, accept/reject requests, unfriend,
and block/unblock users. Communication features are scoped to accepted friends.

### Chat

Accepted friends can connect and exchange messages over WebRTC data channels.
Messages have local persistence, ordering, ACK behavior, queueing, and recovery.

### File Transfer

Files are offered, accepted/rejected, chunked, transferred, completed, failed,
or cancelled over the file data channel. Calls take priority over new file
transfers.

### Voice Call

Voice calls use a fresh short-lived WebRTC media connection per call. Media is
not sent over data channels. Firebase call signaling carries encrypted SDP/ICE
and ephemeral call state. Only one active call is allowed globally.

### Video Call

Video builds on the same dedicated call media path. Remote video should be the
primary surface by default. Local video is a preview and can be swapped by user
intent. Camera controls must reflect real device capability.

## Connection Expectations

Connection behavior must be predictable:

- Manual connect should not be confused with automatic recovery.
- Manual disconnect should not trigger recovery loops.
- Remote app close should dispose remote/local session state.
- Peer busy must clear after failed, timed out, or ended calls.
- Direct and relay routes must be visible and diagnostic.
- Network loss should recover when appropriate and stop when user intent says
  stop.
- Repeated calls must work without app restart.

## Visual Identity

The active direction is Rain with a premium private-signal identity:

- dark ink surfaces
- cyan/mint accents
- signal mist texture
- Peer Core mark
- ripple halo states
- restrained motion
- no childish raindrops
- no mascot treatment
- no random glow blobs
- no diagonal stroke overlays on active UI

Ripple halo states should be component-level, static by default, and emit only
one short ripple on state changes. Reduced motion must show still halos.

## Sound Direction

The app sound direction should be rain/water themed, but mature and restrained.
Sound design must avoid:

- harsh ringtone loops
- repeated sound spam on message bursts
- pausing the user's phone music for short UI sounds where avoidable
- playing stale ringtone/ringback after call terminal state
- unbounded overlapping sound effects

Sound events should route through the central sound event router, not individual
widgets directly.

## Call UI Direction

The call UI has three main surfaces:

- expanded popup or centered call panel
- minimized top call manager bar
- fullscreen video surface

Rules:

- Do not show duplicate call controls in both popup and top bar.
- When popup is open, hide the top bar.
- When minimized, show the top manager bar.
- In fullscreen video, remote video is primary by default.
- The local preview is small and movable/swappable where supported.
- Respect safe areas and status bars on Android.
- Controls must match actual device capability.

## Media Device Expectations

Media device UI must be based on real device inventory:

- microphone list in settings
- connected wired/Bluetooth microphone availability
- selected app microphone persistence
- speaker/earpiece/Bluetooth output route options only when supported
- camera list for video
- flip camera only when multiple or switchable cameras exist

The app should degrade cleanly when a platform cannot expose a device option.

## Build And Release Context

Current branch policy from the active workflow:

- keep `dev` and `main`
- work is integrated into `dev`
- merge into `main` happens through PR

Release/build workflows exist under `.github/workflows`:

- `ci.yml`
- `main-merge-gate.yml`
- `build-artifacts.yml`
- `release.yml`

Production Android release builds require configured signing secrets. Missing
release secrets will fail production build workflow steps by design.

Android APK testing has used split builds for ABI-specific outputs such as:

- armeabi-v7a
- arm64-v8a

## Validation Rules

Normal code changes should run:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

Do not run platform builds unless specifically asked.

Docs-only changes should at least pass:

```powershell
git diff --check
```

Release-sensitive call/connectivity changes also need manual device validation.
Automated tests cannot fully prove Android/Windows WebRTC behavior.

## Highest Risk Areas

| Area | Risk |
| --- | --- |
| Call busy locks | Failed calls can leave stale pair locks and block the next call |
| Media disposal | Stale WebRTC callbacks can hit disposed transceivers/renderers |
| Manual disconnect | A local disconnect can accidentally trigger recovery loops |
| Network weakness | Short transient disconnects can be misclassified as terminal call failure |
| Android permissions | Missing mic/camera permission blocks call establishment |
| Device routing | Bluetooth/speaker controls can show unsupported routes |
| UI duplication | Call popup and manager bar can show conflicting controls |
| Sound effects | Repeated playback can sound broken or interfere with other audio |
| Splash ownership | Native/old splash and Flutter splash can both appear if not coordinated |
| Release secrets | Production builds fail without signing/encryption secrets |

## Contributor Rules

- Keep changes scoped to maintained app/packages.
- Do not reintroduce obsolete sample apps or root-level scaffolding.
- Do not hardcode secrets or local credentials.
- Do not delete user work or stashes without explicit request.
- Commit meaningful changes.
- Prefer simple runtime ownership over clever widget-local side effects.
- Keep UI state derived from runtime truth sources.
- Keep full technical error data in diagnostics even when UI shows a short
  friendly message.
