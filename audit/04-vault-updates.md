# Vault Update Spec

Applied in T6.1 on `audit/rain-hardening` after the outcomes in `audit/STATE.md` are known. `<apply-date>` is replaced by the date T6.1 runs. Where a card ended Blocked, the matching risk keeps status `Open` and the progress note says so. The vault checker (`scripts/check_obsidian_vault.ps1`) must pass after applying: every `[[link]]` below points to an existing note or to a note created in this spec.

## 1. Refresh "Last updated" dates

Change only the `Last updated:` line to `Last updated: <apply-date>` in every file the validator reports as stale (7 registers at Phase 0: `12-Risks/Risk Register.md`, `14-Blockers/BLOCKERS.md`, `11-Technical Debt/Technical Debt Register.md`, `18-Lessons Learned/Recommended Next Actions.md`, `18-Lessons Learned/Project Metrics.md`, `17-Audit/Audit Resolution Tracker.md`, `20-Knowledge Graph/Repository Map.md`) plus every file edited below, plus `AI-Memory/Project Memory.md` (currently 2026-06-09).

## 2. `obsidian-vault/12-Risks/Risk Register.md`

**Section "Active Risk Register" (append after the `R-022` row, same column order: ID, Category, Risk, Impact, Probability, Severity, Mitigation, Detection Strategy, Owner, Related Links, Status):**

```
| R-024 | Security | Signaling "encryption" uses one shared compile-time key; per-pair v=2 exists but is not wired (`pairCipherResolver`/`localUsername` never passed). | SDP and ICE (IP addresses, DTLS fingerprints) are decryptable by anyone holding the app and read access; the E2E claim is not true of the shipped path. | High | High | Keep rules as the real access control; wire a resolver after the rules allow `signingPublicKey` (T4.03) and the key repair (T4.17); keep v=1 decode for one release. | Unit test that the app passes a resolver; emulator test that two users exchange v=2 envelopes. | Security/Engineering | [[Security Roadmap]], [[ADR-013]], SEC-002 in `audit/01-findings.md`, TD-027 | Open |
| R-025 | Technical | New registrations publish `users/<name>/signingPublicKey`, a child the repo rules reject (`$other` validate false). | If deployed rules equal repo rules, sign-up fails after the Auth user is created and the username stays taken. | Medium | High | T4.02 makes the publish non-fatal, T4.03 adds the rule, T4.01 adds rules tests; owner confirms deployed rules. | Rules unit test for the field; emulator run of the real register flow. | Engineering | BLK-011, SEC-001, TASK-015 | Mitigating |
| R-026 | Operational | On Spark nothing reclaims `voiceCalls`, `voiceCallInboxes` and locks of connected or abandoned calls after an app kill. | RTDB storage grows against the Spark quota; stale rooms confuse cleanup. | Medium | Medium | T4.04 lets the client reclaim expired connected rooms; `onDisconnect` for call rooms and a liveness heartbeat stay in the backlog. | Emulator test of kill-mid-call; RTDB size dashboard. | Engineering | [[Rules Strategy]], SIG-003, SIG-004, R-017 | Open |
| R-027 | Technical | Backgrounding marks the user offline mid-call and Android has no call foreground service. | Audio calls can lose the microphone or look offline to the peer when the user switches apps. | High | High | T4.05 keeps presence online during calls; foreground service needs device work (owner action). | Device test: Home for 60 s during an audio call. | Engineering | APP-001, [[Presence Management]] | Open |
| R-028 | Operational | CI gates fail without code changes: 45-day vault freshness, npm advisories, wrong PR branch filter, three overlapping CI workflows. | Red CI trains the team to ignore it; PRs to `dev` get no PR-scoped checks. | High | Medium | T3.2, T3.3, T3.4 now; consolidate workflows (backlog CI-002). | Weekly scheduled CI; required-check list review. | Engineering | [[Release Gates]], CI-001..CI-007, BLK-012 | Mitigating |
| R-029 | Security | `apps/rain/tool/dart_defines.local.json` is in git history (commits 0d8147c, 6ff832b) with ICE/TURN, Supabase and update URL settings. | Anyone with repo read access can recover those values. | Medium | High | Owner rotates TURN credentials and the Supabase anon key if still live; history is not rewritten. | Secret scan of history before each release. | Owner | GIT-003, BLK-013 | Open |
| R-030 | Technical | `firebase_adapter.dart` (3,046 lines) has 0 unit-test coverage and an uncommitted edit once broke the build and the registration rollback. | Regressions in auth, locks and cleanup are caught only by CI emulator tests. | Medium | High | T3.1 restores HEAD; T4.06 adds database/auth ports and unit tests. | Coverage report per file; analyze on every push. | Engineering | GIT-001, TEST-001, [[Emulator Coverage]] | Mitigating |
| R-031 | Operational | `main` and `dev` diverged by 25 and 17 commits with 51 files changed on both sides, including call, crypto and database code. | A naive merge silently drops security or call fixes. | High | High | Reconcile on `integration/main-dev` with the audit conflict policy (T5.1); owner decides the merge. | Diff of the 51 files after merge; full test run. | Engineering/Owner | GIT-002 | Mitigating |
| R-032 | Security | `userSearch` is listable by any signed-in account, sign-up is open and App Check is not enabled. | Username/display-name enumeration and scripted use of Spark quota. | Medium | Medium | T4.19 constrains queries in the rules; owner enables App Check and sign-up throttling. | Rules test for bounded queries; Auth console quota alerts. | Security/Owner | SEC-006, R-014, R-016 | Open |
```

**Section "Risk Summary" (the metrics table near line 34):** recompute from the table after insertion: `Total active risks` becomes 31; `Critical risks`, `High risks`, `Medium risks` recomputed from the Severity column; `Public-launch blockers` +3 (BLK-011, BLK-012, BLK-013).

**Section "Risk To Blocker Map" (table near line 58):** append rows:

```
| R-025 Registration publishes a field the rules reject | BLK-011 | T4.02, T4.03 | TD-025 |
| R-028 CI gates fail without code changes | BLK-012 | T3.2, T3.3, T3.4 | TD-028 |
| R-029 Secrets in git history | BLK-013 | owner rotation | TD-029 |
```

**Existing rows to annotate:** append to the end of the Mitigation cell of `R-017` (Spark constraints): ` 2026-10-10 audit: Spark has no scheduled cleanup, so connected/abandoned call rooms are not reclaimed (see R-026).` and to `SAR-005` row (plaintext local storage): ` 2026-10-10 audit: `PRAGMA key` is a no-op on stock SQLite and the generated DB key is unused; see [[ADR-013]].`

## 3. `obsidian-vault/14-Blockers/BLOCKERS.md`

**Section "Active Blockers" (append after BLK-010, before "Blocker Review Cadence"):**

```
### BLK-011: Registration Publishes A Field The Repo Rules Reject

- Status: Open
- Severity: High
- Owner: Security/Engineering
- Type: Security/Reliability
- Related Risks: R-025, R-024
- Related Roadmap Tasks: TASK-015, TASK-001
- Related Debt: TD-025
- Related Architecture: [[Rules Strategy]], [[Authentication]]
- Impact: If deployed rules equal repo rules, a new sign-up creates the Auth user and then fails on `users/<name>/signingPublicKey`; the username stays taken.
- Workaround Strategy: T4.02 makes the key publish non-fatal; the owner confirms the deployed rules.
- Parallel Progress Path: Rules test harness (T4.01) and the rest of Phase 4 proceed independently.
- Resolution Plan:
  - Make the publish best-effort (T4.02).
  - Add the immutable `signingPublicKey` rule and tests (T4.03).
  - Re-publish the key on login when missing (T4.17).
- Exit Criteria: Rules test proves the owner can write the key once and nobody else can; the real register flow passes against the emulator.
- Detection Strategy: `RULES_TEST`, emulator register flow.

### BLK-012: CI Gates Fail Without Code Changes

- Status: Mitigating
- Severity: High
- Owner: Engineering
- Type: Operational
- Related Risks: R-028
- Related Roadmap Tasks: Release gate work
- Related Debt: TD-028
- Related Architecture: [[Release Gates]]
- Impact: Vault freshness (45 days), npm advisories and the `develop` branch filter turn CI red or skip PR checks with no source change.
- Workaround Strategy: Refresh dates (T3.2), `npm audit fix` (T3.4), fix the filter (T3.3).
- Parallel Progress Path: Code fixes continue locally.
- Resolution Plan:
  - Make the vault staleness check git-date based or non-blocking.
  - Add Dependabot for npm and Actions.
  - Consolidate to one CI and one release workflow.
- Exit Criteria: A week of CI runs with no red run caused only by elapsed time or new advisories.
- Detection Strategy: Scheduled weekly CI run.

### BLK-013: Secrets In Git History Need Owner Rotation

- Status: Open
- Severity: High
- Owner: Owner
- Type: Security
- Related Risks: R-029
- Related Roadmap Tasks: none
- Related Debt: TD-029
- Related Architecture: [[Security Roadmap]]
- Impact: `dart_defines.local.json` values (TURN credentials, Supabase anon key) are recoverable from commits 0d8147c and 6ff832b.
- Workaround Strategy: Treat the values as exposed; do not rewrite history.
- Parallel Progress Path: All engineering work continues.
- Resolution Plan:
  - Rotate or revoke the credentials if still live.
  - Run a secret scan over history before each release.
- Exit Criteria: Owner confirms rotation or that the values are already dead.
- Detection Strategy: Secret scan in CI.
```

## 4. `obsidian-vault/11-Technical Debt/Technical Debt Register.md`

**Section "Debt Statistics":** `Total debt items` 22 -> 28, `P1 items` +4, `P2 items` +2 (recount from the entries below).

**Append new entries under "Architecture Debt" and "DevOps Debt" in the existing `### TD-0xx: Title` format:**

```
### TD-025: Firebase Adapter Is One Untested 3,000-Line Class

- Category: Architecture
- Status: Open
- Priority: P1
- Owner: Engineering
- Title: `FirebaseSignalingAdapter` combines auth, presence, voice calls, locks, cleanup, legacy rooms, social graph and callables.
- Description: 3,046 lines at HEAD, 0 of 1,277 lines covered by unit tests, no fake for `FirebaseAuth`/`FirebaseDatabase`.
- Cause: Adapter grew with each feature and was only tested through emulator suites run in CI.
- Risk: Regressions such as the registration rollback ordering are invisible until CI emulator runs.
- Cost to Fix: L, about 5 days for ports plus tests; XL for the full split.
- Cost to Ignore: Every backend change stays high risk.
- Files Affected: `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- Related Systems: [[Firebase Architecture]], [[Emulator Coverage]]
- Roadmap Tasks: T4.06 in `audit/03-plan.md`
- Resolution Strategy: Introduce database and auth ports, then split by responsibility (`audit/02-refactor-targets.md` target 2).

### TD-026: Call Runtime Is An Extension On The Controller

- Category: Architecture
- Status: Open
- Priority: P1
- Owner: Engineering
- Title: `VoiceCallRuntime` is an extension of `RainRuntimeController` with about 120 methods and 150-340-line functions.
- Description: Voice, file, friend and connection-request logic are extensions sharing one 2,423-line controller.
- Cause: Incremental extraction into coordinators left orchestration in the extension.
- Risk: Races and swallowed errors hide in long functions (SIG-001..003, APP-002, APP-003).
- Cost to Fix: XL
- Cost to Ignore: Call bugs keep costing multi-file regressions.
- Files Affected: `apps/rain/lib/application/runtime/voice_call_runtime.dart`, `rain_runtime_controller.dart`, `voice_call/*`
- Related Systems: [[VoiceCallRuntime Refactor]]
- Roadmap Tasks: `audit/02-refactor-targets.md` targets 1 and 3
- Resolution Strategy: Characterization tests first, then extract frame IO, end, invite and media factory coordinators.

### TD-027: Local Database Key Is Generated But Never Used

- Category: Security
- Status: Open
- Priority: P1
- Owner: Security/Engineering
- Title: `openEncryptedRainDatabase` executes `PRAGMA key` on a stock SQLite build, which ignores it.
- Description: The DB stays plaintext, a 32-byte key sits unused in the keystore, and `sqlite3_flutter_libs` is end-of-life.
- Cause: SQLCipher open path and migration were deferred (TASK-002).
- Risk: Misleading wiring; latent data loss if a SQLCipher build is introduced without a migration.
- Cost to Fix: L
- Cost to Ignore: Plaintext chat history on disk (accepted in [[ADR-010]], refined in [[ADR-013]]).
- Files Affected: `packages/rain_core/lib/database/rain_database.dart`, `database_key_service.dart`, `apps/rain/lib/application/bootstrap/app_bootstrap.dart`
- Related Systems: [[Security Roadmap]], [[Privacy Review]]
- Roadmap Tasks: TASK-002, T4.07
- Resolution Strategy: Report state honestly now (T4.07); implement option (a) of ADR-013 after the owner decision.

### TD-028: Eight Overlapping GitHub Workflows

- Category: DevOps
- Status: Open
- Priority: P2
- Owner: Engineering
- Title: Three CI workflows and four release workflows with different gates and no SHA pinning.
- Description: Same checks defined three times; `ci.yml` had a `develop` branch filter; vault and audit gates fail on time.
- Cause: Gates were added per incident.
- Risk: Green in one workflow says nothing about another; supply-chain exposure through tag-pinned actions.
- Cost to Fix: L
- Cost to Ignore: Wasted runner minutes and unclear release safety.
- Files Affected: `.github/workflows/*.yml`
- Related Systems: [[Release Gates]]
- Roadmap Tasks: T3.3, T4.23, `audit/02-refactor-targets.md` target 7
- Resolution Strategy: One CI and one release workflow, pinned actions, Dependabot.

### TD-029: Beta And End-Of-Life Dependencies, Historical Secrets

- Category: DevOps
- Status: Open
- Priority: P2
- Owner: Engineering/Owner
- Title: `file_picker 12.0.0-beta.3` in production, `sqlite3_flutter_libs 0.6.0+eol`, `dart_defines.local.json` in history.
- Description: Pre-release plugin handles file selection; EOL native libs; historical config file recoverable from git.
- Cause: Fast iteration without dependency policy.
- Risk: Unpatched bugs; credential exposure.
- Cost to Fix: M
- Cost to Ignore: Security patches missed.
- Files Affected: `apps/rain/pubspec.yaml`, `pubspec.lock`, `apps/rain/tool/dart_defines.local.json` (history)
- Related Systems: [[Security Roadmap]]
- Roadmap Tasks: ARCH-006, GIT-003 in `audit/01-findings.md`
- Resolution Strategy: Move to stable `file_picker` after device smoke; owner rotates exposed values.

### TD-030: Ghost Call Rooms On Spark

- Category: Operational
- Status: Open
- Priority: P1
- Owner: Engineering
- Title: Connected or abandoned `voiceCalls` rooms are never deleted without Blaze scheduled functions.
- Description: Client cleanup runs at start/resume for the user's own lock and skips `connected` rooms; no `onDisconnect` for call nodes.
- Cause: Cleanup was designed around Cloud Functions.
- Risk: RTDB growth against Spark quotas.
- Cost to Fix: M
- Cost to Ignore: Quota exhaustion over time.
- Files Affected: `packages/protocol_brain/lib/adapters/firebase_adapter.dart`, `packages/protocol_brain/lib/src/voice_call_cleanup_janitor.dart`, `backend/firebase/functions/index.js`
- Related Systems: [[Rules Strategy]], [[Firebase Architecture]]
- Roadmap Tasks: T4.04
- Resolution Strategy: Pure cleanup planner and client reclaim (T4.04); `onDisconnect` and liveness heartbeat later.
```

## 5. `obsidian-vault/11-Decisions/ADR-012.md` (new file)

```
# ADR-012: Spark-Only Backend - Cloud Functions Are Optional

Date: <apply-date>

## Context

Rain runs on the Firebase Spark plan ([[ADR-002]]). `backend/firebase/functions/index.js` exports three scheduled cleanup jobs (`cleanupPresence`, `cleanupRooms`, `cleanupVoiceCalls`), `cleanupConnectionRequests` and nine callables. Scheduled and deployed functions need the Blaze plan. The app default is `rtdbOnly` (`packages/protocol_brain/lib/src/connection_request_backend_mode.dart`).

Related: [[ADR-001]], [[ADR-002]], [[Rules Strategy]], [[Firebase Architecture]], [[Risk Register]].

## Problem

The repository ships code that assumes server-side cleanup and quota authority while the product constraint forbids paid features. Docs (`backend/firebase/README.md`) and tests must say which path is authoritative.

## Options

1. Treat Cloud Functions as required and move to Blaze.
2. Treat Cloud Functions as optional extras and make every Spark path self-sufficient on the client and in RTDB rules.
3. Remove the functions code.

## Decision

Choose Option 2. The `rtdbOnly` path must be correct without any function: presence freshness is computed client-side, call rooms are reclaimed by client cleanup (T4.04) and rules, quotas are best-effort counters under rules. Cloud Functions remain in the repository, are not deployed in free-tier releases, and no app code may depend on them in `rtdbOnly` mode. Any change to functions must keep their tests (`npm test`) green and `npm audit` clean.

## Consequences

- Features that need server authority (scheduled cleanup, strict quotas, closed-app push) are explicitly out of scope on Spark.
- `FirebaseFunctions` is instantiated lazily (T4.22) and `cloud_functions` stays a dependency only for the optional backend mode.
- README and Risk Register describe the Spark limits (R-026).
- Revisit if the owner moves to Blaze.
```

## 6. `obsidian-vault/11-Decisions/ADR-013.md` (new file)

```
# ADR-013: Local Database Encryption Approach

Date: <apply-date>

## Context

[[ADR-010]] accepted plaintext Drift/SQLite storage for the current phase. Since then the repository added a keystore-backed DB key (`DatabaseKeyService`) and `openEncryptedRainDatabase`, which executes `PRAGMA key` but is a no-op on stock SQLite. `sqlite3` is 3.3.1, which supports build hooks; `sqlite3_flutter_libs` is `0.6.0+eol`. Context7 (`/simolus3/sqlite3.dart`, `UPGRADING_TO_V3.md`) documents `hooks: user_defines: sqlite3: source: sqlcipher` (or `sqlite3mc`).

Related: [[ADR-010]], [[Security Roadmap]], [[Privacy Review]], [[Technical Debt Register]], [[Risk Register]].

## Problem

The code implies encrypted storage that does not exist. A decision is needed between keeping plaintext, application-level encryption and SQLCipher.

## Options

1. (c) Keep plaintext, document it, rely on OS disk encryption.
2. (b) Encrypt message bodies with AES-GCM using the existing DB key; metadata stays plaintext.
3. (a) SQLCipher through the `sqlite3` build hook with a verified plaintext-to-cipher migration.

## Decision

Status: Proposed, awaiting the owner (audit owner action 4). Recommendation: option (a) as the target with a version marker and an interrupted-migration recovery test; option (b) only if (a) cannot be built on Windows; until decided, [[ADR-010]] stays in force and the app reports `db_encryption_inactive` (T4.07).

## Consequences

- No claim of encrypted local history until (a) or (b) ships and is validated.
- Key loss behavior must be defined: never regenerate a key while a database file exists.
- Native builds on Android and Windows and a migration test are required before release.
```

## 7. `obsidian-vault/18-Lessons Learned/Recommended Next Actions.md`

**Section "Current Recommendation Summary" (append a paragraph after the last "progress" paragraph):**

```
Audit hardening 2026-10-10 (branch `audit/rain-hardening`, files `audit/01-findings.md`..`audit/05-report.md`): 65 findings (2 P0, 10 P1). Next in order: (1) owner confirms deployed RTDB rules and rotates the secrets in git history; (2) merge `audit/rain-hardening` and `integration/main-dev` after device checks on Android and Windows; (3) rules test harness and `signingPublicKey` rule (T4.01, T4.03); (4) database/auth ports for the Firebase adapter (T4.06); (5) decide [[ADR-013]]; (6) consolidate CI workflows. Source of truth for status is `audit/STATE.md`.
```

## 8. `obsidian-vault/AI-Memory/Project Memory.md`

**Section "Constraints" (append bullets):**

```
- Spark-only: Cloud Functions in `backend/firebase/functions` are optional and not deployed in free-tier builds ([[ADR-012]]). Scheduled cleanups (`cleanupPresence`, `cleanupRooms`, `cleanupVoiceCalls`, `cleanupConnectionRequests`) need Blaze.
- Canonical working copy for the audit program is `D:\Rain` (decision D1, 2026-10-09); AGENTS.md still names the OneDrive path until the owner confirms.
```

**Section "Known Pitfalls" (append bullets):**

```
- Signaling today is v=1: one shared compile-time `RAIN_SIGNALING_ENCRYPTION_KEY` for all users. The per-pair v=2 cipher exists but the app passes no `pairCipherResolver`/`localUsername`; do not describe signaling as end-to-end encrypted ([[ADR-013]], R-024).
- `users/$username` rules have `$other: .validate false`; any new child (for example `signingPublicKey`) needs a rule and a rules test in the same change.
- `PRAGMA key` is ignored by stock SQLite: the local database is plaintext although a DB key exists in the keystore ([[ADR-010]], [[ADR-013]]).
- `voiceCalls/<id>/expiresAt` is immutable under the rules; a liveness heartbeat must use `updatedAt`.
- `localMutations.run` is a FIFO future queue, not a DB transaction; `serializedTransaction` must never be nested (it deadlocks the write queue).
- The vault gate fails when any register is older than 45 days; refresh `Last updated` or run the validator before pushing.
- Android has no call foreground service and backgrounding marks presence offline; closed-app and background-call reliability remain out of scope until that exists.
- `dart_defines.local.json` values are in git history (commits 0d8147c, 6ff832b); treat them as exposed.
```

**Section "Technical Debt" and "Risks" (append one line each):**

```
- Audit 2026-10-10 added TD-025..TD-030 (see [[Technical Debt Register]]).
- Audit 2026-10-10 added R-024..R-032 (see [[Risk Register]]).
```

## 9. Other notes touched

- `obsidian-vault/17-Audit/Audit Resolution Tracker.md`: add a section "2026-10 Hardening Audit" listing each finding id fixed (from `audit/STATE.md` Done) and each left open; refresh date.
- `obsidian-vault/18-Lessons Learned/Project Metrics.md`: update test counts and coverage (peer_core 73.1 %, protocol_brain 54.6 %, rain_core 43.7 %, apps/rain 68.8 % at Phase 0; replace by the Phase 4 results) and refresh date.
- `obsidian-vault/20-Knowledge Graph/Repository Map.md`: add `audit/` and note the planned `packages/rain_models` only if the backlog item ARCH-001 is executed.
- `CONTINUITY.md`: dated entry for the audit with what changed, validation results, blocked cards and next actions.
- `AGENTS.md`: after owner confirmation of DOC-006 only.
