# Index Strategy

## Required Indexes

- `messages(peer_id, sent_at, seq)`
- `friends(display_name)`
- `file_transfers(peer_id, created_at)`
- `file_transfers(state)`
- `queued_messages(to, status, sent_at)`

## Business Value

Keeps chat and friends responsive as users accumulate messages and transfers.

## Technical Value

Avoids full scans and sorts in watched queries.

Related: [[Database Scalability Epic]], [[Migration Plan]].
