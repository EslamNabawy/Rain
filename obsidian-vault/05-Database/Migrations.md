# Migrations

Current Drift schema version observed: 6.

## Known Migration History

- v2 added `identity_table.gender`.
- v3 added `friends.online`.
- v4 added `friends.gender`.
- v5 added `file_transfers`.
- v6 added secondary indexes for messages, friends, queued messages, and file transfers.

## Implemented v6 Index Migration

- `messages_peer_sent_seq_id_idx`
- `friends_display_name_idx`
- `queued_messages_to_status_seq_sent_idx`
- `queued_messages_status_to_idx`
- `file_transfers_peer_created_idx`
- `file_transfers_message_id_idx`
- `file_transfers_state_peer_idx`

Migration proof is in `packages/rain_core/test/rain_database_test.dart`.

## Migration Rules

- Never delete local user data without an explicit versioned migration.
- Test legacy-to-current migration.
- Test generated Drift schema output.

Related: [[Database Schema]], [[Technical Debt]].
