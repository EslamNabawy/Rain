# Rain Clean Architecture

Rain is kept as a small Flutter workspace with clear package boundaries instead
of one large app folder.

## Workspace Layout

```text
apps/rain/              Flutter application shell and UI
packages/rain_core/     local data, identity, friends, messages, queues
packages/protocol_brain/ signaling adapters, session state, reconnect policy
packages/peer_core/     WebRTC/data-channel primitives
backend/firebase/       active Firebase signaling infrastructure
docs/                   plans, architecture notes, CI/CD notes
scripts/                build, verification, and asset automation
final product/          only user-facing builds and testable packages
```

## App Source Layout

```text
apps/rain/lib/application/       app bootstrap, Riverpod state, runtime orchestration
apps/rain/lib/core/              configuration and platform/runtime environment readers
apps/rain/lib/infrastructure/    Firebase/signaling adapters and device/app services
apps/rain/lib/presentation/      routes, screens, widgets, theme, and chat UI
```

The Flutter app intentionally keeps domain-heavy behavior in workspace packages
instead of duplicating a `domain` folder inside the app shell:

- `packages/rain_core` owns local persistence, identity, friends, messages, and
  offline queue rules.
- `packages/protocol_brain` owns signaling contracts, presence, sessions, and
  connection state.
- `packages/peer_core` owns low-level WebRTC peer primitives.

## Dependency Direction

```text
apps/rain
  -> packages/rain_core
  -> packages/protocol_brain
  -> packages/peer_core

packages/rain_core
  -> packages/protocol_brain

packages/protocol_brain
  -> packages/peer_core

packages/peer_core
  -> Flutter WebRTC platform APIs
```

## Rules

- UI screens, routing, theme, and Riverpod providers stay in `apps/rain`.
- Local database, identity, friends, messages, and offline queue rules stay in
  `packages/rain_core`.
- Signaling, presence freshness, connection intent, and retry/reconnect policy
  stay in `packages/protocol_brain` unless they are pure UI state.
- Raw peer connection/channel operations stay in `packages/peer_core`.
- Build outputs, extracted test bundles, and old portable packages stay under
  `final product`, never as random root folders.
- New plans and architecture decisions go under `docs`, not a new root folder.
- `apps/rain/test/architecture_layers_test.dart` protects the app layer shape
  and rejects old flat `package:rain/services`, `package:rain/screens`, and
  similar imports.

## Product Folder

The root `final product` folder is the only folder meant for manual app testing.
Current builds stay at the top of that folder. Old extracted builds and previous
portable packages are kept in `final product/archive`.
