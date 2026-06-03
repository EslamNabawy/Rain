# Presence Management

## Current Model

Detailed implementation planning: [[Presence Management Refactor Plan]].

- Foreground heartbeat around 10 seconds.
- Presence stored in RTDB `presence`.
- Session id and platform state exist.
- Runtime action gates resolve backend presence from both `online` and `lastHeartbeat`.
- The app-side freshness window is 30 seconds for friend seeding, direct Connect, offline request routing, and voice/video call start.
- Stale backend records with raw `online: true` are treated as offline and recorded as `backend_presence_stale_resolved_offline`.

## Target Rules

- Fresh backend presence is required for Connect and Call.
- Closed app means offline.
- Presence unknown blocks calls and offline request notifications.
- Auto-recovery must not bypass stale peer truth.

## Required Tests

- App close marks peer offline.
- Expired heartbeat marks stale/offline.
- Stale backend `online: true` cannot seed local friend state as online.
- Stale backend `online: true` cannot start direct Connect or voice/video call setup.
- Newer session id wins over old heartbeats.
- Recovery does not reconnect manually disconnected peers.

Related: [[Presence And Direct Connect]], [[Signaling Reliability Epic]].
