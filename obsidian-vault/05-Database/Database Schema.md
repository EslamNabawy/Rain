# Database Schema

Last updated: 2026-06-05

## Local Drift Tables

Current Drift schema version: 6.

### messages

- `id`
- `peerId`
- `content`
- `sentAt`
- `seq`
- `type`
- `status`
- `isOutgoing`

### friends

- `username`
- `displayName`
- `gender`
- `state`
- `addedAt`
- `lastOnlineAt`
- `online`
- `unreadCount`

### queued_messages

- `id`
- `to`
- `content`
- `sentAt`
- `seq`
- `status`

### file_transfers

- `id`
- `peerId`
- `messageId`
- `direction`
- `fileName`
- `fileSize`
- `mimeType`
- `localPath`
- `tempPath`
- `bytesTransferred`
- `state`
- `error`
- `createdAt`
- `updatedAt`

### connection_memory_table

- `peerId`
- `lastConnectedAt`
- `cachedIce`
- `fingerprint`
- `consecutiveFailures`

### identity_table

- `id`
- `username`
- `displayName`
- `createdAt`
- `gender`

### message_seq_tracker

- `peerId`
- `lastSeq`

## Secondary Indexes

- `messages_peer_sent_seq_id_idx` on `messages(peerId, sentAt, seq, id)`.
- `friends_display_name_idx` on `friends(displayName)`.
- `queued_messages_to_status_seq_sent_idx` on `queued_messages(to, status, seq, sentAt)`.
- `queued_messages_status_to_idx` on `queued_messages(status, to)`.
- `file_transfers_peer_created_idx` on `file_transfers(peerId, createdAt)`.
- `file_transfers_message_id_idx` on `file_transfers(messageId)`.
- `file_transfers_state_peer_idx` on `file_transfers(state, peerId)`.

## At-Rest Security

Decision: [[ADR-010]].

The local Drift/SQLite schema is not app-layer encrypted in the current implementation. `messages.content`, `queued_messages.content`, `file_transfers.fileName`, and `file_transfers.localPath` should be treated as plaintext local data. Product and release claims must not imply local database encryption unless the schema/opening path is changed through a future migration-tested encryption phase.

Related: [[Migrations]], [[Database Architecture]].
