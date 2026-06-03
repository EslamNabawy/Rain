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

- Secondary indexes are missing for high-frequency queries.
- `watchConversation(peerId)` returns the full conversation ordered by `sentAt` and `seq`.
- File transfer records are watched by peer without known indexes.
- Message pagination is not yet implemented.

## Required Indexes

- `messages(peer_id, sent_at, seq)`
- `friends(display_name)`
- `file_transfers(peer_id, created_at)`
- `file_transfers(state)`
- `queued_messages(to, status, sent_at)`

Related: [[Database Schema]], [[Migrations]], [[Technical Debt]].
