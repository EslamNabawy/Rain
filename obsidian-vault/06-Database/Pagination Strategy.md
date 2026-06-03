# Pagination Strategy

## Problem

Conversation watch currently emits full ordered conversations.

## Target

- Load older messages by page.
- Keep a bounded live tail stream.
- Preserve message ordering by `sentAt` and `seq`.
- Keep unread behavior correct for selected/open chat.

Related: [[Database Scalability Epic]], [[Index Strategy]].
