# Project Home

Last updated: 2026-06-03

Rain is a private peer-to-peer chat app for Android and Windows. It supports accepted-friend chat, file transfer, voice calls, video calls, connection request notifications, local diagnostics, app update validation, and direct test builds.

## Command Center

- Product source: [[Vision]], [[Requirements]], [[Feature Matrix]]
- Architecture source: [[System Architecture]], [[Design Decisions]], [[Technical Debt]]
- Runtime source: [[AI Context]], [[Project Memory]]
- QA source: [[Test Strategy]], [[QA Findings]], [[Launch Readiness]]
- Security source: [[Security Review]], [[Risk Register]], [[Permissions Matrix]]
- Operations source: [[Deployment]], [[Monitoring]], [[Incident Response]]

## Current Scores

- Completion estimate: 62%
- Technical debt score: 72/100 risk, higher is worse
- Security score: 66/100
- Test coverage score: 70/100
- Production readiness score: 48/100
- Scalability score: 45/100
- Maintainability score: 50/100

## Active Features

- [[Authentication]]
- [[Friendship And Blocking]]
- [[Presence And Direct Connect]]
- [[Peer Chat]]
- [[File Transfer]]
- [[Voice Calls]]
- [[Video Calls]]
- [[Connection Request Notifications]]
- [[Version And Updates]]
- [[Diagnostics And Logging]]
- [[Sound System]]
- [[Branding And UI]]

## Open Blockers

See [[BLOCKERS]].

Top blockers:

- Voice/video call reliability is not production-proven across PC-to-mobile and mobile-to-PC.
- Firebase RTDB call lock protocol can still create stale or false busy states.
- Update prompt behavior has been reported unreliable in old-app scenarios.
- Real device QA is incomplete; emulator/unit coverage is not enough for WebRTC calls.

## Recent Architectural Decisions

- [[ADR-001]] - Firebase is signaling and coordination only, not media transport.
- [[ADR-002]] - Stay on Firebase Spark/free tier where possible.
- [[ADR-003]] - Obsidian vault is the living source of truth for project knowledge.

## Work Next

1. Harden the call signaling lease and terminal reconciliation path.
2. Fix strict app update version validation and Remote Config manifest handling.
3. Add database indexes and message pagination.
4. Add WebRTC diagnostics that classify signaling, permission, ICE, TURN, and media failures separately.
5. Split oversized runtime and UI files into maintainable coordinators.
