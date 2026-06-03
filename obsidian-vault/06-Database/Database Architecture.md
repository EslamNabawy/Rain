# Database Architecture

See also [[Database Schema]].

## Current Local Storage

Drift stores messages, friends, queued messages, file transfers, connection memory, identity, and sequence tracker.

## Risk

The current schema has primary keys but lacks secondary indexes for common list/watch queries.

Related: [[Index Strategy]], [[Pagination Strategy]], [[Migration Plan]].
