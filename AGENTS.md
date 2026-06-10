# Rain Agent Operating Manual

This file is the primary operating manual for AI sessions working in this repository.

Every future session must read this file first, then read [[CONTINUITY.md]] if available in the local context.

## Project Goals

Rain is a Flutter monorepo for a private peer-to-peer chat app on Android and Windows.

Core product goals:

- Private accepted-friend chat.
- Reliable peer-to-peer connection management.
- Voice calls, video calls, and file transfers over WebRTC.
- Firebase used for authentication, presence, signaling, coordination, rules, and update policy.
- Local-first diagnostics that help debug failures without exposing private content.
- A self-documenting engineering system driven by an Obsidian vault and tracked project memory.

Core engineering goal:

Build Rain into a maintainable, reliable, testable, security-conscious product without losing project history or repeating solved mistakes.

## Repository Map

- `apps/rain` - Flutter desktop and Android app.
- `packages/peer_core` - WebRTC transport, media, platform bridge, and data-channel primitives.
- `packages/protocol_brain` - signaling, sessions, retry, call coordination, connection requests, and connection memory.
- `packages/rain_core` - Drift storage, identity, friends, messages, file metadata, and delivery rules.
- `backend/firebase` - Firebase Realtime Database rules, Remote Config templates, and backend support code.
- `obsidian-vault` - project memory, architecture notes, roadmap, risks, blockers, debt, decisions, and operational documentation.

Do not touch `D:\old project\Rain`. The active maintained copy is expected to be `C:\Users\eslam\OneDrive\Desktop\GoodStuff\Rain` unless the user explicitly changes it.

## Engineering Priorities

1. Correctness
2. Reliability
3. Security
4. Maintainability
5. Operational simplicity
6. Performance
7. Developer experience

## Default Behavior

- Be direct, technical, and concise.
- Verify with tools when practical.
- Do not hallucinate APIs, versions, security guarantees, or test results.
- Prefer simple maintainable solutions over clever abstractions.
- Keep changes focused on the current request.
- Do not revert user changes unless the user explicitly asks.
- Do not hardcode secrets, credentials, tokens, private keys, or local-only account data.
- Do not introduce paid Firebase dependencies unless the user explicitly changes the free-tier constraint.
- Keep runtime backends limited to Firebase and noop unless the app direction changes.
- Prefer existing Flutter, Riverpod, Drift, Firebase, WebRTC, Melos, and repository patterns.
- Do not reintroduce obsolete scaffolding such as old phase runners, external sample apps, or unused generated experiments.

## Rain Autonomous Engineering System

For meaningful work, operate through the Rain Autonomous Engineering System. Always identify the current workflow node in progress updates or final reports when the task spans more than a direct answer.

Source-of-truth priority order:

1. Actual repository implementation
2. This `AGENTS.md`
3. `CONTINUITY.md`
4. `obsidian-vault/03-Architecture/Current Architecture.md`
5. `obsidian-vault/AI-Memory/Project Memory.md`
6. `obsidian-vault/12-Risks/Risk Register.md`
7. `obsidian-vault/14-Blockers/BLOCKERS.md`
8. `obsidian-vault/11-Technical Debt/Technical Debt Register.md`
9. User request
10. External examples

Reality enforcement:

- Never claim files were modified unless they were actually modified.
- Never claim tests, builds, validation, CI, vault updates, or git commits succeeded unless they were actually executed and verified.
- If a check was not run, state that it was not executed.

Workflow nodes:

0. Environment verification: repository path, branch, git status, workspace health, vault availability.
1. Knowledge synchronization: required startup notes and relevant feature/system notes.
2. Repository discovery: implementation, related modules, abstractions, tests, and TODOs.
3. Task understanding: requested change, scope, assumptions, and unknowns.
4. Impact analysis: architecture, database, Firebase, WebRTC, security, performance, operations, migration, and documentation.
5. Pattern discovery: existing Rain patterns before external references.
6. Architecture validation: Riverpod, package, Firebase, WebRTC, and ownership boundaries.
7. Implementation plan.
8. Execution.
9. Validation.
10. Obsidian synchronization.
11. Vault validation.
12. Production-readiness review.
13. Version-control preparation.
14. Completion report.

Do not code before planning for non-trivial work. Do not consider implementation complete until code and vault state are synchronized or the final response explicitly states what could not be synchronized.

For testing strategy, scenario generation, QA intelligence, failure analysis, or risk discovery, use the vault's scenario-intelligence layer after the normal startup set:

1. `obsidian-vault/15-AI/Scenario Intelligence Agent.md`
2. `obsidian-vault/20-Knowledge Graph/System Model.md`
3. `obsidian-vault/20-Knowledge Graph/State Graph.md`
4. `obsidian-vault/20-Knowledge Graph/Business Rule Graph.md`
5. `obsidian-vault/12-Risks/Assumption Register.md`
6. `obsidian-vault/09-Testing/Failure Graph.md`
7. `obsidian-vault/09-Testing/Scenario Coverage Matrix.md`

Scenario work must derive tests from explicit assumptions, state paths, business rules, and failure chains. Do not mark a scenario covered unless the named validation was actually executed or previously recorded.

## Required Session Startup

For any non-trivial work:

1. Read this `AGENTS.md`.
2. Read `CONTINUITY.md`.
3. Check `git status --short --branch`.
4. Inspect relevant code or docs before editing.
5. Identify impacted documentation before implementing.

If `CONTINUITY.md` is missing, create it before starting implementation work.

## Mandatory Pre-Implementation Reading

Before any implementation, read these source-of-truth notes:

1. `obsidian-vault/AI-Memory/Project Memory.md`
2. `obsidian-vault/01-Roadmap/Master Roadmap.md`
3. `obsidian-vault/11-Technical Debt/Technical Debt Register.md`
4. `obsidian-vault/12-Risks/Risk Register.md`
5. `obsidian-vault/14-Blockers/BLOCKERS.md`

Use these notes to identify the current priorities, critical path, risks, blockers, and known failure patterns before changing code.

## Documentation Requirements

Documentation is part of the product.

Documentation is mandatory. No implementation is considered complete until the Obsidian vault has been updated.

When discovering or changing any important system, update the relevant Obsidian note and project memory. Important systems include:

- Feature behavior
- Runtime state machines
- Firebase rules or schemas
- WebRTC signaling or media flow
- Database entities and migrations
- Security assumptions
- Release workflows
- Testing strategy
- Technical debt
- Risks and blockers
- Architecture decisions
- Lessons learned

Follow `DOCUMENTATION_RULES.md` for naming, linking, ADRs, roadmaps, debt, and lessons learned.

## Obsidian Update Requirements

The Obsidian vault must evolve with the project.

After meaningful work:

1. Update affected feature or architecture notes.
2. Update `obsidian-vault/AI-Memory/Project Memory.md` when a durable fact changes.
3. Update risk, blocker, or debt notes when new issues are discovered.
4. Update roadmap or sprint notes when scope changes.
5. Update lessons learned and recommended next actions when implementation work completes.
6. Run the vault validator when documentation changes.

The current validator is:

```powershell
.\scripts\check_obsidian_vault.ps1
```

The vault now contains architecture, risks, roadmaps, tasks, metrics, knowledge graph links, and self-improvement data. Keep those systems current.

## Implementation Workflow

Before editing code:

1. Understand the current behavior from code, tests, diagnostics, or docs.
2. Understand the affected architecture through relevant notes under `obsidian-vault/02-Architecture`, `obsidian-vault/03-Architecture`, and linked feature/system notes.
3. Review existing ADRs in `obsidian-vault/11-Decisions`.
4. Review linked notes from the affected architecture, roadmap, risks, blockers, and debt items.
5. Identify the smallest safe change.
6. Check for related state, async, Firebase, WebRTC, security, and UI edge cases.
7. Prefer existing abstractions and patterns.
8. Add or update tests proportional to risk.
9. Update documentation and continuity notes.

For high-risk systems such as calls, signaling, Firebase rules, update checks, file transfer, or authentication, do not rely only on visual/manual checks.

## Post-Code Documentation Gate

After modifying code:

1. Update architecture docs for affected systems.
2. Update roadmap progress.
3. Update technical debt status or add new debt if created/discovered.
4. Update risks.
5. Update blockers.
6. Update lessons learned.
7. Update `obsidian-vault/AI-Memory/Project Memory.md` if durable project facts changed.
8. Generate or update the next recommended task in `obsidian-vault/18-Lessons Learned/Recommended Next Actions.md`.
9. Run `.\scripts\check_obsidian_vault.ps1`.

No implementation is complete until this gate is satisfied or the final response clearly states which required updates could not be completed and why.

## Validation Workflow

Use these checks for normal code changes:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

Use this check for documentation-vault changes:

```powershell
.\scripts\check_obsidian_vault.ps1
```

Do not run platform builds unless the user asks for build verification.

If validation cannot run, document why in the final response and, if relevant, in `CONTINUITY.md`.

## Blocker Handling

Never hide blockers.

When blocked:

1. Record the blocker in the Obsidian blocker register when the vault exists.
2. Record the immediate effect in `CONTINUITY.md`.
3. Continue safe adjacent work if possible.
4. Explain what is blocked, why, and what input or external state is needed.

Do not mark work complete when a required blocker remains.

## Technical Debt Tracking

When introducing or discovering debt:

1. Prefer fixing it if it is local and safe.
2. If not fixed, record it in the technical debt register.
3. Include risk, affected files, reason, and recommended resolution.
4. Link it to the relevant feature, architecture note, or roadmap phase.

No silent debt.

## Project Memory Requirements

Project memory must preserve durable facts:

- Architecture decisions
- Business rules
- Known constraints
- Naming conventions
- Failure patterns
- Lessons learned
- Current operating assumptions

Do not store temporary command output or speculation as memory.

## Continuous Improvement Requirements

After significant work, capture:

- What changed.
- What was learned.
- What failed or remained risky.
- Which validation passed or failed.
- What future work should happen next.

Future phases will build automated improvement loops, but Phase 0 only establishes the operating model.

## Local Android Flutter QA

Use the shared Windows QA toolkit at `C:\android-flutter-qa-toolkit` for local Android validation when requested.

Rules:

- Use PowerShell commands only.
- Do not use bash.
- Do not use Docker for this local workflow.
- Keep Appium bound to `127.0.0.1:4723`.
- Prefer Flutter `integration_test` for durable app flows.
- Use Appium plus `appium-flutter-driver` only for external smoke automation.
- Run the project smoke through `qa.appium.json`.
- Do not create per-project `node_modules` for Appium.
- Interactive widgets touched by automation need stable `ValueKey('qa.feature.action')`.
- Widgets that native or black-box automation must see also need `Semantics`.
- Store run artifacts under `D:\android-test-artifacts`.
- Do not touch `D:\old project\Rain`.

Common commands:

```powershell
C:\android-flutter-qa-toolkit\scripts\test-env.ps1
C:\android-flutter-qa-toolkit\scripts\start-avd.ps1
C:\android-flutter-qa-toolkit\scripts\start-appium.ps1
C:\android-flutter-qa-toolkit\scripts\run-local-quality.ps1 -ProjectRoot "<project-root>"
C:\android-flutter-qa-toolkit\scripts\run-local-quality.ps1 -ProjectRoot "<project-root>" -IncludeIntegration -Udid emulator-5554
C:\android-flutter-qa-toolkit\scripts\run-appium-smoke.ps1 -ProjectRoot "<project-root>" -BuildFirst -StartAvd -StartAppium
```

## Phase 0 Boundary

Phase 0 creates the operating model only.

Do not use Phase 0 to produce detailed architecture documentation, implementation plans, audits, or code changes. Future phases will populate the vault and knowledge graph.

<!-- AI-OVERLAY:START -->
## AI Tooling Overlay

Use Context7 for current third-party documentation: Flutter, Dart, Riverpod, Drift, Firebase, WebRTC, Melos, Node, npm, SDKs, APIs, libraries, and CLI tools.

Use OpenViking for private/project context: architecture notes, prior decisions, Obsidian notes, memory, and repo-specific knowledge. Keep OpenViking indexes and config outside this repository.

Use Promptfoo only when changing prompts, agent behavior, RAG retrieval, model routing, model configuration, or generated text behavior. Promptfoo is not a runtime dependency and is not enabled as a CI gate by default.

Use `.ai/impeccable.md` for frontend, UI, UX, and visual design work.

Use agency role files only when the task matches the role. Do not load every role into every task.

Preserve Rain's existing architecture, Firebase Spark/free-tier constraint, Obsidian documentation gates, and validation workflow. The overlay must not force unrelated rewrites, runtime dependency changes, CI changes, hooks, or deployment behavior.
<!-- AI-OVERLAY:END -->
