# Rain Audit and Hardening: Final Report

Date: 2026-10-10. Working copy `D:\Rain`. Branches: `audit/rain-hardening` (cut from `dev` `601647c`) and `integration/main-dev` (`origin/main` merged into the audit branch). Nothing was merged into `main` or `dev`. Details: `audit/01-findings.md` (65 findings), `02-refactor-targets.md`, `03-plan.md`, `04-vault-updates.md`, `STATE.md`.

## Results

| Phase | Tasks and commits |
|---|---|
| 0 Setup | T0.1 `cd7d51b` |
| 1 Findings | T1.1 `5ac327b`, T1.2 `59a5c83`, T1.3 `a36e2e1`, T1.4 `97b3597`, T1.5 `83a76b5`, T1.6 `2751bf1`, T1.7 `0f4ea59`, T1.8 `f5129ea`, T1.9 `bddcc04`, T1.10 `212d609`, T1.11 `f93c613`, T1.12 `ccff652` |
| 2 Plan | T2.1 `3e5dc01`, T2.2 `fdffe84` + `03f9cdd`, T2.3 `55713e2` |
| 3 Baseline | T3.1 `b466768`, T3.2 `0fda669`, T3.3 `30992ec`, T3.4 `4943068`, T3.5 `7146e85` |
| 4 Fixes | T4.02 `4f28f0a`, T4.04 `18d275e`, T4.05 `253d8cb`, T4.06 `9155f4b` (reduced), T4.07 `13fdff2`, T4.08 `4a7ed16`, T4.09 `deaef93`, T4.10 `ad79d19`, T4.11 `71138df`, T4.12 `e1e4cb9`, T4.13 `696e78e`, T4.14 `03078d6`, T4.16 `ccb88dd`, T4.17 `6ff2037`, T4.18 `fda079f`, T4.20 `c8186f8`, T4.21 `4feaa3f`, T4.22 `95778ab`, T4.23 `b9e5348` |
| 5 Reconcile | T5.1 `95cbb07` on `integration/main-dev` (38 conflicts resolved) |
| 6 Vault and report | T6.1 `ebcca4e`, T6.2 this report |

Findings: 65 (2 P0, 10 P1, 29 P2, 24 P3). Two findings were corrected while executing fixes: RTC-003 was downgraded to P3 (release validation already rejects the public relay) and DB-003 to P3 (no table declares a foreign key, so the check is unreachable).

Fixed in code: GIT-001, CI-001, CI-003, CI-004, CI-005/BE-002, SEC-001 (app side), SEC-004, SEC-005, SEC-007, SIG-001, SIG-002, SIG-003, SIG-005, RTC-001, RTC-002, APP-001 (presence part), APP-002, APP-003, DB-002, ARCH-002, ARCH-003, ARCH-004. Tests added for DB-001, TEST-001 (registration rollback flow) and SEC-003 (encryption state is reported, storage is still plaintext).

## Blocked and skipped

| Card | Reason |
|---|---|
| T4.01 RTDB rules test harness (BE-001) | Blocked. `npx --yes firebase-tools@13 emulators:exec --only database "node -e 1"` in `backend/firebase` fails: `Error: Could not spawn `java -version`. Please make sure Java is installed and on your system PATH.` No Java on this machine. |
| T4.03 `signingPublicKey` rule (SEC-001 rules part) | Blocked by T4.01 (rule changes require RULES_TEST). |
| T4.19 `userSearch` query limits (SEC-006) | Blocked by T4.01. |
| T4.15 corrupt-database recovery (DB-003) | Skipped: the premise was wrong; no foreign keys exist. |
| T4.06 database and auth ports | Reduced to extracting and testing the registration rollback flow; ports for the whole adapter remain in the backlog. |

Not executed: platform builds (R7), emulator integration suites, Android and Windows device runs, anything touching the live Firebase project.

## Owner actions

1. Rotate or revoke the TURN credentials and Supabase anon key from `apps/rain/tool/dart_defines.local.json` history (commits 0d8147c, 6ff832b) if still live (GIT-003).
2. Install JDK 21, then run T4.01, T4.03 and T4.19 (rules tests and the `signingPublicKey` and `userSearch` rule changes). Until the rule exists, registration still tries to write `users/<name>/signingPublicKey`; the app now ignores a rejection, but confirm that the deployed rules equal `backend/firebase/database.rules.json` (SEC-001 was assessed from the repo copy).
3. Restrict the Firebase API key, decide on App Check and sign-up throttling (GIT-004, SEC-006).
4. Decide the local database encryption option in `obsidian-vault/11-Decisions/ADR-013.md` (recommended: SQLCipher through the `sqlite3` build hook with a verified migration); test on Android and Windows.
5. Device tests: audio call survives Home for 60 s on Android 13+ and a minimized window on Windows; decide on a call foreground service (APP-001 part 2); crossed invites within 50 ms; an app kill mid-call (SIG-003); file picking before bumping `file_picker` (ARCH-006).
6. GitHub: after workflow consolidation (backlog CI-002) update branch protection required checks; protect `main` and `dev`. Review the new `.github/dependabot.yml` against the one on `main`.
7. Review `integration/main-dev` and decide when to merge it into `main`. Merge notes: vault IDs in this branch were numbered to avoid collisions with `main` (R-024..R-032, TD-025..TD-030, ADR-012, ADR-013); the doc layout follows `dev` (`docs/plans`, `docs/audits`) and `main`'s duplicate copies were removed; `rain_database.g.dart` was regenerated with build_runner.
8. Confirm `D:\Rain` as the canonical copy and update `AGENTS.md` (DOC-006).
9. Measure Firebase RTDB usage with five accounts for 24 h before changing the 10-second heartbeat (BE-003).
10. A stray empty-subject commit `ef1c897` exists on `audit/rain-hardening` (a helper script was called without arguments); history was not rewritten (R2).

## Before and after

| Check | Before (dev `601647c` + uncommitted edit) | After (`audit/rain-hardening`) | After merge (`integration/main-dev`) |
|---|---|---|---|
| `flutter analyze` | protocol_brain 186 issues (working tree) | no issues, 4 packages | no issues |
| `dart format` | exit 65 (parse error) | 291 files, 0 changed | 297 files, 0 changed |
| peer_core tests | 76 | 80 | 80 |
| protocol_brain tests | 276 | 294 | 294 |
| rain_core tests | 61 | 67 | 69 |
| apps/rain tests | 744 + 20 skipped | 760 + 20 skipped | 774 + 20 skipped |
| functions tests | 37 | 37 | 37 |
| `npm run audit:moderate` | 1 critical, 1 moderate, then 4 incl. high | 0 vulnerabilities | 0 |
| vault check | fails (7 stale dates) | passes | passes |
| RTDB rules tests | none | none (blocked, no Java) | none |

A single non-repeating failure in `runtime_startup_test.dart` appeared in one run after the merge and did not reproduce in three later runs.

## Remaining backlog

See `audit/03-plan.md` section Backlog. Highest value next: rules test harness and `signingPublicKey` rule (needs Java), wiring per-pair signaling encryption (SEC-002), database and auth ports for the Firebase adapter (TEST-001), foreground service for calls, workflow consolidation (CI-002), and the long-function refactors in `02-refactor-targets.md`.
