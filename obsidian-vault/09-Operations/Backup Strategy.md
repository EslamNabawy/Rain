# Backup Strategy

## Current State

Rain does not have a formal user data backup strategy.

## Data Locations

- Local Drift database stores messages, friends cache, queues, file records.
- Firebase stores identity, presence, relationships, signaling, and ephemeral coordination.
- Files are transferred peer-to-peer and saved/exported locally.

## Required Future Decisions

- Whether chats should remain local-only.
- Whether export/import should exist.
- Whether account recovery should include friend graph recovery.
- How to handle deleted local app data.

Related: [[Database Architecture]], [[Risk Register]].
