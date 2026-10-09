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
