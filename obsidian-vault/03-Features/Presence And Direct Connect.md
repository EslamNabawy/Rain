# Presence And Direct Connect

## Purpose

Show whether a peer is available and establish WebRTC data-channel connection.

## Business Value

Users need to know whether direct chat/file actions can work now.

## Technical Flow

- Presence is stored in RTDB `presence`.
- Runtime heartbeat interval is 10 seconds while foreground/running.
- UI freshness target has been treated around 30 seconds.
- Runtime now re-resolves backend presence with a 30 second `lastHeartbeat` freshness window before seeding local online state, direct Connect, connection-request routing, or call start.
- Runtime presence snapshots include session id, session start time, and state.
- A presence row with `state: offline` is offline even when raw `online` is still true.
- The chat Connect action now uses the runtime fresh-presence resolver instead of reading raw `BackendIdentity.online`.
- Network auto-recovery preflights fresh backend presence and skips stale/offline peers instead of reconnecting through stale state.
- Presence expiry records a terminal `presenceExpired` intent until the next successful explicit reconnect.
- Backend write freshness for calls/requests has used stricter RTDB rule checks.
- Data-peer signaling uses Firebase rooms.
- WebRTC data channels carry chat, control, and file traffic.
- UI peer status is projected through `ConnectionDiagnostics` and `peerConnectionDiagnosticsProvider` from data session, presence freshness, manual disconnect intent, connection coordinator state, and active call state.
- An open data lane with stale presence is shown as `Data lane only`, not `Connected`; messaging may still be allowed through `canSendData`.
- Manual disconnect and failed/recovering call state take precedence over raw connected data-session status in peer UI.

## Edge Cases

- App close should mark peer offline.
- Network loss is not manual disconnect.
- Manual disconnect blocks auto-recovery.
- Stale presence must not allow misleading Connect or Call actions.
- Stale raw-online backend records are treated as offline and logged for diagnostics.
- Raw `BackendIdentity.online` must not be used directly by UI action routing.
- Stale presence plus an open data lane must not create false connected UI.
- One peer showing failed/recovering call state while the data lane remains open must not split chat/link/call status surfaces.

## Known Issues

- Users reported peers staying online until both apps restart.
- Full app-close runtime regression coverage must use the app-package test wrapper, `scripts/run_rain_app_test.ps1`, so Windows Drift/sqlite native assets resolve from `apps/rain`.

## Testing Requirements

- Online to offline transition after app close.
- Manual disconnect does not reconnect.
- Network recovery reconnects only when intended.
- Projection precedence tests for failed, manual disconnect, recovering, out-of-sync, connected, and data-lane-only states.

Related: [[Peer Chat]], [[Connection Request Notifications]], [[Risk Register]].
