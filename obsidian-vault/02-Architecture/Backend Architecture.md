# Backend Architecture

## Backend Products

- Firebase Auth - account identity.
- Firebase Realtime Database - users, presence, friendships, blocks, signaling rooms, call rooms, locks, connection requests.
- Firebase Remote Config - update manifest and release policy.
- Cloud Functions - optional cleanup/guardrail code in repository, but Spark/free-tier constraints limit production dependency.

## Firebase RTDB Paths

- `users`
- `presence`
- `friendRequests`
- `outgoingFriendRequests`
- `friendships`
- `blocks`
- `blockedBy`
- `userSearch`
- `rooms`
- `activeVoicePairs`
- `activeVoiceUsers`
- `voiceCallInboxes`
- `voiceCalls`
- `connectionRequests`
- `connectionRequestOutboxes`
- `connectionRequestPairLocks`

## Backend Risks

- RTDB rules encode complex state-machine logic.
- Call lock creation uses multiple client-side writes and transactions.
- Permission-denied errors can be hard to classify without strong diagnostics.
- Spark/free-tier means no guaranteed server function enforcement unless rules cover it.

Related: [[Security Review]], [[Permissions Matrix]], [[Infrastructure Architecture]], [[Connection Request Notifications]].
