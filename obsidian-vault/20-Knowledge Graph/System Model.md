# System Model

Last updated: 2026-06-04

## Purpose

This note gives scenario-intelligence agents a compact model of Rain's core domains, critical flows, critical assets, and failure-sensitive areas.

Use it with [[State Graph]], [[Business Rule Graph]], [[Failure Graph]], [[Assumption Register]], [[Feature Map]], and [[Dependency Map]] before generating scenarios or test plans.

## Core Domains

- Identity: [[Authentication]]
- Friends: [[Friendship And Blocking]]
- Presence: [[Presence And Direct Connect]], [[Presence Management]]
- Chat: [[Peer Chat]]
- File Transfer: [[File Transfer]], [[Streaming Architecture]], [[Backpressure Strategy]]
- Voice Calls: [[Voice Calls]], [[Call State Machine]]
- Video Calls: [[Video Calls]], [[CallMediaCoordinator]]
- Notifications: [[Connection Request Notifications]]
- Diagnostics: [[Diagnostics And Logging]], [[Diagnostics Sanitization]]
- Update System: [[Version And Updates]], [[Release Gates]]

## Critical Flows

- Registration: create Firebase Auth user, create RTDB user, add search index, set presence, save Drift identity.
- Login: authenticate Firebase user, verify RTDB user ownership, save Drift identity only after backend proof.
- Friend Request: create request mirrors, accept/reject, update friendships, sync local friend state.
- Connection Establishment: validate friendship and presence, create signaling room, exchange SDP/ICE, open data channels.
- Chat Session: persist outgoing message, send over WebRTC, acknowledge, retry or queue on failure.
- File Transfer Session: validate relationship and transfer conflicts, persist transfer record, send metadata, stream chunks, finalize or cancel.
- Voice Call Session: validate friendship and fresh presence, claim call locks, create room/inbox, negotiate media, reconcile terminal state.
- Video Call Session: use voice-call signaling path plus video renderer/camera/media-mode ownership.
- Account Deletion: reauthenticate, shut down runtime best-effort, clean/tombstone RTDB data, delete Firebase Auth last, clear local session.

## Critical Assets

- User Identity: Firebase Auth uid, RTDB `users/{username}`, Drift `identity_table`.
- Friendship Graph: `friendships`, `friendRequests`, `outgoingFriendRequests`, local friend rows.
- Message Metadata: Drift messages, queued messages, sequence trackers.
- File Metadata: file transfer records, local received paths, transfer progress.
- Presence State: `presence/{username}` with uid, online, heartbeat, state, session id.
- Signaling State: peer rooms, voice call rooms, inboxes, active pair/user locks, ICE records.
- Remote Config Policy: release manifest, required/optional update policy, channel/platform metadata.
- Diagnostics Evidence: sanitized crash, runtime, call, Firebase, update, and export records.

## Failure-Sensitive Areas

- WebRTC negotiation: SDP/ICE order, stale offers, ICE restart, media setup, route selection.
- Presence synchronization: stale heartbeat, old session id, app close, network loss, raw online booleans.
- Offline request delivery: quota, confirmation, muted senders, stale receiver presence, RTDB/function mode differences.
- Call locking: stale user locks, pair locks, terminal rooms, missing inbox mirrors, caller/callee ownership.
- Diagnostics export: sanitizer coverage, Android SAF/content handles, fallback file creation.
- Update enforcement: stale Remote Config, build-number comparison, required update root gate.
- Account lifecycle: deleted/tombstoned backend identity, surviving Firebase Auth, local Drift cache, session generation.

## Scenario Generation Rule

For every critical flow:

1. Identify the involved domains.
2. Identify the critical assets read or mutated.
3. Read related assumptions in [[Assumption Register]].
4. Generate at least one scenario that violates each relevant assumption.
5. Trace downstream effects through [[Failure Graph]].
6. Convert high-impact gaps into tests, risks, debt, blockers, or roadmap work.

Related: [[Scenario Intelligence Agent]], [[Test Strategy]], [[Risk Register]], [[Technical Debt Register]].
