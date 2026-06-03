# Design Decisions

Design decisions are tracked as ADRs under [[ADR-001]], [[ADR-002]], [[ADR-003]], [[ADR-004]], [[ADR-005]], [[ADR-006]], [[ADR-007]], and [[ADR-008]].

## Current Decisions

- Firebase carries signaling and coordination, not media.
- WebRTC carries chat data, file bytes, voice, and video.
- One active voice/video call globally.
- Calls require fresh online presence, not necessarily an already-connected chat lane.
- Manual disconnect blocks automatic reconnect for that peer.
- Closed/killed app means offline in the current product scope.
- Obsidian vault is now the documentation source of truth.
- Call runtime uses coordinator architecture.
- Firebase call leases have one lease authority.
- Presence resolver owns peer availability decisions.
- Message loading uses bounded live tail plus pagination.
- File transfer uses streaming sinks and data-channel backpressure.

Related: [[Project Memory]], [[Technical Debt]], [[System Architecture]], [[Architecture Refactor Plan Index]], [[Decision Map]].
