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

## Edge Cases

- App close should mark peer offline.
- Network loss is not manual disconnect.
- Manual disconnect blocks auto-recovery.
- Stale presence must not allow misleading Connect or Call actions.
- Stale raw-online backend records are treated as offline and logged for diagnostics.
- Raw `BackendIdentity.online` must not be used directly by UI action routing.

## Known Issues

- Users reported peers staying online until both apps restart.
- Full app-close runtime regression coverage still needs CI or a fixed local Drift/sqlite test harness because the local Windows `friend_flow_test.dart` process fails before test logic on sqlite native asset loading.

## Testing Requirements

- Online to offline transition after app close.
- Manual disconnect does not reconnect.
- Network recovery reconnects only when intended.

Related: [[Peer Chat]], [[Connection Request Notifications]], [[Risk Register]].
