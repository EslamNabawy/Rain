# Business Rule Graph

Last updated: 2026-06-04

## Purpose

Track core business and product rules that scenario-intelligence agents must treat as invariants.

Use this note to generate tests that prove a rule still holds when assumptions fail.

## Identity Rules

- A username maps to one Firebase Auth uid through RTDB `users/{username}`.
- Local Drift identity is a cached session candidate, not authenticated truth.
- Login must prove backend identity exists and belongs to the current uid.
- Deleted or tombstoned accounts must not be restored from local cache or surviving Auth.
- Account deletion requires password reauthentication before destructive backend work starts.

Related: [[Authentication]], [[State Graph]].

## Friendship Rules

- Only accepted friends can chat, connect, transfer files, or call.
- Blocking removes or prevents friend/request interaction in both directions.
- Self friendship and self friend requests are invalid.
- Relationship changes must close or invalidate active peer sessions where needed.

Related: [[Friendship And Blocking]], [[Permissions Matrix]].

## Presence Rules

- Fresh presence requires online flag, fresh heartbeat, valid session ownership, and online state.
- Stale presence must be treated as offline for user-facing connect/call/request routing.
- Online direct connect must not consume offline notification quota.
- Closed app currently means offline for call/ring reliability.

Related: [[Presence Management]], [[Connection Request Notifications]].

## Messaging Rules

- Messages are local-first and must be stored before ack is sent.
- Unknown late incoming messages should be stored before ack to avoid false delivery.
- Offline queued messages remain queued or failed; they should not disappear silently.
- Message content must not be exported in diagnostics.

Related: [[Peer Chat]], [[Diagnostics Sanitization]].

## File Transfer Rules

- File metadata and chunks travel over WebRTC data channels, not Firebase.
- File transfers must preserve terminal state and cleanup behavior on cancel/failure.
- Large transfer behavior must stay bounded by chunk and backpressure policy.
- File bytes must not be logged or exported in diagnostics.

Related: [[File Transfer]], [[Backpressure Strategy]].

## Call Rules

- Firebase carries signaling only; media packets do not pass through Firebase.
- One active call per user/pair is enforced through call locks.
- Terminal Firebase room state wins over late local or remote frames.
- Late terminal races should be diagnostics events, not crash records.
- Voice and video share the call signaling path but differ in media/rendering requirements.

Related: [[Voice Calls]], [[Video Calls]], [[Call State Machine]], [[Lease Management]].

## Update Rules

- Required update blocks startup before protected app content.
- Optional update is visible but dismissible according to app policy.
- Remote Config must be deployed after each release for old clients to discover updates.
- Stale Remote Config policy is not "current."

Related: [[Version And Updates]], [[Release Gates]].

## Diagnostics Rules

- Diagnostics are local and sanitized.
- Do not log raw passwords, tokens, SDP, ICE candidates, ciphertext, message text, or file bytes.
- Expected async races should be structured events unless they break user-visible behavior.
- Export paths must distinguish real filesystem paths from platform-managed handles.

Related: [[Diagnostics And Logging]], [[Diagnostics Sanitization]].

## Scenario Generation Rule

For each rule:

1. Identify the assets protected by the rule.
2. Identify the assumptions the rule depends on.
3. Generate one scenario where each assumption fails.
4. Verify whether the rule fails closed, recovers, or leaks state.
5. Record any unproven rule in [[Assumption Register]], [[Risk Register]], or [[Technical Debt Register]].

Related: [[Scenario Intelligence Agent]], [[System Model]], [[Failure Graph]].
