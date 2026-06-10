# Rain AI Tool Routing

This file is project-local routing guidance. It does not install tools, alter runtime behavior, or make tools active by default.

## Context7

Use Context7 when current third-party docs matter: Flutter, Dart, Riverpod, Drift, Firebase, `flutter_webrtc`, GoRouter, Melos, Node, npm, GitHub Actions, SDKs, APIs, libraries, CLIs, or migration guides.

Do not use memory or guesses for version-sensitive API behavior when Context7 is available.

## OpenViking

Use OpenViking for private/project context:

- Rain architecture notes and prior decisions.
- Obsidian vault notes.
- Historical debugging and release evidence.
- Repo-specific conventions and continuity.

Local helpers:

```powershell
.\scripts\ai\doctor.ps1
.\scripts\ai\import-openviking.ps1 -Target project
.\scripts\ai\import-openviking.ps1 -Target ai
.\scripts\ai\import-openviking.ps1 -Target obsidian
.\scripts\ai\import-openviking.ps1 -Target all
```

Project import writes to `viking://resources/projects/Rain/source` and excludes build artifacts, `.ai/`, and the Obsidian vault by default. Import `.ai/` and the vault separately so guidance and notes can be refreshed independently.

## Promptfoo

Promptfoo is intentionally not enabled by default. Rain has AI operating docs, but the application/backend does not currently contain runtime LLM behavior.

Enable Promptfoo only when changing concrete prompts, agent behavior, RAG retrieval, model routing, model configuration, or generated text behavior that can be regression-tested.

## Impeccable

Use `.ai/impeccable.md` for frontend, UI, UX, visual design, product screens, responsiveness, accessibility, and layout-state work. Preserve Rain's existing design system and verify important screens visually when practical.

## Agency Roles

Use role files only when they match the task. Do not load every role by default.

- `.ai/agency/architect.md`
- `.ai/agency/reviewer.md`
- `.ai/agency/security.md`
- `.ai/agency/frontend.md`
- `.ai/agency/researcher.md`
- `.ai/agency/reality-checker.md`
