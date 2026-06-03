# Presence Management

## Current Model

- Foreground heartbeat around 10 seconds.
- Presence stored in RTDB `presence`.
- Session id and platform state exist.

## Target Rules

- Fresh backend presence is required for Connect and Call.
- Closed app means offline.
- Presence unknown blocks calls and offline request notifications.
- Auto-recovery must not bypass stale peer truth.

## Required Tests

- App close marks peer offline.
- Expired heartbeat marks stale/offline.
- Newer session id wins over old heartbeats.
- Recovery does not reconnect manually disconnected peers.

Related: [[Presence And Direct Connect]], [[Signaling Reliability Epic]].
