# Index Strategy

## Required Indexes

- `messages_peer_sent_seq_id_idx` on `messages(peer_id, sent_at, seq, id)`.
- `friends_display_name_idx` on `friends(display_name)`.
- `queued_messages_to_status_seq_sent_idx` on `queued_messages(to, status, seq, sent_at)`.
- `queued_messages_status_to_idx` on `queued_messages(status, to)`.
- `file_transfers_peer_created_idx` on `file_transfers(peer_id, created_at)`.
- `file_transfers_message_id_idx` on `file_transfers(message_id)`.
- `file_transfers_state_peer_idx` on `file_transfers(state, peer_id)`.

## Implementation

Implemented in Drift schema v6 on 2026-06-05.

Evidence:

- `packages/rain_core/lib/database/rain_database.dart` declares the indexes with `@TableIndex`.
- `packages/rain_core/lib/database/rain_database.g.dart` was regenerated through `dart run build_runner build`.
- `packages/rain_core/test/rain_database_test.dart` verifies new-schema index creation and v5-to-v6 index migration.

## Business Value

Keeps chat and friends responsive as users accumulate messages and transfers.

## Technical Value

Avoids full scans and sorts in watched queries.

Related: [[Database Scalability Epic]], [[Migration Plan]].
