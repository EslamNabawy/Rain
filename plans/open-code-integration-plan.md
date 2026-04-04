# OpenCode Multi-Agent Integration Plan

Phase 1 — Architecture & Validation (completed)
- Validate opencode.json references to six SKILL.md files (done)
- Confirm six SKILL.md files exist at:
-   - skills/tdd-workflow/SKILL.md
-   - skills/security-review/SKILL.md
-   - skills/backend-patterns/SKILL.md
-   - skills/coding-standards/SKILL.md
-   - skills/verification-loop/SKILL.md
-   - skills/api-design/SKILL.md
- Result: PASS (validated via scripts/validate_opencode.js)

Phase 2 — Agent-sized Unit Decomposition
- Unit 1: Planner — decompose OpenCode integration into tasks A..E.
- Unit 2: Architect — define interfaces between Backend, Frontend, and DB agents.
- Unit 3: Code Reviewer — prepare gating checks for each unit (edge cases, security).
- Unit 4: E2E Prep — outline smoke tests for the integration (auth, load, errors).
- Each unit must be independently verifiable and contain a single dominant risk.

Phase 3 — Parallel Implementation (in a real session)
- Implement code skeletons (not in this plan) for the six SKILL.md-driven behaviors.
- Gate each implementation with the corresponding reviewer checks.
- Run eval-first style checks after each unit completion.

Phase 4 — Integration & E2E
- Wire frontend to backend surfaces; validate data flow end-to-end.
- Execute Playwright-like E2E tests for critical paths.

Phase 5 — Verification & Delivery
- Run full verification loop: build, type checks, lint, tests, security checks.
- If green, prepare a PR with a detailed changelog and rollout plan.

Done Conditions (per unit)
- Unit X: All acceptance criteria met; test stubs present; review completed.

Notes
- This plan is a template for proceeding from read-only validation to full multi-agent execution.
- Replace placeholders with concrete files, tests, and commands in your repo/CI.
