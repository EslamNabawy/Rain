# Project Home

Last updated: 2026-06-03

Rain is a private peer-to-peer chat app for Android and Windows. It supports accepted-friend chat, file transfer, voice calls, video calls, connection request notifications, local diagnostics, app update validation, and direct test builds.

## Command Center

- Product source: [[Vision]], [[Requirements]], [[Feature Matrix]]
- User source: [[User Flows]], [[User Personas]]
- Roadmap source: [[Master Roadmap]], [[Critical Path]], [[30 Day Plan]], [[60 Day Plan]], [[90 Day Plan]], [[Parallel Work Streams]], [[Launch Blockers]], [[Quick Wins]], [[High-Risk Work]]
- Execution source: [[Backlog]], [[Active Sprint]], [[Audit Resolution Tracker]], [[Weekly Progress]]
- Architecture source: [[System Architecture]], [[Current Architecture]], [[Target Architecture]], [[Refactoring Strategy]]
- Diagram source: [[System Diagrams]], [[Sequence Diagrams]], [[Entity Relationships]]
- API source: [[API Overview]], [[Endpoints]], [[Contracts]]
- Runtime source: [[AI Context]], [[Project Memory]]
- QA source: [[Test Strategy]], [[QA Findings]], [[Launch Readiness]]
- Risk source: [[Risk Register]], [[Risk Categories]], [[Risk Matrix]], [[Blocker Resolution Plan]]
- Security source: [[Security Review]], [[Security Roadmap]], [[Risk Register]], [[Permissions Matrix]]
- Operations source: [[Deployment]], [[Monitoring]], [[Incident Response]], [[Backup Strategy]], [[Release Gates]]
- Technical debt source: [[Technical Debt Register]], [[Debt Categories]], [[Debt Prioritization]]
- Development source: [[Coding Standards]], [[Environment Setup]], [[Build Process]]
- Research source: [[Research Notes]], [[Competitor Analysis]]
- Lessons source: [[Lessons Learned Index]], [[Continuous Improvement Log]]
- AI memory source: [[Project Memory]], [[AI Memory Index]], [[Durable Facts]], [[Session Handoff]]
- Knowledge graph source: [[Knowledge Graph Index]], [[Domain Map]], [[Dependency Map]], [[Decision Map]], [[Feature Map]], [[System Ownership Map]]
- Template source: [[Templates Index]]

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
- [[ADR-001]] - Production readiness vault owns audit execution.

## Work Next

1. Execute [[VoiceCallRuntime Refactor]] through [[CallStartCoordinator]], [[CallLeaseManager]], [[CallMediaCoordinator]], [[CallTerminalReconciler]], and [[CallDiagnosticsRecorder]].
2. Harden [[Lease Management]], [[Presence Management]], and [[Call State Machine]].
3. Fix strict app update version validation and Remote Config manifest handling in [[Version And Updates]].
4. Add database indexes and message pagination through [[Index Strategy]] and [[Pagination Strategy]].
5. Add WebRTC diagnostics that classify signaling, permission, ICE, TURN, and media failures separately.

## Production Execution

- Readiness: [[Production Readiness]]
- Roadmap: [[Master Roadmap]]
- Critical path: [[Critical Path]]
- Parallel streams: [[Parallel Work Streams]]
- Launch blockers: [[Launch Blockers]]
- Quick wins: [[Quick Wins]]
- High-risk work: [[High-Risk Work]]
- Epics: [[Epic Index]]
- Risks: [[Risk Register]]
- Risk categories: [[Risk Categories]]
- Risk matrix: [[Risk Matrix]]
- Debt: [[Technical Debt Register]]
- Debt categories: [[Architecture Debt]], [[Scalability Debt]], [[Security Debt]], [[Performance Debt]], [[Testing Debt]], [[DevOps Debt]], [[UX Debt]]
- Blockers: [[BLOCKERS]]
- Blocker resolution: [[Blocker Resolution Plan]]
- Milestones: [[Milestones]]
- Lessons: [[Lessons Learned Index]]
- Knowledge graph: [[Knowledge Graph Index]]
