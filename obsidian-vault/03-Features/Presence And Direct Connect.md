# Presence And Direct Connect

## Purpose

Show whether a peer is available and establish WebRTC data-channel connection.

## Business Value

Users need to know whether direct chat/file actions can work now.

## Technical Flow

- Presence is stored in RTDB `presence`.
- Runtime heartbeat interval is 10 seconds while foreground/running.
- UI freshness target has been treated around 30 seconds.
- Backend write freshness for calls/requests has used stricter RTDB rule checks.
- Data-peer signaling uses Firebase rooms.
- WebRTC data channels carry chat, control, and file traffic.

## Edge Cases

- App close should mark peer offline.
- Network loss is not manual disconnect.
- Manual disconnect blocks auto-recovery.
- Stale presence must not allow misleading Connect or Call actions.

## Known Issues

- Users reported peers staying online until both apps restart.
- Auto-recovery can still use stale presence internally.

## Testing Requirements

- Online to offline transition after app close.
- Manual disconnect does not reconnect.
- Network recovery reconnects only when intended.

Related: [[Peer Chat]], [[Connection Request Notifications]], [[Risk Register]].
