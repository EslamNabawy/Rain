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

## Operation Budget Notes

- 2026-06-05 Phase 2 call-lock proof keeps voice-call setup in Spark-compatible RTDB paths: caller user lock, callee user lock, pair lock, then `voiceCalls` plus callee inbox.
- Stale-lock repair is intentionally one cleanup attempt plus one claim retry. It avoids loops that would amplify RTDB reads/writes under repeated false-busy failures.
- Denied malformed writes are proven by emulator tests to preserve existing lock, room, and inbox state, so invalid clients do not burn cleanup work by partially mutating call artifacts.
- Server-authoritative transactions use `applyLocally: false`; direct fallback cleanup re-reads before compare-delete, avoiding reliance on queued/offline transaction state surviving process restart.

Related: [[Rules Strategy]], [[Emulator Coverage]], [[Backend Architecture]].
