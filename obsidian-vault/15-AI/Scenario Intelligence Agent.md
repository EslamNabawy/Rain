# Scenario Intelligence Agent

Last updated: 2026-06-04

## Purpose

Define how an AI testing/intelligence agent should reason about Rain.

The goal is to build and maintain system models, then derive scenarios, risks, and tests from those models. This agent should not randomly invent test cases.

Related: [[AI Operating Notes]], [[System Model]], [[State Graph]], [[Business Rule Graph]], [[Failure Graph]], [[Assumption Register]], [[Test Strategy]].

## Required Startup Reading

Read the normal Rain startup set first:

1. Root `AGENTS.md`.
2. Root `CONTINUITY.md`.
3. [[Project Memory]].
4. [[Master Roadmap]].
5. [[Technical Debt Register]].
6. [[Risk Register]].
7. [[BLOCKERS]].
8. [[Current Architecture]].

Then read the scenario-intelligence set:

1. [[System Model]]
2. [[Feature Map]]
3. [[Dependency Map]]
4. [[State Graph]]
5. [[Business Rule Graph]]
6. [[Assumption Register]]
7. [[Failure Graph]]
8. [[Scenario Coverage Matrix]]
9. [[Test Strategy]]

## Operating Principle

Before making any implementation, analysis, testing, or architecture decision, build or refresh:

- Feature Graph
- Dependency Graph
- State Graph
- Business Rule Graph
- Failure Graph

Store durable graph findings inside Obsidian.

All scenario generation, risk analysis, and testing must be derived from these graphs.

## Scenario Generation Loop

For each target feature or release gate:

1. Select the feature from [[System Model]] and [[Feature Map]].
2. Identify dependencies from [[Dependency Map]].
3. Identify state machines from [[State Graph]].
4. Identify invariants from [[Business Rule Graph]].
5. Select assumptions from [[Assumption Register]].
6. Generate scenarios that violate each relevant assumption.
7. Trace each violation through [[Failure Graph]].
8. Check existing tests in [[Test Strategy]] and [[Coverage Dashboard]].
9. Update [[Scenario Coverage Matrix]] with coverage status and next proof.
10. Record gaps as tests, risks, debt, blockers, or next actions.

## Required Scenario Output

Every scenario batch should include:

- Target feature or flow.
- State path under test.
- Assumption being violated.
- Critical assets touched.
- Expected fail-closed or recovery behavior.
- Existing test evidence, if any.
- Missing test, risk, debt, or blocker.
- Recommended smallest deterministic test.
- Scenario coverage status from [[Scenario Coverage Matrix]].

## Priority Scenario Families

- Auth/account lifecycle: registration, login, logout, expired session, account deletion.
- Presence and connection: fresh/stale/offline/unknown presence, manual disconnect, recovery.
- Voice/video calls: lock claim/repair, terminal room reconciliation, late frames, media setup.
- Connection requests: offline-only routing, quota, mutes, duplicate pending requests.
- Diagnostics: sanitizer, export path, failure taxonomy.
- Update system: stale policy, required update, optional update, release metadata.
- File transfer: disconnect, cancel, backpressure, terminal transfer state.

## Rules

- Do not treat local identity as authenticated truth.
- Do not treat raw online presence as reachability.
- Do not treat Firebase as media transport.
- Do not collapse signaling, media, permission, ICE/TURN, and terminal-state failures.
- Do not create broad scenario lists without linking assumptions and failure chains.
- Do not mark a scenario covered unless the named test or validation was actually run.

## Handoff Requirements

After scenario work:

1. Update [[Assumption Register]] if assumptions changed.
2. Update [[Failure Graph]] for new or refined chains.
3. Update [[Scenario Coverage Matrix]] with covered, partially covered, gap, or accepted status.
4. Update [[Risk Register]] or [[Technical Debt Register]] for uncovered high-impact issues.
5. Update [[Recommended Next Actions]] when priorities change.
6. Run `.\scripts\check_obsidian_vault.ps1` after vault edits.

Related: [[AI Instructions]], [[AI Memory Index]], [[Scenario Intelligence Agent]], [[Scenario Coverage Matrix]].
