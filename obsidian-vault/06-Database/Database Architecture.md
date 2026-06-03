# Database Architecture

See also [[Database Schema]].

## Current Local Storage

Drift stores messages, friends, queued messages, file transfers, connection memory, identity, and sequence tracker.

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

Related: [[Database Architecture Overview]], [[Index Strategy]], [[Pagination Strategy]], [[Migration Plan]].
