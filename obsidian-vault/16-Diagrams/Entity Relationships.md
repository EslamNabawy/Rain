# Entity Relationships

```mermaid
erDiagram
  USERS ||--o{ FRIENDSHIPS : owns
  USERS ||--o{ PRESENCE : publishes
  USERS ||--o{ VOICE_CALLS : caller
  USERS ||--o{ VOICE_CALLS : callee
  VOICE_CALLS ||--|| ACTIVE_VOICE_PAIRS : locks
  VOICE_CALLS ||--o{ ACTIVE_VOICE_USERS : locks
  VOICE_CALLS ||--o{ VOICE_CALL_INBOXES : notifies
  FRIENDS ||--o{ MESSAGES : has
  FRIENDS ||--o{ FILE_TRANSFERS : has
```

## Local Entities

- `messages`
- `friends`
- `queued_messages`
- `file_transfers`
- `connection_memory_table`
- `identity_table`
- `message_seq_tracker`

## Remote Entities

- `users`
- `presence`
- `friendships`
- `rooms`
- `voiceCalls`
- `voiceCallInboxes`
- `activeVoicePairs`
- `activeVoiceUsers`
- `connectionRequests`

Related: [[Database Schema]], [[Backend Architecture]].
