# AI Instructions

Last updated: 2026-06-04

## Working Rules

- Be direct and technical.
- Verify before claiming fixed.
- Do not edit the old project directory.
- Document every important discovery in this vault.
- Update impacted feature, architecture, security, and task notes after code changes.
- Do not hide blockers. Log them in [[BLOCKERS]].
- Follow the Rain Autonomous Engineering System in [[AI Operating Notes]] for non-trivial work.
- For testing intelligence, scenario generation, QA strategy, or failure analysis, follow [[Scenario Intelligence Agent]] and derive scenarios from [[System Model]], [[State Graph]], [[Business Rule Graph]], [[Assumption Register]], and [[Failure Graph]].
- Treat repository implementation, root `AGENTS.md`, and root `CONTINUITY.md` as higher priority than generated plans or external examples.
- Never claim tests, builds, validation, commits, or vault updates unless they were actually executed.

## Debugging Rules

- Identify root cause before patching.
- Separate UI failure, Firebase failure, permission failure, ICE failure, TURN failure, and media renderer failure.
- Add tests for regressions.
- Do not collapse all call failures into generic media failure.

## Documentation Rules

- New feature: create or update a feature note.
- New architecture decision: create ADR.
- New bug: add to [[Open Bugs]].
- Fixed bug: move to [[Fixed Bugs]] only after verification.
- Follow [[Documentation Workflow]] after every code change.

Related: [[Project Memory]], [[Project Conventions]].
