# Project Conventions

## Branching

- Work should happen on `dev`.
- Merge to `main` through PR gates.

## Documentation

- All major knowledge must live in [[Project Memory]] and related vault notes.
- Every significant architecture decision gets an ADR.
- Every feature gets a feature note.

## Runtime Conventions

- Manual disconnect means no auto-reconnect.
- Offline/stale peers must not start calls.
- Every blocked user action needs a visible message.
- Firebase is signaling/coordinating only.

Related: [[AI Instructions]], [[Design Decisions]].
