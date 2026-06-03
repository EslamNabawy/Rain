# Migrations

Current Drift schema version observed: 5.

## Known Migration History

- v2 added `identity_table.gender`.
- v3 added `friends.online`.
- v4 added `friends.gender`.
- v5 added `file_transfers`.

## Required Future Migration

Add secondary indexes:

- `messages(peer_id, sent_at, seq)`
- `friends(display_name)`
- `file_transfers(peer_id, created_at)`
- `file_transfers(state)`
- `queued_messages(to, status, sent_at)`

## Migration Rules

- Never delete local user data without an explicit versioned migration.
- Test legacy-to-current migration.
- Test generated Drift schema output.

Related: [[Database Schema]], [[Technical Debt]].
