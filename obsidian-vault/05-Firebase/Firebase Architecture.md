# Firebase Architecture

## Products

- Firebase Auth
- Realtime Database
- Remote Config
- Optional Cloud Functions code in repo, but production direction must respect Spark/free-tier constraints.

## Key RTDB Paths

- `users`
- `presence`
- `friendships`
- `rooms`
- `voiceCalls`
- `voiceCallInboxes`
- `activeVoicePairs`
- `activeVoiceUsers`
- `connectionRequests`
- `connectionRequestOutboxes`
- `connectionRequestPairLocks`

Related: [[Rules Strategy]], [[Emulator Coverage]], [[Backend Architecture]].
