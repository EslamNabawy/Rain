# Rain Continuity

This file must survive across future AI sessions.

Every future session must read this file before starting non-trivial work.

## Current Goal

Phase 8 self-improvement engine has been completed. Lessons, recurring patterns, improvement backlog, optimization opportunities, metrics, and recommended next actions are now managed under `obsidian-vault/18-Lessons Learned/`.

## Current Phase

Phase 8 - Self-Improvement Engine

## Completed Phases

- [x] Phase 0 - Operating Model Foundation
- [x] Phase 1 - Obsidian Vault Bootstrap
- [x] Phase 2 - Repository Discovery
- [x] Phase 3 - Project Memory Generation
- [x] Phase 4 - Audit to Roadmap Conversion
- [x] Phase 5 - Technical Debt System
- [x] Phase 6 - Risk and Blocker Intelligence
- [x] Phase 7 - Architecture Refactor Planning
- [x] Phase 8 - Self-Improvement Engine
- [ ] Phase 9 - Codex Automation Layer
- [ ] Phase 10 - Continuous Project Evolution

## Active Work

- `ROOT_CAUSE_ANALYSIS.md` was created on 2026-06-03 from the supplied Windows diagnostics JSON, Android screenshot, and manual failure report. It is the current evidence lock for call/presence/update/diagnostics failures.
- The RCA confirmed these root-cause clusters: split call terminal authority, Android `signaling.endCall` permission denial, presence freshness races, terminal inbox exposure before cleanup, Android diagnostics export path failure, and update build-number inconsistency.
- First mitigation from the RCA execution is complete: late voice signaling states after terminal Firebase rooms are recorded as `late_frame_ignored` events only and no longer overwrite crash diagnostics as `lastCrash`.
- Second mitigation from the RCA execution is complete: Firebase `endCall` now writes the terminal `voiceCalls/{callId}` room state before any best-effort inbox mirror update, so an already-cleaned `voiceCallInboxes/{callee}/{callId}` row can no longer cause a permission-denied terminal cleanup failure.
- Third mitigation from the RCA execution is complete: diagnostics export treats Android SAF `/document/...` and `/tree/...` handles as platform-managed picker outputs and no longer opens them as raw filesystem paths.
- Fourth mitigation from the RCA execution is complete: backend presence is resolved from `online + lastHeartbeat` with a shared 30 second runtime freshness window before local friend seeding, direct connect, connection-request routing, or voice/video call start. Stale raw-online records are treated as offline and logged as `backend_presence_stale_resolved_offline`.
- Fifth mitigation from the RCA execution is complete: call setup diagnostics now retain a per-call Firebase room status timeline and terminal-room failure reconciliation emits `VoiceCallDiagnostics`, so failed setup exports can show ringing/accepted/failed transitions instead of an empty room timeline.
- Sixth mitigation from the RCA execution is complete: update checks now classify stale Remote Config release policy as `remotePolicyOutdated` instead of `current`, same-version minimum build upgrades become required updates, and optional update prompts render from the root app surface before login/home.
- Seventh mitigation from the RCA execution is complete: Phase 05 presence/session freshness now carries session metadata through backend identity snapshots, treats `presence.state != online` as offline, blocks UI Connect and auto-recovery through the shared fresh-presence resolver, and preserves `presenceExpired` as a terminal peer intent until a later successful explicit reconnect.
- Phase 0 deliverables are complete.
- Phase 1 vault structure is complete.
- Phase 2 repository discovery is documented in `obsidian-vault/03-Architecture/Current Architecture.md`.
- Phase 3 primary AI memory is documented in `obsidian-vault/AI-Memory/Project Memory.md`.
- Phase 4 roadmap artifacts are documented in `obsidian-vault/01-Roadmap/`.
- Phase 5 technical debt artifacts are documented in `obsidian-vault/11-Technical Debt/`.
- Phase 6 risk and blocker artifacts are documented in `obsidian-vault/12-Risks/` and `obsidian-vault/14-Blockers/`.
- Phase 7 architecture refactor plans are documented in `obsidian-vault/03-Architecture/`.
- Phase 8 self-improvement artifacts are documented in `obsidian-vault/18-Lessons Learned/`.
- Repository-wide `AGENTS.md` now requires pre-implementation reading of project memory, roadmap, debt, risk, and blockers, plus a post-code Obsidian update gate.
- `obsidian-vault/01-Roadmap/Engineering System Flaw Remediation Plan.md` has been created to fix flaws in the current documentation operating system before Phase 9 automation.
- Engineering System Flaw Remediation Phase 00 and Phase 01 are complete: canonical source views are documented, duplicate note titles were removed, and the vault checker now fails on uncontrolled duplicate note titles.
- Do not perform app code modifications as part of documentation-only phase work.
- Wait for explicit user approval before starting Phase 9.

## Known Risks

- The repository already contains prior documentation and an expanded Obsidian vault; future phases must avoid duplicating or contradicting it.
- The active maintained repo must remain separate from `D:\old project\Rain`.
- The project has high-risk runtime areas: Firebase signaling, WebRTC calls, presence, update checks, diagnostics, and release workflows.
- Future phases must avoid overbuilding before discovery.
- The vault still has manual-only governance gaps around status schemas, validation evidence, stale notes, and generated metrics; full Phase 9 automation should wait until those are structured.

## Known Blockers

- None for Phase 8 self-improvement engine.

## Next Recommended Action

Use `ROOT_CAUSE_ANALYSIS.md` to implement the next repair in evidence order: complete call setup media/ICE failure classification and keep release Remote Config deployment evidence tied to each build.

## Future Population Areas

Future phases will populate:

- Architecture
- Risks
- Roadmaps
- Tasks
- Metrics
- Knowledge graph
- Self-improvement data
- Lessons learned
- Technical debt
- Blockers
- ADRs
