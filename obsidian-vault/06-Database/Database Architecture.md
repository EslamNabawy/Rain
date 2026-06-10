# Database Architecture

See also [[Database Schema]].

## Current Local Storage

Drift stores messages, friends, queued messages, file transfers, connection memory, identity, and sequence tracker.

## Local Data Security

Decision: [[ADR-010]].

Rain currently uses normal Drift/SQLite local storage without app-layer database encryption. Message content, queued outgoing message content, file-transfer names, and local file paths are plaintext local database fields. This is an accepted current-scope limitation, not a technical security fix.

Future local database encryption must be planned separately with key management, plaintext-to-encrypted migration, interrupted-migration recovery, and migration tests.

## Current Risks

- Drift schema v6 now includes explicit secondary indexes for high-frequency message, queue, file-transfer, and friend query paths.
- Chat startup now uses a bounded live tail instead of full conversation loading.
- Older message history loads by cursor page from local storage.
- Remaining risk is device/low-power performance proof, not absence of local query structure.

## Implemented Indexes

- `messages_peer_sent_seq_id_idx`
- `friends_display_name_idx`
- `queued_messages_to_status_seq_sent_idx`
- `queued_messages_status_to_idx`
- `file_transfers_peer_created_idx`
- `file_transfers_message_id_idx`
- `file_transfers_state_peer_idx`

## Conversation Loading

`MessageStore.watchConversationTail` watches the newest 50 messages by default. `MessageStore.loadConversationPage` loads older messages before a `MessagePageCursor(sentAt, seq, id)`. `MessagesController` merges older pages with the live tail and de-duplicates by message id.

Related: [[Database Architecture Overview]], [[Index Strategy]], [[Pagination Strategy]], [[Migration Plan]].
