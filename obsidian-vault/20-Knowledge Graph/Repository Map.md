# Repository Map

Last updated: 2026-06-03

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
| App integration tests | `apps/rain/integration_test` | [[Test Strategy]], [[Emulator Test Matrix]] |
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

Related: [[Knowledge Graph Index]], [[System Ownership Map]], [[Domain Map]], [[Durable Facts]].
