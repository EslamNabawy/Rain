# Design Decisions

Design decisions are tracked as ADRs under [[ADR-001]], [[ADR-002]], and [[ADR-003]].

## Current Decisions

- Firebase carries signaling and coordination, not media.
- WebRTC carries chat data, file bytes, voice, and video.
- One active voice/video call globally.
- Calls require fresh online presence, not necessarily an already-connected chat lane.
- Manual disconnect blocks automatic reconnect for that peer.
- Closed/killed app means offline in the current product scope.
- Obsidian vault is now the documentation source of truth.

Related: [[Project Memory]], [[Technical Debt]], [[System Architecture]].
