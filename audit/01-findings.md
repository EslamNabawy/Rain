# Findings

Source of truth: repository at `dev` 601647c plus `audit/00-inventory.md`. Findings follow the format in `audit/prompts/rain-orchestrator.xml`.

## A. Repo health and git

### GIT-001 Uncommitted `firebase_adapter.dart` edit breaks the build and regresses registration rollback
- Severity: P0 | Confidence: High
- Location: `packages/protocol_brain/lib/adapters/firebase_adapter.dart:1469-1519`
- Evidence: (audit/00-inventory.md §3.2, observed in Phase 0)
```
flutter analyze packages/protocol_brain -> 186 issues, exit 1
dart format -> "line 3024, column 1 ... Expected to find '}'"
firebase_adapter.dart:1503 / :1509  } catch (_) {   (closing braces lost)
```
- Why it matters: working tree cannot compile; every package importing protocol_brain cannot build or test. Even if braces were restored, `_auth.signOut()` runs before `_rollbackNewlyCreatedAuthUser` (which only deletes when `currentUser?.uid == user.uid`), so each failed registration leaves an orphaned Auth user and the username is permanently unregistrable.
- Fix: restore HEAD version (T3.1); WIP preserved in `audit/wip/firebase_adapter-uncommitted.patch`.
- Effort: S

### GIT-002 `main` and `dev` diverged with 51 files changed on both sides
- Severity: P1 | Confidence: High
- Location: merge-base `4798605`; `origin/main` +25 commits, `origin/dev` +17
- Evidence: computed with `git diff --name-only 4798605 origin/{main,dev}` intersection
```
51 overlap files: apps/rain 18, packages/protocol_brain 7, packages/rain_core 5,
packages/peer_core 4, docs/audits 5, obsidian-vault 8, backend/firebase/functions 2,
.github/workflows 1 (rain-ci-cd.yml), CONTINUITY.md, README.md
```
- Why it matters: highest-risk code (`firebase_adapter.dart`, `signaling_cipher.dart`, `voice_call_session.dart`, `voice_call_runtime.dart`, `file_transfer_runtime.dart`, `rain_database.dart` and its `.g.dart`, `default_peer_core.dart`, `data_channel_backpressure.dart`) changed on both sides; a naive merge silently picks one side of security or call-logic fixes. `rain_database.g.dart` cannot be hand-merged.
- Fix: reconcile on `integration/main-dev` per the Phase 5 conflict policy; regenerate `rain_database.g.dart` with build_runner.
- Effort: L

### GIT-003 `dart_defines.local.json` is in git history (commits 0d8147c, 6ff832b)
- Severity: P0 | Confidence: High
- Location: `apps/rain/tool/dart_defines.local.json` (added `0d8147c`, removed `6ff832b`)
- Evidence:
```
git log --all -- apps/rain/tool/dart_defines.local.json
6ff832b Clean up Rain app and CI dependencies
0d8147c feat(OpenCode): Phase 1 architecture & validation artifacts ...
keys (names only): RAIN_BACKEND, RAIN_ICE_SERVERS, RAIN_UPDATE_URL, FIREBASE_DATABASE_URL, SUPABASE_URL, SUPABASE_ANON_KEY
```
- Why it matters: values were not inspected (R5). `RAIN_ICE_SERVERS` may carry TURN credentials and `SUPABASE_ANON_KEY` is a bearer credential. They remain recoverable by anyone with read access to the repo or a clone.
- Fix: owner rotates TURN credentials and the Supabase anon key if still live (decision D5). Do not rewrite history (R2). File is gitignored now.
- Effort: S (owner action)

### GIT-004 Tracked Firebase client config (`google-services.json`, `firebase_options.dart`)
- Severity: P3 | Confidence: Medium
- Location: `apps/rain/android/app/google-services.json`, `apps/rain/lib/infrastructure/firebase/firebase_options.dart`
- Evidence: `git ls-files` lists both.
- Why it matters: client Firebase config is not secret; its safety depends on RTDB rules and API key restrictions. Severity stays P3 provided those hold; see SEC-xxx findings in section E (rules are traced in SEC checks) and the owner action on API key restrictions.
- Fix: none in repo; owner restricts the API key (Android package + SHA-1, API allow-list) in Google Cloud console.
- Effort: S (owner action)
- Confirm by: T1.5 rules trace (see SEC findings); API key restriction can only be checked in the console.

### GIT-005 Unmerged dependabot branch for `qs` / `firebase-functions`
- Severity: P3 | Confidence: High
- Location: `origin/dependabot/npm_and_yarn/backend/firebase/functions/multi-0fc86330f8`
- Evidence:
```
d857fe0 chore(deps): bump qs and firebase-functions
```
- Why it matters: it overlaps with the npm audit fix in T3.4 (and `package.json`/lock are among the 51 both-sided files), so merging it separately will conflict.
- Fix: do T3.4 `npm audit fix`; then close the dependabot branch/PR once the lock matches.
- Effort: S

### GIT-006 Stray empty root dirs and overlapping plan documents
- Severity: P3 | Confidence: High
- Location: `integration_test/`, `test_driver/`, `RAIN_DEEP_ANALYSIS_AND_PLAN.md` (39,684 B), `RAIN_ENGINEERING_OVERHAUL_PLAN.md` (55,603 B), `docs/audits/*` (11 files)
- Evidence:
```
git ls-files integration_test test_driver -> 0 files; both dirs exist locally (empty, untracked)
```
- Why it matters: empty dirs are not in git (harmless locally); two large root plan documents overlap `docs/audits/PROJECT_DEEP_ANALYSIS.md` and `FLAWS_AND_FIXES_TODO.md`, so there are several competing sources of truth for the same backlog.
- Fix: move the two root plans into `docs/audits/` (or mark superseded) and link them from the vault; delete the empty local dirs.
- Effort: S

## B. Monorepo structure

### ARCH-001 `rain_core` (storage) depends on `protocol_brain` (signaling) for two small types
- Severity: P2 | Confidence: High
- Location: `packages/rain_core/lib/src/drift_connection_memory_store.dart:4`, `packages/rain_core/lib/voice_call/voice_call_frame.dart:1`
- Evidence:
```
voice_call_frame.dart:1  export 'package:protocol_brain/protocol_brain.dart' show CallMediaMode, VoiceCallFrame, VoiceCallFrameType;
drift_connection_memory_store.dart:4  import 'package:protocol_brain/protocol_brain.dart';   // ConnectionMemoryStore, ConnectionMemory
```
- Why it matters: importing the whole `protocol_brain` barrel drags Firebase (auth, database, cloud_functions) into the storage package, so a pure-DB change recompiles and retests signaling and the graph `rain_core -> protocol_brain -> peer_core` cannot be reordered. rain_core only needs `ConnectionMemory`, `ConnectionMemoryStore`, `VoiceCallFrame`, `VoiceCallFrameType`, `CallMediaMode`.
- Fix: extract these value types into a dependency-free package (e.g. `rain_models`) or into `rain_core`, and have `protocol_brain` depend on it; at minimum import `package:protocol_brain/src/...` narrowed `show` instead of the barrel.
- Effort: M

### ARCH-002 `protocol_brain` public barrel exports concrete Firebase adapters and a test fake
- Severity: P2 | Confidence: High
- Location: `packages/protocol_brain/lib/protocol_brain.dart:44`, `:51`, `:57`
- Evidence:
```
44: export 'adapters/firebase_adapter.dart';
51: export 'src/connection_request_rtdb_adapter.dart';
57: export 'src/testing/fake_connection_request_adapter.dart';
```
- Why it matters: any importer of the barrel (including `rain_core`, see ARCH-001) gets production Firebase code and `FakeConnectionRequestAdapter` in its API; the fake can be instantiated in release code by mistake. `src/testing/` also holds `fake_voice_signaling_adapter.dart` and `live_smoke_peer_core.dart`, which are not exported, so the testing split is already inconsistent.
- Fix: move fakes to `package:protocol_brain/testing.dart` (separate entry point); split `protocol_brain.dart` into an interface barrel and `protocol_brain_firebase.dart` for adapters.
- Effort: M

### ARCH-003 App imports the Firebase SDK in four places beyond bootstrap
- Severity: P2 | Confidence: High
- Location: `apps/rain/lib/application/bootstrap/app_bootstrap.dart:1-3`, `apps/rain/lib/infrastructure/services/force_update_service.dart:3`, `apps/rain/lib/infrastructure/services/network_status_service.dart:4`, `apps/rain/lib/infrastructure/services/turn_credential_service.dart:5`, `:165`
- Evidence:
```
turn_credential_service.dart:165  final user = FirebaseAuth.instance.currentUser;
network_status_service.dart:101   final FirebaseDatabase _database;
```
- Why it matters: `app_bootstrap.dart` and `firebase_options.dart` are legitimate composition-root uses. `force_update_service.dart` (Remote Config) and `network_status_service.dart` (injects `FirebaseDatabase`) are infrastructure services and acceptable. `turn_credential_service.dart:165` reads the `FirebaseAuth.instance` singleton directly instead of an injected auth/identity provider, so it cannot be tested without Firebase and bypasses the app's identity layer.
- Fix: inject a `Future<String?> Function()` ID-token/uid getter into `TurnCredentialService` from `identity_providers.dart`.
- Effort: S

### ARCH-004 `cloud_functions` is a hard dependency of `protocol_brain` although Spark default is `rtdbOnly`
- Severity: P2 | Confidence: High
- Location: `packages/protocol_brain/pubspec.yaml:22`, `packages/protocol_brain/lib/adapters/firebase_adapter.dart:3`, `:27`, `:35`, `:44`, `:2284` (HEAD)
- Evidence:
```
firebase_adapter.dart:35  _functions = functions ?? FirebaseFunctions.instance,
firebase_adapter.dart:2284  } on FirebaseFunctionsException catch (error) {
```
- Why it matters: `FirebaseFunctions.instance` is eagerly created in the constructor even in `rtdbOnly` mode; the plugin adds binary size and a Blaze-only code path to a Spark app (constraint D4). It is not a runtime failure, but it blurs which features work on Spark.
- Fix: make `functions` a lazy getter and move the callable path behind `ConnectionRequestBackendMode.cloudFunctions`; longer term, move callable code to a separate adapter file/package.
- Effort: M

### ARCH-005 Melos scripts cover only pub get, analyze and test
- Severity: P3 | Confidence: High
- Location: `pubspec.yaml:15-19`
- Evidence:
```
scripts:
  pub:get: dart run melos exec -- flutter pub get
  analyze: dart run melos exec -- flutter analyze
  test: dart run melos exec --concurrency=1 -- flutter test
```
- Why it matters: format check, coverage, build_runner (needed for `rain_database.g.dart`), functions tests and rules tests are run by hand or only in CI, so local and CI behavior drift.
- Fix: add `format`, `format:check`, `coverage`, `build_runner`, `functions:test`, `rules:test` scripts.
- Effort: S

### ARCH-006 Beta and end-of-life dependencies in production
- Severity: P2 | Confidence: High
- Location: `apps/rain/pubspec.yaml:17` (`file_picker: ^12.0.0-beta.3`), `pubspec.lock:1287-1302` (`sqlite3` 3.3.1, `sqlite3_flutter_libs` 0.6.0+eol), `packages/rain_core/pubspec.yaml:22`
- Evidence:
```
apps/rain/pubspec.yaml:17  file_picker: ^12.0.0-beta.3          (latest stable 13.1.0, audit/00-inventory.md §4.2)
pubspec.lock  sqlite3_flutter_libs  version: "0.6.0+eol"
```
- Why it matters: a pre-release plugin handles every incoming/outgoing file selection; an `+eol` package ships the native SQLite binaries and blocks the SQLCipher route (see SEC finding on DB encryption). One major behind: `go_router` 17 vs 18, `flutter_secure_storage` 10 vs 11 (holds the key store), `flutter_local_notifications` 21 vs 22.
- Fix: move `file_picker` to a stable 13.x after smoke-testing picking on Android and Windows; plan sqlite3 build-hooks migration with the DB encryption decision; defer other major bumps to the backlog.
- Effort: M

### ARCH-007 Lint set is only `flutter_lints`
- Severity: P3 | Confidence: High
- Location: `analysis_options.yaml:1-10`
- Evidence:
```
include: package:flutter_lints/flutter.yaml
errors: invalid_annotation_target: ignore
```
- Why it matters: 113 `catch (_)` and unawaited futures in call/transfer paths are not flagged; the codebase mixes swallowed errors with real handling.
- Fix: add under `linter: rules:` `unawaited_futures`, `avoid_catches_without_on_clauses`, `only_throw_errors`, `cancel_subscriptions`, `close_sinks`, `avoid_print`, `prefer_final_locals`; introduce them gradually (enable, then baseline ignores).
- Effort: M
