# Presence Management

## Current Model

Detailed implementation planning: [[Presence Management Refactor Plan]].

- Foreground heartbeat around 10 seconds.
- Presence stored in RTDB `presence`.
- Session id and platform state exist.
- Runtime action gates resolve backend presence from both `online` and `lastHeartbeat`.
- Backend identity snapshots also carry presence `sessionId`, `startedAt`, and `state` for diagnostics and stale-session reasoning.
- The app-side freshness window is 30 seconds for friend seeding, direct Connect, chat action availability, and voice/video call start.
- RTDB offline connection-request preflight uses the 45 second rules freshness window so app decisions align with `database.rules.json`.
- Stale backend records with raw `online: true` are treated as offline and recorded as `backend_presence_stale_resolved_offline`.
- Records whose presence `state` is not `online` are treated as offline even if raw `online` is true.
- Chat Connect, runtime Connect, connection-request routing, voice/video call start, and network auto-recovery use the shared runtime fresh-presence resolver or authoritative `PeerConnectivitySnapshot`.
- `friend.isOnline` is display state only for chat actions; action authority comes from runtime-backed peer connectivity snapshots.
- Auto-recovery removes stale/offline peers from the recoverable set and records `PeerDisconnectIntent.presenceExpired` instead of reconnecting through stale presence.
- `presenceExpired` is retained as a terminal peer intent until a later successful explicit reconnect, so UI/diagnostics can distinguish peer-close from transient transport loss.

## Target Rules

- Fresh backend presence is required for Connect and Call.
- Closed app means offline.
- Presence unknown blocks calls and offline request notifications.
- Auto-recovery must not bypass stale peer truth.
- UI components must not read raw `BackendIdentity.online` directly for user actions.

## Required Tests

- App close marks peer offline.
- Expired heartbeat marks stale/offline.
- Stale backend `online: true` cannot seed local friend state as online.
- Stale backend `online: true` cannot start direct Connect or voice/video call setup.
- Local `friend.isOnline: true` without fresh backend presence cannot enable chat panel direct actions.
- Stale backend presence routes offline-request preflight instead of direct actions.
- Presence `state: offline` overrides raw `online: true`.
- Newer session id wins over old heartbeats.
- Recovery does not reconnect manually disconnected peers.
- Recovery does not reconnect stale/offline peers.
- Local validation note: isolated app tests that touch Drift/SQLite must run through `scripts/run_rain_app_test.ps1` or from `apps/rain`, not from the repository root with a root-relative path.

Related: [[Presence And Direct Connect]], [[Signaling Reliability Epic]].
