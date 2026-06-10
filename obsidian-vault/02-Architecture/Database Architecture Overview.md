# Database Architecture Overview

This architecture overview captures the high-level database risks discovered during audit. The canonical database architecture note is [[Database Architecture]].

Rain uses Drift/SQLite for local persistence.

## Tables

- `messages`
- `friends`
- `queued_messages`
- `file_transfers`
- `connection_memory_table`
- `identity_table`
- `message_seq_tracker`

## Current Risks

- Local query structure was mitigated on 2026-06-05 with Drift schema v6 indexes.
- Chat startup now uses a bounded live tail plus older-page loading.
- Remaining risk is device/low-power performance proof for large histories.

## Implemented Indexes

- `messages_peer_sent_seq_id_idx`
- `friends_display_name_idx`
- `queued_messages_to_status_seq_sent_idx`
- `queued_messages_status_to_idx`
- `file_transfers_peer_created_idx`
- `file_transfers_message_id_idx`
- `file_transfers_state_peer_idx`

Related: [[Database Schema]], [[Migrations]], [[Technical Debt]].
