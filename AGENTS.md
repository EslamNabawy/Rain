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

## Required Session Startup

For any non-trivial work:

1. Read `CONTINUITY.md`.
2. Read this `AGENTS.md`.
3. Check `git status --short --branch`.
4. Inspect relevant code or docs before editing.
5. Identify impacted documentation before implementing.

If `CONTINUITY.md` is missing, create it before starting implementation work.

## Documentation Requirements

Documentation is part of the product.

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
2. Update `obsidian-vault/15-AI/Project Memory.md` when a durable fact changes.
3. Update risk, blocker, or debt notes when new issues are discovered.
4. Update roadmap or sprint notes when scope changes.
5. Run the vault validator when documentation changes.

The current validator is:

```powershell
.\scripts\check_obsidian_vault.ps1
```

Future phases will populate architecture, risks, roadmaps, tasks, metrics, knowledge graph links, and self-improvement data. Do not overbuild those systems early.

## Implementation Workflow

Before editing code:

1. Understand the current behavior from code, tests, diagnostics, or docs.
2. Identify the smallest safe change.
3. Check for related state, async, Firebase, WebRTC, security, and UI edge cases.
4. Prefer existing abstractions and patterns.
5. Add or update tests proportional to risk.
6. Update documentation and continuity notes.

For high-risk systems such as calls, signaling, Firebase rules, update checks, file transfer, or authentication, do not rely only on visual/manual checks.

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
