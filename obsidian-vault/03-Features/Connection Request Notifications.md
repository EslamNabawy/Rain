# Connection Request Notifications

## Purpose

Notify an offline peer that someone wants to connect.

## Business Value

Lets users request attention when direct online connection is not available.

## Technical Flow

- Direct Connect checks fresh backend presence.
- If peer is online, connect directly.
- If peer is offline/stale, ask confirmation before sending request notification.
- Request creation uses RTDB paths and guardrails.
- Request limits should count only offline notification requests, not normal online connects.

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

## Known Issues

- Permission denied has been reported for request paths when rules/app payload diverge.

Related: [[Backend Architecture]], [[Permissions Matrix]], [[Risk Register]].
