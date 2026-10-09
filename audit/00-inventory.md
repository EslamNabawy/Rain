# Rain Audit — Phase 0: Inventory and Tooling

- Date: 2026-10-09
- Working copy: `D:\Rain` (branch `dev`, tracking `origin/dev` at `601647c`)
- Mode: read-only. Nothing was modified, formatted, committed, stashed or reset. The only file written is this one.
- Tests were run against a clean `git archive HEAD` export in a scratch directory, because the working tree does not compile (see §3.2).

## 1. Corrections to the master prompt's assumptions

| Prompt said | Observed | Evidence |
|---|---|---|
| GitHub repo `EslamNabawy/Rain` | `origin` is `https://github.com/AbdogadXNabawy/Rain.git`; older merge commits reference `EslamNabawy/dev` (PR #9) | `git remote -v`, `git log origin/main` (`6e75ead`) |
| 7 GitHub Actions workflows | **8** workflows | `.github/workflows/*.yml` (§6) |
| Dependency direction app → protocol_brain → peer_core / rain_core | `rain_core` depends **on** `protocol_brain` (not the other way). Graph: `rain → {peer_core, protocol_brain, rain_core}`, `rain_core → protocol_brain`, `protocol_brain → peer_core` | `packages/rain_core/pubspec.yaml`, `dart run melos list --graph` |
| backend/firebase contains "rules, functions" | Contains RTDB rules, Remote Config template **and Cloud Functions** (scheduled `onSchedule` jobs + callable connection-request API). Scheduled and deployed functions require the Blaze plan. App default is `rtdbOnly`, so the Spark path does not need them | `backend/firebase/functions/index.js:2,11,55,93,184-196`; `packages/protocol_brain/lib/src/connection_request_backend_mode.dart` |
| AGENTS.md: active copy is `C:\Users\eslam\OneDrive\Desktop\GoodStuff\Rain` | This audit ran on `D:\Rain`. **Open question** which copy is canonical | `AGENTS.md` "Repository Map" |

## 2. Repository map

| Path | Role | lib files (lines, non-generated) | test files (lines) |
|---|---|---|---|
| `apps/rain` | Flutter app (Riverpod 3, go_router 17, flutter_webrtc 1.4) v`1.0.8+9` | 112 (45,904) + 1 generated | 74 (30,670) |
| `packages/peer_core` | WebRTC transport, media, data channel | 15 (4,960) | 3 (2,892) |
| `packages/protocol_brain` | Signaling, sessions, Firebase adapters, signaling cipher | 30 (13,344) | 16 (8,335) |
| `packages/rain_core` | Drift DB, identity/keys, messages | 17 (2,546) + `rain_database.g.dart` | 10 (1,776) |
| `backend/firebase` | `database.rules.json`, `remoteconfig.template.json`, `functions/` (Node 20, firebase-functions 7.2.5, firebase-admin 13.10) | — | `functions/test` (37 tests) |
| `obsidian-vault` | 39 top-level folders, ADR-001…ADR-010 in `11-Decisions` | — | — |
| `.github/workflows` | 8 workflows | — | — |
| `scripts/` | vault validator + QA/device scripts | — | — |
| Root docs | `AGENTS.md`, `CONTINUITY.md` (52 KB), `PROJECT_PROGRESS_TRACKER.md`, `RAIN_DEEP_ANALYSIS_AND_PLAN.md`, `RAIN_ENGINEERING_OVERHAUL_PLAN.md`, `docs/audits/*` (earlier audits exist; Phase 1 must reconcile with them, not duplicate) | — | — |

Untracked/ignored but present locally: `build/`, `artifacts/`, `final product/`, `.idea/`, `.obsidian/`, `deps.txt`, `IDEA.md`, empty `integration_test/` and `test_driver/` at root (not in HEAD), `apps/rain/android/key.properties` and `apps/rain/android/app/rain-local-release.jks` (both correctly ignored).

Vault structure note: duplicated numbering families (`02-Architecture` + `03-Architecture`, `11-Decisions` + empty `14-Decisions`, `13-Blockers` + `14-Blockers`, `12-Tasks` + `15-Tasks`, `AI-Memory` + `19-AI Memory`). Candidate DOC finding for Phase 1.

### 2.1 Package graph and boundary leaks

```
rain ──► peer_core
  │ ──► protocol_brain ──► peer_core
  └──► rain_core ──► protocol_brain
```

- Firebase SDK imports inside the app (outside protocol_brain): `app_bootstrap.dart:1-3`, `firebase_options.dart:3`, `force_update_service.dart:3`, `network_status_service.dart:4`, `turn_credential_service.dart:5`.
- `protocol_brain.dart` re-exports all of `peer_core`, the concrete `firebase_adapter.dart`, `connection_request_rtdb_adapter.dart` and the test fake `src/testing/fake_connection_request_adapter.dart` from its public barrel.
- `protocol_brain` depends on `cloud_functions` (`firebase_adapter.dart:3,2255`) even though the Spark default mode is `rtdbOnly`.
- `rain_core` imports `protocol_brain` (1 import) — storage depends on signaling. Phase 1 should check what it uses.

### 2.2 Largest hand-written files (> 400 lines; 52 files)

Top 15:

| Lines | File |
|---|---|
| 2,947 | `apps/rain/lib/application/runtime/voice_call_runtime.dart` |
| 2,831 (HEAD) / 3,023 (working tree) | `packages/protocol_brain/lib/adapters/firebase_adapter.dart` |
| 2,423 | `apps/rain/lib/application/runtime/rain_runtime_controller.dart` |
| 2,183 | `packages/protocol_brain/lib/adapters/connection_request_rtdb_adapter.dart` |
| 1,830 | `apps/rain/lib/presentation/widgets/home/chat_panel.dart` |
| 1,828 | `apps/rain/lib/application/runtime/voice_call/voice_call_signaling_cleanup_coordinator.dart` |
| 1,803 | `apps/rain/lib/presentation/screens/settings_screen.dart` |
| 1,687 | `apps/rain/lib/presentation/screens/home_screen.dart` |
| 1,476 | `packages/protocol_brain/lib/src/protocol_brain_impl.dart` |
| 1,465 | `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart` |
| 1,451 | `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart` |
| 1,267 | `apps/rain/lib/infrastructure/services/crash_diagnostics_service.dart` |
| 1,208 | `packages/peer_core/lib/src/call/call_media_connection.dart` |
| 1,194 | `apps/rain/lib/infrastructure/signaling/debug_signaling_adapter.dart` |
| 1,163 | `apps/rain/lib/application/state/runtime_providers.dart` |

Function-length (> 60 lines) inventory is deferred to Phase 1 (needs an AST pass, not a line count).

### 2.3 Hygiene markers (hand-written `lib/` only)

| Marker | Count |
|---|---|
| `catch (_)` | 113 |
| `late` | 48 |
| `print(` / `debugPrint(` at line start | 3 |
| `// ignore:` / `ignore_for_file:` | 3 |
| `TODO` / `FIXME` / `HACK` / `XXX` | 0 |

Lint config: root `analysis_options.yaml` uses only `flutter_lints` with `invalid_annotation_target: ignore`; all packages inherit it. No stricter rules (e.g. `avoid_catches_without_on_clauses`, `unawaited_futures`) are enabled.

## 3. Git state

### 3.1 main vs dev divergence

- Merge base: `4798605` (2026-06-10) "Fix call establishment: prevent state updates from being dropped during session transition".
- `origin/main` has **25** commits not on dev; `origin/dev` has **17** commits not on main.
- `git diff --stat origin/main origin/dev`: 362 files, +8,633 / −8,179.
- Files changed since the merge base: 324 on main, 101 on dev, **51 on both** (likely conflicts).

Only on main (highlights): file-level doc headers on all Dart files (`0a65568`, touches nearly every file — the main source of the 324), trace-context scaffolding (`da55e3b`, `e849e29`), `ThrottledProviderObserver` (`d758458`), file-transfer perf (`fa37ce0`, `6e3d18c`), Windows single-instance guard (`378527a`), `rain-ci-cd.yml` + build-artifact workflows, npm audit bumps, app version bump.

Only on dev (highlights): call-engine races and cleanup (`f9b1ec9`, `a2a80a6`), audit phases 1-4 (`5c02b2b`), per-pair cipher core + ECDH + v1/v2 fallback (`55f01b5`), critical fixes C-01…C-06 (`47c7c8b`), chunk DoS prune + ICE relay reserve + SQLCipher key bootstrap (`31d0ab9`), CODEOWNERS, CI hardening, `PROJECT_PROGRESS_TRACKER.md`.

Files changed on both sides (51) include the highest-risk code: `firebase_adapter.dart`, `signaling_adapter.dart`, `signaling_cipher.dart`, `voice_call_session.dart`, `voice_call_runtime.dart`, `voice_call_signaling_cleanup_coordinator.dart`, `file_transfer_runtime.dart`, `core_providers.dart`, `identity_providers.dart`, `call_media_connection.dart`, `data_channel_backpressure.dart`, `default_peer_core.dart`, `rain_database.dart` (+ `.g.dart`), `message_delivery_service.dart`, `main.dart`, `home_screen.dart`, `rain-ci-cd.yml`, functions `package.json`/lock, and 7 vault registers.

Other branches: `origin/dependabot/npm_and_yarn/backend/firebase/functions/multi-0fc86330f8` (2026-09-03, bumps `qs` and `firebase-functions`; unmerged). No other local or remote branches.

### 3.2 Uncommitted change to `firebase_adapter.dart` — confirmed regression, build-breaking

`git diff --stat`: 1 file, +6 / −29. Effect, observed:

1. **Does not compile.** The `catch (_) {` at `firebase_adapter.dart:1509-1510` lost its closing braces, so `_isPermissionDenied` is now declared inside the catch block and the class body never closes. `dart format` fails: `line 3024, column 1 … Expected to find '}'`. `flutter analyze` on protocol_brain: **186 issues** (76 `referenced_before_declaration`, 36 `undefined_method`, 1 `expected_token`, 1 `non_abstract_class_inherits_abstract_member` "Missing concrete implementations of … and 46 more", 43 `unused_element`, 29 infos). Every package that imports protocol_brain (all of them except peer_core) cannot build or test in this working tree.
2. **Logic regressions even if braces were fixed:**
   - `signInWithEmailAndPassword` moved to `:1470`, before the DB writes, and outside the try. If it throws, the freshly created Auth user is never rolled back (orphan Auth account holding the username's email).
   - In the catch at `:1488-1492`, `_auth.signOut()` now runs **before** `_rollbackNewlyCreatedAuthUser`, which only deletes when `_auth.currentUser?.uid == user.uid` (`:1500`). After sign-out `currentUser` is null, so the delete never happens: every failed registration leaves an orphaned Auth user and the username becomes permanently unregistrable.
   - Removed the `backendUserCreated` distinction: a failure in `userSearch`/`setPresence` after the `users/<name>` row was written now tries to delete the Auth user while leaving the DB row, producing a `users/` row whose uid has no Auth account.
   - Removed the friendly "already taken or locked" mapping for permission-denied errors and the `_signOutAfterFailedRegistration` helper.
3. HEAD version of the same file is clean: analyze shows "No issues found!" on the exported HEAD copy.

Recommendation for Phase 1 (not applied): treat this edit as a P0 finding; the HEAD version should be the baseline, and the user should decide whether to discard or rework the local edit.

### 3.3 Secrets and sensitive files

| Item | Status | Evidence |
|---|---|---|
| `apps/rain/android/app/google-services.json` | **Tracked** | `git ls-files` |
| `apps/rain/lib/infrastructure/firebase/firebase_options.dart` (earlier `apps/rain/lib/firebase_options.dart`) | **Tracked** | `git ls-files`, history |
| `apps/rain/tool/dart_defines.local.json` | **Was committed** in `0d8147c` (2026-04-04), removed in `6ff832b` (2026-05-21); still in history. Keys present: `RAIN_BACKEND`, `RAIN_ICE_SERVERS`, `RAIN_UPDATE_URL`, `FIREBASE_DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`. Values were **not** inspected (ICE servers may carry TURN credentials). Now gitignored | `git log --all -- apps/rain/tool/dart_defines.local.json` |
| Release keystore, `key.properties` | Ignored, not in history | `git status --ignored`, history scan |
| `backend/firebase/functions/.env*` | Ignored, not in history | `.gitignore`, history scan |

Firebase client config (API key, project id) in `google-services.json` / `firebase_options.dart` is not a secret by itself, but its safety depends entirely on RTDB rules and API-key restrictions. Phase 1 should verify both and decide whether the historical `dart_defines.local.json` values need rotation.

## 4. Tooling results

Toolchain: Flutter 3.44.4 stable (Dart 3.12.2) at `C:\flutter\bin` (not on PATH), Node v24.19.0. Firebase CLI **not installed**, so RTDB rules/emulator tests could not run locally.

| Command | Where | Result |
|---|---|---|
| `flutter pub get` (workspace) | working tree | OK; `pubspec.lock` unchanged; "124 packages have newer versions incompatible with dependency constraints" |
| `dart run melos list --graph` | working tree | OK (melos 7 via `pubspec.yaml` `melos:` block). Scripts: `pub:get`, `analyze`, `test` only; no `format`, `coverage`, `build_runner` or rules-test scripts |
| `flutter analyze` apps/rain | working tree | No issues |
| `flutter analyze` peer_core | working tree | No issues |
| `flutter analyze` protocol_brain | working tree | **186 issues, exit 1** (caused by §3.2) |
| `flutter analyze` protocol_brain | HEAD export | No issues |
| `flutter analyze` rain_core | working tree | No issues |
| `dart format --set-exit-if-changed --output=none apps packages` | working tree | **Exit 65**: cannot parse `firebase_adapter.dart`; 282 other files formatted, 0 changed |
| same | HEAD export | Exit 0, 283 files, 0 changed |
| `flutter test --coverage` peer_core | HEAD export | **76 passed** (21 s) |
| `flutter test --coverage` protocol_brain | HEAD export | **276 passed** (22 s) |
| `flutter test --coverage` rain_core | HEAD export | **61 passed** (23 s) |
| `flutter test --coverage` apps/rain | HEAD export | **744 passed, 20 skipped** (103 s). Skip reasons: "Requires Firebase emulators", "Legacy control-channel voice path frozen until Firebase signaling." |
| `npm test` backend/firebase/functions | working tree | **37 passed** |
| `npm audit` backend/firebase/functions | working tree | 1 critical (`proxy-addr` 1.1.0-2.0.7), 1 moderate (`qs` ≤6.15.3); fix available (open dependabot branch covers `qs`) |
| `.\scripts\check_obsidian_vault.ps1` | working tree | **Fails**: 7 registers have stale "Last updated" (2026-08-21). The gate fails on elapsed time alone, so CI turns red with no code change |
| `build_runner` | — | Not run: generated `rain_database.g.dart` is present and analyze is clean |
| Platform builds | — | Not run (AGENTS.md: only on request) |

### 4.1 Line coverage (lcov, HEAD export)

lcov only lists files loaded by at least one test, so untouched files are not counted; real coverage is lower.

| Package | Covered / total | % |
|---|---|---|
| peer_core | 1,581 / 2,163 | 73.1 |
| protocol_brain | 2,845 / 5,206 | 54.6 |
| rain_core | 1,447 / 3,314 (772 / 1,169 excluding `rain_database.g.dart`) | 43.7 (66.0) |
| apps/rain | 13,368 / 19,427 | 68.8 |

Notable gaps: **`firebase_adapter.dart` 0 / 1,277 (0%)**; `connection_request_rtdb_adapter.dart` 73%; `protocol_brain_impl.dart` 72%; `rain_database.dart` 43%; `debug_signaling_adapter.dart` 12%; `home_screen.dart` 23%; `chat_panel.dart` 27%; `friend_profile_screen.dart` and `file_transfer_bubble.dart` 0%.

### 4.2 `flutter pub outdated` (direct dependencies, abbreviated)

| Package | Current | Latest | Note |
|---|---|---|---|
| flutter_webrtc | 1.4.1 | 1.6.2+hotfix.4 | upgradable within constraint |
| firebase_core / auth / database / remote_config | 4.9.0 / 6.5.1 / 12.4.1 / 6.5.1 | 4.15.0 / 6.7.0 / 12.6.0 / 6.7.0 | upgradable |
| cloud_functions | 6.3.1 | 6.5.0 | only needed for non-Spark mode |
| drift / drift_flutter | 2.33.0 / 0.3.0 | 2.35.2 / 0.3.1 | upgradable |
| sqlite3 | 3.3.1 | 3.7.0 | constraint caps at 3.5.2; relevant to the SQLCipher decision |
| file_picker | **12.0.0-beta.3** | 13.1.0 | **beta in production deps** |
| flutter_local_notifications | 21.0.0 | 22.3.1 | major behind |
| go_router | 17.2.3 | 18.0.2 | major behind |
| flutter_secure_storage | 10.3.1 | 11.2.0 | major behind; holds the key store |
| flutter_riverpod | 3.3.1 | 3.4.3 | upgradable |

No `dependency_overrides` and no `pubspec_overrides.yaml` in the workspace (melos sets `usePubspecOverrides: true` but none exist). Full output was captured during the run; Phase 1 will cite specifics.

## 5. Firebase backend snapshot

- `firebase.json`: emulators auth:9099, database:9000; rules `database.rules.json`; Remote Config template; functions `nodejs20`.
- Functions: `cleanupPresence`, `cleanupRooms`, `cleanupVoiceCalls` (`onSchedule`), plus 9 connection-request exports. Scheduled functions need Blaze. Phase 1 must confirm which RTDB cleanup paths exist in `rtdbOnly` mode, because on Spark these janitors never run.

## 6. CI/CD workflows (8)

| Workflow | Triggers | Jobs | Notes |
|---|---|---|---|
| `ci.yml` "CI/CD" | push `**`, tags `v*.*.*`, PR → `main`, **`develop`** | dependency-review, workflow-lint, quality-gate, static-analysis, tests, firebase-backend, firebase-emulator-tests, android-build, windows-config-check, test-gates, release-artifacts, required-checks | PR target `develop` does not exist (branch is `dev`) |
| `main-merge-gate.yml` | PR → main, dispatch | workflow-lint, workspace-validation, firebase-backend, firebase-emulator-tests, android-debug-abi, windows-demo-artifact, android-demo-artifacts, required-main-merge-checks | overlaps ci.yml |
| `rain-ci-cd.yml` | push main/dev, PR → main, dispatch | test, build-windows, build-android, release | uses `upload-artifact@v4`/`download-artifact@v4` while others use v7/v8; third overlapping CI |
| `documentation-vault.yml` | push dev/main + PR on vault paths | obsidian-vault | `actions/checkout@v4` (others v5); fails on date staleness |
| `build-artifacts.yml` | dispatch | hard-release-gate, build-windows, build-android, publish-test-release | release secrets |
| `fast-release.yml` | dispatch | resolve-target, ci-status-gate, prepare-release, build-android, build-windows, required-checks | release secrets |
| `validated-release.yml` | dispatch | resolve-target, workflow-lint, workspace-validation, firebase-backend, firebase-emulator-tests, release-evidence, validation-gate, build-windows, build-android, publish-release, required-checks | release secrets |
| `release.yml` | dispatch (tag) | resolve-target … create-release, required-checks | release secrets |

- Every action is pinned by **tag**, none by SHA (`subosito/flutter-action@v2`, `softprops/action-gh-release@v2`, `actions/*@v4-v8`).
- Secrets used: `RAIN_RELEASE_DART_DEFINES_JSON`, `RAIN_RELEASE_KEY_ALIAS`, `RAIN_RELEASE_KEY_PASSWORD`, `RAIN_RELEASE_KEYSTORE_BASE64`, `RAIN_RELEASE_STORE_PASSWORD`, `GITHUB_TOKEN`.
- Four release-style workflows (build-artifacts, fast-release, validated-release, release) and three CI-style workflows (ci, main-merge-gate, rain-ci-cd) overlap. Phase 1 will assess redundancy and failing state (no CI run history was fetched in Phase 0).

## 7. Progress tracker snapshot (dev only)

`PROJECT_PROGRESS_TRACKER.md` exists only on dev. It claims "10 / 21 tasks DONE"; TASK-005 reverted/blocked; TASK-001 (per-pair E2E) crypto core done, **adapter wiring deferred**; TASK-002 (SQLCipher) key bootstrap done, **native open path deferred** (EOL `sqlcipher_flutter_libs`). Each "done" claim is to be verified against code in Phase 1 (dimension L).

## 8. Open questions for Solom

1. Which copy is canonical: `D:\Rain` or `C:\Users\eslam\OneDrive\Desktop\GoodStuff\Rain` (per AGENTS.md)? And is `AbdogadXNabawy/Rain` the correct GitHub remote?
2. The uncommitted `firebase_adapter.dart` edit breaks the build and regresses registration rollback. Was it intentional work in progress, or can later phases treat HEAD as the baseline?
3. Which branch should the fix plan target: reconcile `dev` into `main`, `main` into `dev`, or a fresh integration branch? (51 files changed on both sides.)
4. Is the Firebase project actually on Spark today? If so, the Cloud Functions (scheduled cleanup, callable API) cannot be deployed and should be marked non-Spark.
5. Do the historical `dart_defines.local.json` values (ICE/TURN servers, Supabase anon key) still work? If so, they need rotating.
