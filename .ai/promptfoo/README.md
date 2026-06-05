# Promptfoo

Promptfoo is not enabled for Rain by default.

Current reason: Rain has AI operating documentation, but the Flutter app and Firebase backend do not currently contain runtime prompts, agents, RAG retrieval, model calls, generated text behavior, or LLM output contracts.

Enable later only when there is concrete AI behavior to test:

1. Add `.ai/promptfoo/promptfooconfig.yaml`.
2. Keep fixtures, prompts, and expected outputs under `.ai/promptfoo/` unless the project establishes another convention.
3. Run `.\scripts\ai\run-evals.ps1`.
4. Add CI gates only after the evals are stable, useful, and intentionally part of release policy.
