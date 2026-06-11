# Rain Documentation Rules

This file is the documentation style guide for Rain.

Phase 0 defines rules only. Future phases will populate detailed architecture, risks, roadmaps, tasks, metrics, knowledge graph data, and self-improvement notes.

## Naming Conventions

- Use clear title case for Markdown note names.
- Use stable names that describe the system, not the current implementation detail.
- Prefer singular concepts: `Call Lease Manager`, not `Call Lease Managers`.
- Avoid vague names such as `Misc`, `Stuff`, `Notes`, or `Old`.
- Use ADR numbering with zero padding: `ADR-001.md`, `ADR-002.md`.
- Use task IDs where useful: `TASK-001`, `TASK-002`.

## Obsidian Linking Standards

- Use Obsidian wiki links for internal knowledge references.
- Link concepts when they are related by dependency, ownership, risk, or workflow.
- Every important note should have inbound and outbound links.
- Avoid orphan notes.
- Prefer linking to concept notes instead of repeating long explanations.
- Do not create links to files that do not exist unless the current phase explicitly creates placeholder notes.

Examples:

- `[[Project Memory]]`
- `[[Risk Register]]`
- `[[Call State Machine]]`
- `[[Release Gates]]`

## Folder Structure Standards

The vault should remain organized by purpose:

- Dashboard notes summarize state.
- Product notes describe user value and requirements.
- Architecture notes describe systems and decisions.
- Feature notes describe behavior and implementation implications.
- Firebase and database notes describe backend rules, data shape, and persistence.
- Testing notes describe validation strategy and coverage.
- Security notes describe threats, rules, privacy, and mitigations.
- DevOps notes describe CI/CD, release gates, and operational workflows.
- Tasks, risks, blockers, debt, and progress notes track execution.
- AI notes preserve durable project memory and instructions.

Do not scatter execution tracking across unrelated folders.

## ADR Standards

Create an ADR for significant decisions involving:

- Architecture direction
- Backend constraints
- Security policy
- State management strategy
- Release strategy
- Tooling or automation strategy
- Major tradeoffs

ADR format:

1. Context
2. Problem
3. Options
4. Decision
5. Consequences
6. Related links

ADRs should record the decision, not become implementation plans.

## Roadmap Standards

Roadmaps must be dependency-driven.

Each roadmap phase should include:

- Purpose
- Dependencies
- Expected outputs
- Success criteria
- Validation expectations

Avoid roadmaps that are only wish lists. A later task should not depend on an earlier phase that has not defined its contract.

## Technical Debt Standards

Every debt item should include:

- ID
- Description
- Severity
- Impact
- Affected files or systems
- Why it exists
- Recommended resolution
- Owner or responsible area
- Status

Debt that blocks release should also appear in the risk or blocker register.

## Risk Standards

Every risk should include:

- ID
- Description
- Severity
- Probability
- Impact
- Mitigation
- Trigger condition
- Exit criteria
- Status

Risks are about possible future harm. Bugs are already observed failures. Blockers stop or constrain current work.

## Blocker Standards

Every blocker should include:

- ID
- Blocking condition
- Impact
- Required decision, input, or external change
- Work that can continue safely
- Exit criteria

Never hide a blocker in chat history only.

## Lessons Learned Standards

Record lessons learned when:

- A regression escapes tests.
- A release gate fails for a new reason.
- A user-reported failure reveals a missing diagnostic.
- A design assumption proves wrong.
- A workflow wastes significant time.

Each lesson should include:

- What happened
- Why it happened
- What changed
- What test, rule, or process prevents recurrence

## Project Memory Standards

Project memory stores durable facts, not temporary notes.

Good memory entries:

- Business rules
- Architecture constraints
- Naming conventions
- Known failure patterns
- Release constraints
- Security constraints

Bad memory entries:

- Temporary command output
- Unverified speculation
- Duplicated task descriptions
- Long logs

## Phase Discipline

Do not overbuild documentation early.

Phase 0 creates rules. Future phases populate:

- Architecture
- Risks
- Roadmaps
- Tasks
- Metrics
- Knowledge graph
- Self-improvement data
