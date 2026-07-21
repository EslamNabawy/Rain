# Repository Map

Last updated: 2026-07-21

## Purpose

Provide the vault-level repository discovery map. This note is linked to [[Current Architecture]], [[System Ownership Map]], and [[Domain Map]].

## Verified Areas

| Area | Expected Path | Notes |
| --- | --- | --- |
| Flutter app | `apps/rain` | [[Frontend Architecture]], [[Feature Map]] |
| Peer/WebRTC core | `packages/peer_core` | [[Signaling Architecture]], [[CallMediaCoordinator]] |
| Protocol/signaling core | `packages/protocol_brain` | [[Lease Management]], [[Call State Machine]] |
| Core domain/storage | `packages/rain_core` | [[Database Architecture]], [[Database Schema]] |
| Firebase backend | `backend/firebase` | [[Firebase Architecture]], [[Rules Strategy]] |
| Documentation vault | `obsidian-vault` | [[Project Home]], [[Knowledge Graph Index]] |
| GitHub workflows | `.github/workflows` | [[CI-CD Roadmap]], [[Release Gates]] |
| Local scripts | `scripts` | [[Build Process]], [[Release Gates]] |
| App integration tests | `apps/rain/integration_test` | [[Test Strategy]], [[Emulator Test Matrix]]; includes opt-in Phase 10 `device_media_reality_proof_test.dart`. |
| Root integration tests | `integration_test`, `test_driver` | [[Test Strategy]], [[Coverage Dashboard]] |

## Workspace Packages

- Root `pubspec.yaml` declares a Dart workspace for `apps/rain`, `packages/peer_core`, `packages/protocol_brain`, and `packages/rain_core`.
- Melos scripts are defined in root `pubspec.yaml` for `pub:get`, `analyze`, and `test`.
- App code depends on all three local packages.
- `protocol_brain` depends on `peer_core`.
- `rain_core` depends on `protocol_brain`.

## Generated/Non-Source Areas

- `.dart_tool`
- `build`
- `apps/rain/build`
- `artifacts`
- `final product`

These folders may contain useful build outputs but are not treated as primary architecture source.

## Semantic Validation Contract

`scripts/check_obsidian_vault.ps1` is the local preflight for vault structure and operational truth. It validates required files, unique note titles, wiki-links, inbound/outbound links, and the semantic registers below.

| Register | Required Shape | Enforcement |
| --- | --- | --- |
| [[Audit Resolution Tracker]] | Resolution matrix rows with epic, feature, task, status, and next step; senior audit overlay rows with owner, priority, evidence, release impact, and status. | Missing row fields fail validation; P0/P1 senior-audit rows must carry evidence-required text. |
| [[Risk Register]] | Senior audit risk overlay rows with owner, severity, detection, release impact, and status; active risks with probability, severity, mitigation, detection, owner, links, and status. | Missing fields fail validation; probability, severity, and active risk status must use supported values. |
| [[Technical Debt Register]] | Each `TD-###` section must expose category, status, priority, owner, title, description, risk, files affected, related systems, roadmap tasks, and resolution strategy. | Missing fields fail validation; P0/P1 debt needs a resolution strategy; closed or accepted debt needs validation or acceptance evidence. |
| [[BLOCKERS]] | Senior audit blocker overlay rows need blocking status, mapped blocker, owner, and exit evidence; each `BLK-###` section needs status, severity, owner, type, related risks/tasks/debt, impact, workaround, parallel path, exit criteria, and detection strategy. | Missing fields fail validation; High/Critical blockers need a resolution plan; closed blockers need evidence. |
| [[Project Metrics]] | Evidence ledger tables require date, branch, base commit, scope, command, result, and evidence. | Missing ledger fields fail validation; result must be Passed, Failed, Skipped, or Blocked; passed rows cannot carry pending evidence. |
| [[Recommended Next Actions]] and this note | Must carry parseable `Last updated: YYYY-MM-DD`. | Operational semantic notes become stale after the review window and fail validation. |

This contract is intentionally narrower than full truth verification. It catches unsupported operational claims before release planning, while [[Release Gates]] and command/test evidence still decide whether a specific artifact can be promoted.

Related: [[Knowledge Graph Index]], [[System Ownership Map]], [[Domain Map]], [[Durable Facts]].
