# Production Readiness

Last updated: 2026-06-03

## Scoreboard

- Production readiness: 48/100 baseline, target 90/100
- Architecture: 58/100 baseline
- Security: 66/100 baseline
- Scalability: 45/100 baseline
- Maintainability: 50/100 baseline
- Technical debt risk: 72/100 baseline

## Readiness Formula

Rain reaches 90/100 only when the seven roadmap phases in [[Master Roadmap]] are complete and verified by [[Release Gates]].

## Critical Path

1. [[Architecture Stabilization Epic]]
2. [[Signaling Reliability Epic]]
3. [[Database Scalability Epic]]
4. [[File Transfer Optimization Epic]]
5. [[Security Hardening Epic]]
6. [[CI-CD Modernization Epic]]
7. [[Production Validation Epic]]

## Hard Launch Blockers

- False busy and stale call leases.
- PC-to-mobile voice/video call failures.
- Update prompt/version validation failures.
- Missing database indexes and pagination.
- File transfer I/O and allocation pressure.
- Firebase rules complexity without exhaustive emulator coverage.

Related notes: [[Project Home]], [[Critical Path]], [[Audit Resolution Tracker]], [[Risk Register]], [[Risk Matrix]], [[BLOCKERS]], [[Blocker Resolution Plan]].
