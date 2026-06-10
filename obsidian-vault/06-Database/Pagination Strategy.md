# Pagination Strategy

## Problem

Before 2026-06-05, `MessageStore.watchConversation(peerId)` emitted the full ordered conversation. Large chats could make chat startup and provider rebuilds scale with total history.

Detailed implementation planning: [[Message Loading Refactor Plan]].

## Current Implementation

- `MessageStore.watchConversationTail(peerId, limit: 50)` watches only the newest bounded page.
- `MessageStore.loadConversationPage(peerId, before: cursor, limit: 50)` loads older rows by stable cursor.
- `MessagePageCursor` uses `sentAt`, `seq`, and `id` so duplicate timestamps and sequence ties remain deterministic.
- `MessagesController` starts from the bounded live tail and merges older pages only when requested.
- Chat pull-to-refresh first loads older local history, then continues the existing network/friend refresh behavior.

## Remaining Proof

- Low-power/device scroll performance is not yet measured.
- Rebuild isolation around long conversations is locally provider-tested but not frame-budget proven.
- UI affordance is currently pull-to-refresh; a dedicated "load older" affordance can be considered after device UX testing.

Related: [[Database Scalability Epic]], [[Index Strategy]].
