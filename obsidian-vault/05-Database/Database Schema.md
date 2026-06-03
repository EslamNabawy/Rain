# Database Schema

## Local Drift Tables

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

Related: [[Migrations]], [[Database Architecture]].
