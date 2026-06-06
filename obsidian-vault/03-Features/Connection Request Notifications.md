# Connection Request Notifications

## Purpose

Notify an offline peer that someone wants to connect.

## Business Value

Lets users request attention when direct online connection is not available.

## Technical Flow

- Direct Connect checks fresh backend presence.
- If peer is online, connect directly.
- If peer is offline/stale, ask confirmation before sending request notification.
- Unknown presence blocks direct actions until a backend snapshot is observed.
- Request creation uses RTDB paths and guardrails.
- Request limits should count only offline notification requests, not normal online connects.
- App-side RTDB request preflight uses the same 45 second freshness window that the Realtime Database rules use for online/offline receiver decisions.

## Dependencies

- RTDB `connectionRequests`
- RTDB `connectionRequestOutboxes`
- RTDB `connectionRequestPairLocks`
- Local notification abstraction
- Settings for mute/notification behavior

## Guardrails

- Confirmation required.
- Online peers cannot receive offline request notifications.
- Presence unknown blocks request.
- Every blocked action must show a user-facing message.
- Chat UI action availability must read `PeerConnectivitySnapshot.peerOnlineForAction`, not raw `friend.isOnline`.

## Known Issues

- Permission denied has been reported for request paths when rules/app payload diverge.
- Phase 1 local proof covers stale/unknown/fresh provider routing. Firebase rule/emulator proof for online receiver denial and request quota non-consumption remains Phase 2 work.

Related: [[Backend Architecture]], [[Permissions Matrix]], [[Risk Register]].
