# Continuity

Last updated: 2026-08-29
Branch: `chore/wire-tracing-scaffolds` (off `feature/local-design-and-tracing`)

## Active Work

Two parallel streams. The cross-platform remediation stream (B1 in progress 2026-08-26) continues on `main`; this side branch added a tracing overlay on top of `feature/local-design-and-tracing`.

### Tracing overlay (2026-08-29, this branch)

Adopted PR1+PR3 of `docs/plans/2026-08-27-rain-tracing-implementation-guide.md` with explicit scope cut ([[ADR-011]]). Wired scaffolds into `apps/rain/lib/infrastructure/diagnostics/tracing/`, replaced `RainDebugProviderObserver` with `ThrottledProviderObserver` in `RainStartupApp`, attached `AppNavigationObserver` to the `GoRouter` observers list, and wrapped `IdentityController.register` and `RainRuntimeController._startCall` in `TraceContext.runAsync` so every `auth/*` and `call/*` event inside shares one `traceId`. The `voice_call_tracing_patch.dart` file is not imported (its `VoiceFailureTaxonomy` enum competes with `CallErrorClassifier`).

Slices deferred to follow-up work:
- `traceId` in heartbeat, presence watches, signaling writes, file transfer, and `createOutgoingCall`.
- Drift event persistence, debug overlay UI, `/debug/traces` page.
- Structural `==`/`hashCode` on `PeerConnectivitySnapshot` and `ConnectionDiagnostics`.
- New tracing tests; current suite does not exercise the new code paths.

### Cross-platform remediation (on `main`, 2026-08-26 → 2026-08-29)

- R1 lint sweep (commit `595a0fe`): 254 `library;` directives + 1 doc-comment fix; repaired pre-existing CI `--fatal-infos` breakage at HEAD `0a65568`.
- A1+A2 file-transfer hot loop (commit `6e3d18c`): receiver SHA-256 via `Isolate.run`; incoming transfer record cache with `clearTransferRuntimeState` as sole invalidation funnel; per-chunk `loadById` removed. Sender-side incremental hash intentionally kept on main isolate (rationale in TD-008 progress note).
- T1 startup test harness repair (commit `30c46cc`): `_runtimeProviderContainer` now passes a non-demo signaling key; fixed 7 pre-existing test failures caused by the hard cipher-key rejection.
- Docs sync (commit `8438e45`).
- A3+A4 (slice 2): binary frames filtered from connectivity fan-out + leading-edge 250 ms data-event throttle (`data_event_throttle_test.dart`); receive flushes via `FileTransferFlushPolicy` in rain_core (first write always flushes for fail-fast disk errors, then 512 KiB batches) (commit `fa37ce0`).
- A5 DEFERRED 2026-08-26: HomeScreen consumer extraction caused shell body height collapse (Row 320×0 probe, Stack→Container→Column→Expanded chain) — reverted to HEAD, full suite green. Next attempt: in-Row Consumer + `select` projections preserving constraints.
- B1 IN PROGRESS 2026-08-26: `windows/runner/main.cpp` single-instance mutex `Local\Rain.SingleInstance` added (CreateMutexW + MessageBox + CloseHandle).

Next slice on `main`: **B1 validation + B2/B3/B4** — camera preflight wiring, exit-path repair, min window size.

Decision gates G1–G6 remain unresolved; gated tasks are not started.

## Validation Evidence Log

| Date | Command | Result |
|------|---------|--------|
| 2026-08-26 | `git status --short --branch` (main) | clean, `main...origin/main` at `0a65568` |
| 2026-08-26 | `flutter test test\friend_flow_test.dart` (apps/rain, post-slice) | 127 passed, 10 skipped, incl. new cache-count regression test |
| 2026-08-26 | `flutter analyze` baseline check (stash verified) | pristine HEAD: 179 infos in apps/rain → pre-existing |
| 2026-08-26 | `flutter test test\runtime_startup_test.dart` baseline check (stash verified) | pristine HEAD: same 7 failures → pre-existing |
| 2026-08-26 | `dart run melos run analyze` (root) | SUCCESS — all 4 packages |
| 2026-08-26 | `dart run melos run test` (root) | SUCCESS — all packages |
| 2026-08-26 | `.\scripts\check_obsidian_vault.ps1` after docs sync | passed (198 files) |
| 2026-08-26 | slice 2: `flutter test` friend_flow+network_loss+throttle focused runs | all passed (incl. disk-failure regression after first-write-flush fix) |
| 2026-08-26 | slice 2: `dart run melos run analyze` + `melos run test` (root) | both SUCCESS |
| 2026-08-29 | `dart pub get` (chore/wire-tracing-scaffolds) | Got dependencies; 105 packages have newer versions incompatible with constraints (pre-existing) |
| 2026-08-29 | `dart run melos run analyze` (chore/wire-tracing-scaffolds) | SUCCESS — `peer_core`, `protocol_brain`, `rain_core`, `rain` all report "No issues found!" after fixing 4 scaffold warnings (`_logTap` unused, `use_null_aware_elements`, `ThrottledProviderObserver` not base/final/sealed, `MaterialApp.router.navigatorObservers` does not exist) and one scaffold import path (`../services/...` resolved to `package:rain/...`) |
| 2026-08-29 | `dart run melos run test` (chore/wire-tracing-scaffolds) | SUCCESS — `peer_core` 75, `protocol_brain` 267, `rain` 741 (20 skipped pre-existing), `rain_core` 51; 1134 tests passed, 0 failed |

## Notes / Blockers

- Tracing slice is on `chore/wire-tracing-scaffolds` worktree, not yet committed or pushed.
- New R-023 / TD-024 capture the residual risk and gap; follow-up work tracked in [[Recommended Next Actions]].
- No new BLOCKERS created. No existing blocker status changed.
- Cloud CI proof for the tracing branch has NOT been run — no push was requested.
- No device/emulator runs executed this session; tracing overlay does not require device proof for its own scope.
- The pre-2026-08-29 cross-platform remediation notes remain in effect on `main`; A5 retry is the next queue item.
