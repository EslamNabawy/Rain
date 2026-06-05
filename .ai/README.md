# Rain AI Overlay

This directory contains Codex-facing project guidance and helper scripts. It is not application runtime code and must not change Rain's Flutter/Firebase dependency graph, CI gates, hooks, release workflows, or deployment behavior unless a later task explicitly asks for that.

## Project Fit

- Project type: Flutter/Dart workspace with a Firebase backend and an Obsidian knowledge vault.
- Runtime AI/LLM behavior: none detected in app/backend code.
- Existing project context: root `AGENTS.md`, `CONTINUITY.md`, and `obsidian-vault/`.
- Overlay status: installed for tool routing, OpenViking imports, UI guidance, and focused agency-role prompts.
- Promptfoo status: placeholder only. Enable when the repo gains concrete prompts, agents, RAG, model calls, generated text behavior, or eval targets.

## Files

- `tool-routing.md`: when to use Context7, OpenViking, Promptfoo, Impeccable, and agency roles.
- `impeccable.md`: frontend/UI/UX quality rules for Rain UI work.
- `agency/`: focused role guidance for architecture, review, security, frontend, research, and reality-checking tasks.
- `openviking/`: import scripts for repository context, `.ai/` overlay context, and Obsidian vault context.
- `promptfoo/`: disabled-by-default eval placeholder.

Use the smallest relevant file for the task. Do not load every role or guidance file by default.
