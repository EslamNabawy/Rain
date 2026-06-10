# Endpoints

## Firebase Auth

- Sign in by Rain username/password mapping.
- Register Rain username/password mapping.

## Firebase RTDB Paths

- `users/{username}`
- `presence/{username}`
- `friendRequests/{to}/{from}`
- `outgoingFriendRequests/{from}/{to}`
- `friendships/{username}/{friend}`
- `blocks/{blocker}/{blocked}`
- `blockedBy/{blocked}/{blocker}`
- `rooms/{roomId}`
- `voiceCalls/{callId}`
- `voiceCallInboxes/{username}/{callId}`
- `activeVoicePairs/{pairId}`
- `activeVoiceUsers/{username}`
- `connectionRequests/{username}/{requestId}`
- `connectionRequestOutboxes/{username}/{requestId}`
- `connectionRequestPairLocks/{pairKey}`

## Remote Config

- `rain_release_manifest_v1`
- legacy fallback: `min_required_version`
- legacy fallback: `update_url`

Related: [[Permissions Matrix]], [[Database Schema]].
