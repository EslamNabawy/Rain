# 2026-06-05 Senior Audit Remediation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for implementation tasks or `superpowers:executing-plans` for inline execution. Work task-by-task. Do not batch risky call, Firebase, database, and release-gate changes into one commit.

Last updated: 2026-06-05

## Goal

Turn the 2026-06-05 senior audit into a phased remediation program that fixes Rain's highest-risk correctness, reliability, security, maintainability, scalability, and release-evidence gaps.

## Architecture

Rain is a Flutter monorepo. The highest-risk code paths are not isolated syntax problems; they are overloaded runtime ownership, distributed Firebase state, stale presence decisions, weak release proof, and local persistence assumptions. Fix proof first, then refactor. No public-release claim is valid until tests, emulator evidence, vault evidence, and release-gate evidence agree.

## Tech Stack

Flutter, Dart, Riverpod, Drift, Firebase Realtime Database, Firebase Auth, Firebase Remote Config, WebRTC, Melos, PowerShell, GitHub Actions, Obsidian Markdown.

## Related Notes

[[Master Roadmap]], [[Audit Resolution Tracker]], [[Original Audit]], [[BLOCKERS]], [[Blocker Resolution Plan]], [[Technical Debt Register]], [[Risk Register]], [[Critical Path]], [[Release Gates]], [[Emulator Test Matrix]], [[Diagnostics Sanitization]], [[VoiceCallRuntime Refactor]], [[Presence Management]], [[Lease Management]], [[Database Architecture]], [[File Transfer]].

## Context7 Documentation Check

Context7 MCP was used on 2026-06-05 to verify current guidance for the libraries most relevant to this plan.

| Area | Context7 Library | Guidance Applied |
| --- | --- | --- |
| Riverpod provider boundaries | `/rrousselgit/riverpod` | Use `select` to reduce rebuilds only when selected values are immutable. Do not replace `ref.watch` with `ref.read` just to avoid rebuilds; use `ref.read` for event handlers and imperative interactions. |
| Drift schema/index work | `/websites/drift_simonbinder_eu` | Add indexes in schema, update schema version/migrations deliberately, and generate migration tests with Drift tooling after schema changes. |
| Drift local storage security | `/websites/drift_simonbinder_eu` | Drift does not make local SQLite storage encrypted by default; encrypted storage requires an explicit database-opening/key setup and a migration plan. |
| Firebase Realtime Database | `/llmstxt/firebase_google_llms_txt` | Use rules for authorization and validation, define `.indexOn` where query paths need it, queue `onDisconnect` operations before marking clients online, and do not rely on offline transactions surviving app restarts. |

## Blunt Assessment

The repo is green, but green is not enough. Current local validation passes. That means the project has a decent baseline. It does not mean Rain is production-safe.

Core problem: too many important decisions are made by broad runtime objects, stale booleans, prose docs, and manual release discipline. That is how bugs escape.

Fix order:

1. Prove distributed state behavior.
2. Make peer action decisions authoritative.
3. Break oversized runtime ownership only after behavior is pinned.
4. Harden diagnostics and local-data security claims.
5. Add scale fixes.
6. Make release/vault evidence machine-enforced.

## Current Baseline

Validated on `dev` during 2026-06-05 audit:

| Gate | Result |
| --- | --- |
| `dart pub get` | Passed |
| `dart run melos run analyze` | Passed |
| `dart run melos run test` | Passed |
| Firebase functions `npm run lint` | Passed |
| Firebase functions `npm test` | Passed |
| Firebase functions `npm run audit:moderate` | Passed |
| Firebase emulator integration script | Passed |
| JSON config/rules parse | Passed |
| `./scripts/check_obsidian_vault.ps1` | Passed |

Not yet proven:

- Platform builds were not run.
- Physical/emulated device media proof was not run.
- Remote Config deploy/readback proof was not run.
- Build-runner freshness was not run because audit was read-only and generated files can mutate.

## Issue Map

| ID | Severity | Weak Point | Primary Files | Risk |
| --- | --- | --- | --- | --- |
| SAR-001 | Critical | Voice call runtime is too large and stateful. | `apps/rain/lib/application/runtime/voice_call_runtime.dart` | Call setup, cleanup, diagnostics, media, and Firebase reconciliation can regress together. |
| SAR-002 | Critical | Peer connectivity snapshot is not authoritative enough. | `apps/rain/lib/application/state/runtime_providers.dart`, `apps/rain/lib/application/state/peer_connectivity_snapshot.dart` | UI can act on stale presence or miss superseded sessions. |
| SAR-003 | Critical | UI still uses weak friend online state for actions. | `apps/rain/lib/presentation/widgets/home/chat_panel.dart` | Connect/request/call decisions can route wrong under stale presence. |
| SAR-004 | Critical | Firebase voice call locks are fragile multi-path client writes. | `packages/protocol_brain/lib/adapters/firebase_adapter.dart`, `database.rules.json` | Partial writes or stale locks can create false busy, stuck calls, or invalid transitions. |
| SAR-005 | High | Local messages and queued messages are plaintext. | `packages/rain_core/lib/database/rain_database.dart`, `packages/rain_core/lib/messages/message_store.dart`, `packages/rain_core/lib/messages/offline_queue.dart` | Security claims can be misleading if local compromise is in scope. |
| SAR-006 | High | Database query path has no pagination/index proof. | `packages/rain_core/lib/database/rain_database.dart`, `packages/rain_core/lib/messages/message_store.dart` | Large chats can become slow and memory-heavy. |
| SAR-007 | High | File transfer streaming/backpressure is inefficient. | `apps/rain/lib/application/runtime/file_transfer_runtime.dart`, `packages/peer_core/lib/src/default_peer_core.dart` | Large transfers can waste memory/IO and behave poorly under slow receivers. |
| SAR-008 | High | Diagnostics redaction is not strong enough. | `apps/rain/lib/infrastructure/services/crash_diagnostics_service.dart`, `apps/rain/lib/infrastructure/services/rain_debug_log_service.dart` | Logs/exports can leak identifiers, room paths, file names, message-like text, or stack details. |
| SAR-009 | High | Release workflows are not fully unified behind one hard gate. | `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `.github/workflows/build-artifacts.yml`, `.github/workflows/validated-release.yml` | A weaker release path can publish without the same proof as the strong path. |
| SAR-010 | High | Obsidian vault validates structure, not truth. | `scripts/check_obsidian_vault.ps1`, `obsidian-vault/**` | Blockers, risks, debt, and roadmap statuses can drift while validation still passes. |
| SAR-011 | Medium | Demo signing and stable package identity need explicit risk treatment. | `scripts/build_release.ps1`, `apps/rain/android/app/build.gradle.kts`, `.github/workflows/ci.yml` | Demo artifacts can be misunderstood as production-trust artifacts. |
| SAR-012 | Medium | Provider boundaries cause broad UI rebuild risk. | `apps/rain/lib/presentation/widgets/home/chat_panel.dart`, `apps/rain/lib/presentation/screens/home_screen.dart` | UI performance and correctness degrade as state grows. |

## Execution Rules

- No big-bang rewrite.
- No release promotion while P0 blockers remain open.
- Every phase starts with failing or gap-proving tests.
- Every phase ends with local validation and vault evidence update.
- Every completed task updates [[Audit Resolution Tracker]], [[Technical Debt Register]], [[Risk Register]], and relevant architecture notes.
- Every release-affecting change must pass `dart run melos run analyze`, `dart run melos run test`, Firebase backend validation when relevant, and `./scripts/check_obsidian_vault.ps1`.
- If a task changes generated Drift code, run the project-approved build-runner command and commit generated output in the same change.

## Phase 0: Evidence Lock And Planning Hygiene

Priority: P0

Purpose: Freeze current truth before changing behavior.

Files:

- Modify: `obsidian-vault/17-Audit/Audit Resolution Tracker.md`
- Modify: `obsidian-vault/11-Technical Debt/Technical Debt Register.md`
- Modify: `obsidian-vault/12-Risks/Risk Register.md`
- Modify: `obsidian-vault/14-Blockers/BLOCKERS.md`
- Modify or create: `obsidian-vault/09-Testing/Emulator Test Matrix.md`
- Modify or create: `obsidian-vault/18-Lessons Learned/Project Metrics.md`

Steps:

- [x] Record this audit plan as active execution source under [[Master Roadmap]].
- [x] Add SAR issue IDs to the tracker notes above.
- [x] For each SAR item, define owner, priority, dependency, evidence required, and release impact.
- [x] Add a validation evidence section for command output, commit SHA, branch, date, and result.
- [x] Run `./scripts/check_obsidian_vault.ps1`.

Acceptance:

- Every SAR item has a corresponding tracker/risk/debt/blocker entry.
- Vault validation passes.
- No task is marked done without evidence.
- Phase 0 evidence is recorded in [[Project Metrics]].

## Phase 1: Peer Presence And Action Authority

Priority: P0

Status: Complete local proof 2026-06-05; Firebase emulator/device proof remains Phase 2 and Phase 10 work.

Fixes: SAR-002, SAR-003, SAR-012, BLK-008, BLK-009.

Purpose: Stop using stale `friend.isOnline` as action truth.

Files:

- Modify: `apps/rain/lib/application/state/peer_connectivity_snapshot.dart`
- Modify: `apps/rain/lib/application/state/runtime_providers.dart`
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Modify: `apps/rain/lib/application/runtime/friend_runtime.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
- Test: `apps/rain/test/peer_connectivity_provider_test.dart`

Steps:

- [x] Added focused provider tests proving trusted local `friend.isOnline` is not enough to enable actions.
- [x] Extended connectivity snapshot inputs with backend presence session id, heartbeat age, presence state, freshness threshold, and observation time.
- [x] Populated runtime-backed `backendPresenceSessionId` and real `presenceFresh` instead of mirroring `friend.isOnline`.
- [x] Replaced chat panel action decisions from `friend.isOnline` with `PeerConnectivitySnapshot.peerOnlineForAction`.
- [x] Used Riverpod `select` for the immutable selected peer snapshot in the chat panel.
- [x] Confirmed existing `packages/protocol_brain/test/firebase_contract_test.dart` locks session-owned Firebase presence and `onDisconnect` offline cleanup registration.
- [x] Added tests for stale heartbeat, unknown/local-only presence, fresh backend presence, stale receiver routing, and the 45 second RTDB connection-request freshness window.
- [x] Updated [[Presence Management]] and [[Connection Request Notifications]].

Acceptance:

- Connect, call, and offline request UI/runtime preflight now use the same authoritative snapshot.
- Stale online records cannot enable direct connect or call in local provider/runtime proof.
- RTDB connection-request preflight now uses the same 45 second freshness threshold as the rules; quota non-consumption still needs Firebase rule/emulator proof in Phase 2.

Validation:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
./scripts/check_obsidian_vault.ps1
```

## Phase 2: Firebase Call Lock And Rule Proof

Priority: P0

Status: Complete rule/emulator proof 2026-06-05; device media-direction proof remains Phase 10.

Fixes: SAR-004, BLK-001, BLK-002, BLK-003.

Purpose: Prove call locks, rooms, inboxes, and terminal states behave correctly before refactoring runtime code.

Files:

- Reviewed: `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- Reviewed: `backend/firebase/database.rules.json`
- Reviewed: `backend/firebase/functions/connectionRequests.js`
- Test: `packages/protocol_brain/test/**`
- Test: `backend/firebase/functions/test/**`
- Test: `apps/rain/test/integration_voice_signaling_emulator_test.dart`
- Script: `scripts/ci_run_firebase_emulators.ps1`

Steps:

- [x] Added emulator tests for terminal leftover locks, missing inbox cleanup, malformed lock/inbox writes, permission denied paths, and live-lock state preservation.
- [x] Added denied rule tests for invalid `connected`, invalid caller/callee ownership, malformed status, oversized reason payloads, and cross-role signaling writes.
- [x] Added client contract tests for compensating cleanup after partial write failure and best-effort terminal cleanup.
- [x] Added Firebase rule validation tests proving malformed child writes reject the whole operation where `.validate` applies.
- [x] Added transaction contract proof: voice lock transactions use `applyLocally: false` and direct fallback re-reads before compare-delete.
- [x] Verified stale-lock repair remains deterministic and conservative through shared `VoiceLockReclaimPolicy` and emulator proof.
- [x] Verified live locks are never deleted by stale cleanup through emulator post-denial state assertions.
- [x] Recorded Firebase operation budget impact in [[Firebase Architecture]].

Acceptance:

- False busy only appears when a fresh valid lock exists in policy and emulator proof.
- Stale locks repair once with diagnostics and conservative retry behavior.
- Terminal rooms win over late local frames and stale locks no longer block reverse call setup.
- Rules reject malformed or unauthorized transitions and denied writes preserve existing state.

Validation:

```powershell
Push-Location backend/firebase/functions
npm run lint
npm test
npm run audit:moderate
Pop-Location
./scripts/ci_run_firebase_emulators.ps1
dart run melos run analyze
dart run melos run test
./scripts/check_obsidian_vault.ps1
```

## Phase 3: Voice Call Runtime Decomposition

Priority: P0

Status: In progress 2026-06-05. First safe slice complete: pure call error classification and voice/video media adapter ownership were extracted with focused and workspace validation. Room reconciliation, lock coordination, command coordination, and full media session ownership remain open Phase 3 work.

Fixes: SAR-001, SAR-004, BLK-001, BLK-002, BLK-005.

Purpose: Split `VoiceCallRuntime` without changing behavior blindly.

Files:

- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Create or modify: `apps/rain/lib/application/runtime/call_command_service.dart`
- Create or modify: `apps/rain/lib/application/runtime/call_room_reconciler.dart`
- Create or modify: `apps/rain/lib/application/runtime/call_lock_coordinator.dart`
- Create or modify: `apps/rain/lib/application/runtime/call_media_session_coordinator.dart`
- Create or modify: `apps/rain/lib/application/runtime/call_error_classifier.dart`
- Create or modify: `apps/rain/test/call_error_classifier_test.dart`
- Test: `apps/rain/test/**voice**.dart`
- Test: focused call state-machine tests.

Steps:

- [ ] Add characterization tests around start, accept, reject, hangup, terminal remote room, local media failure, permission failure, and late Firebase update.
- [x] Extract pure error classification first.
- [ ] Extract room reconciliation second.
- [ ] Extract lock coordination third.
- [ ] Extract media session ownership fourth. 2026-06-05 partial: media adapter classes and media diagnostics mapping moved to `call_media_session_coordinator.dart`; session orchestration remains in `VoiceCallRuntime`.
- [x] Keep public `RainRuntimeController` behavior stable during extraction for the first slice.
- [ ] Delete dead helper paths only after coverage proves no behavior loss.
- [x] Update [[VoiceCallRuntime Refactor]], [[Call State Machine]], and [[Current Architecture]] for the first slice.

Evidence 2026-06-05:

- `CallErrorClassifier` now owns voice call reason codes, user-facing failure messages, retry/failure taxonomy, Firebase signaling snapshot classification, busy user extraction, and local media failure classification.
- `CallVoiceMediaConnection`, `VideoVoiceMediaConnection`, `VideoCallRendererException`, and voice media diagnostics mapping moved from `voice_call_runtime.dart` into `call_media_session_coordinator.dart`.
- `VoiceCallRuntime` still orchestrates command handling, Firebase room reconciliation, lock coordination, state mutation, and cleanup. That is intentional until the remaining characterization seams are covered.

Acceptance:

- No single call runtime file owns command handling, media, Firebase reconciliation, diagnostics, and cleanup at once.
- State transitions are explicit and tested.
- Runtime returns to idle after every terminal path.

Validation:

```powershell
dart run melos run analyze
dart run melos run test
./scripts/check_obsidian_vault.ps1
```

## Phase 4: Diagnostics Privacy And Failure Taxonomy

Priority: P0/P1

Status: Mitigated locally 2026-06-05; keep adding sanitizer regressions for every new private diagnostic field.

Fixes: SAR-008, BLK-005.

Purpose: Make diagnostics useful without leaking private data.

Files:

- Modify: `apps/rain/lib/infrastructure/services/crash_diagnostics_service.dart`
- Modify: `apps/rain/lib/infrastructure/services/rain_debug_log_service.dart`
- Modify: call diagnostics models under `apps/rain/lib/application/**`
- Test: diagnostics sanitizer tests under `apps/rain/test/**`
- Update: `obsidian-vault/08-Security/Diagnostics Sanitization.md`

Steps:

- [x] Added failing tests with nested maps/lists containing tokens, passwords, room ids, peer ids, usernames, Firebase paths, SDP, ICE candidates, file names, and message-like strings.
- [x] Replaced key-only sanitization with recursive schema/value sanitization through `DiagnosticsSanitizer`.
- [x] Required crash records, app/debug events, coalesced event records, write-failure debug output, and final diagnostic export payloads to pass through the sanitizer.
- [x] Added call failure taxonomy for Firebase permission, media permission, ICE failure, TURN failure, room terminal, stale lock, and malformed remote data.
- [x] Updated privacy review with explicit local-only/export behavior.

Evidence 2026-06-05:

- `apps/rain/lib/infrastructure/services/diagnostics_sanitizer.dart` centralizes diagnostic redaction and pseudonymization.
- `CrashDiagnosticsService` sanitizes errors, stack traces, event contexts, event coalescing records, file-write debug messages, and final exports.
- `RainDebugLogService` uses the same sanitizer instead of a separate partial redactor.
- `CallErrorClassifier.failureTaxonomy` now separates `firebase_permission_denied`, `media_permission_denied`, `ice_failed`, `turn_unavailable`, `room_terminal`, `stale_lock_repaired`, `malformed_remote_data`, and existing presence/busy/rules/timeout buckets.

Acceptance:

- No raw sensitive value appears in diagnostic exports.
- Failure classification is specific enough for support without exposing payloads.

Validation:

```powershell
dart run melos run analyze
dart run melos run test
./scripts/check_obsidian_vault.ps1
```

Validation passed locally on 2026-06-05 for the Phase 4 code/docs sync: `dart run melos run analyze`, full `dart run melos run test`, and `.\scripts\check_obsidian_vault.ps1`.

Focused Phase 4 proof passed locally:

```powershell
flutter test test\crash_diagnostics_service_test.dart test\rain_debug_log_service_test.dart test\call_error_classifier_test.dart --reporter expanded
```

## Phase 5: Local Data Security Decision

Priority: P1

Status: Accepted/documented 2026-06-05 using Option A.

Fixes: SAR-005.

Purpose: Stop pretending local storage risk is solved if it is not solved.

Files:

- Modify: `packages/rain_core/lib/database/rain_database.dart`
- Modify: `packages/rain_core/lib/messages/message_store.dart`
- Modify: `packages/rain_core/lib/messages/offline_queue.dart`
- Modify: `obsidian-vault/08-Security/Privacy Review.md`
- Modify: `obsidian-vault/08-Security/Security Roadmap.md`
- Modify: `obsidian-vault/12-Risks/Risk Register.md`

Decision:

- Option A: Accept plaintext local storage and document threat model. Selected 2026-06-05.
- Option B: Add local database encryption with key management and migration proof.

Decision note: [[ADR-010]].

Steps:

- [x] Decide whether local device compromise is in product threat model for the current implementation.
- [x] If Option A, update privacy/security docs and user-facing claims.
- [x] If Option B, create a separate implementation plan before code changes. Not selected.
- [x] If Option B, add migration tests from plaintext schema to encrypted schema. Not selected.

Evidence 2026-06-05:

- `messages.content`, `queued_messages.content`, `file_transfers.fileName`, and `file_transfers.localPath` are Drift text columns in `packages/rain_core/lib/database/rain_database.dart`.
- `MessageStore`, `OfflineQueue`, and `FileTransferStore` write those fields directly into the local database.
- `_openRainDatabase()` uses Drift's normal native database setup and does not configure an encryption key.
- Context7 Drift documentation confirms encrypted databases require explicit setup; encryption is not automatic.
- Current security position: Rain protects Firebase/Auth/signaling access and keeps diagnostics local/sanitized, but it does not claim local message database encryption.

Acceptance:

- Product/security docs match implementation.
- No security claim implies local message encryption unless it exists.
- Future Option B work must be planned separately with key management, encrypted database opening, plaintext-to-encrypted migration, rollback behavior, and migration tests.

Validation:

```powershell
dart run melos run analyze
dart run melos run test
./scripts/check_obsidian_vault.ps1
```

Phase 5 completed as a documentation/security decision only. Workspace analyze/test were not rerun because no application code changed in this phase; vault validation is the required local gate for this update.

## Phase 6: Database Scalability

Priority: P1

Status: Mitigated locally 2026-06-05; device/frame-budget proof remains open.

Fixes: SAR-006.

Purpose: Make message storage work beyond toy conversation sizes.

Files:

- Modify: `packages/rain_core/lib/database/rain_database.dart`
- Modify generated Drift output only through approved generator.
- Modify: `packages/rain_core/lib/messages/message_store.dart`
- Modify: chat providers/widgets under `apps/rain/lib/application/state/**` and `apps/rain/lib/presentation/widgets/home/**`
- Test: `packages/rain_core/test/**`
- Test: `apps/rain/test/**chat**.dart`
- Update: `obsidian-vault/06-Database/Index Strategy.md`
- Update: `obsidian-vault/06-Database/Pagination Strategy.md`

Steps:

- [x] Inventory all high-frequency queries.
- [x] Add Drift indexes for conversation reads, queue drain/recovery, file transfer lookup, and friend lookup.
- [x] Add migration tests from current schema.
- [x] Regenerate Drift output after schema/index changes.
- [x] Replace app chat startup full-conversation watch with bounded initial live tail.
- [x] Add tests for page ordering, older-page loading, duplicate prevention, and migration.

Evidence 2026-06-05:

- Drift schema version is now 6.
- `packages/rain_core/lib/database/rain_database.dart` declares `messages_peer_sent_seq_id_idx`, `friends_display_name_idx`, `queued_messages_to_status_seq_sent_idx`, `queued_messages_status_to_idx`, `file_transfers_peer_created_idx`, `file_transfers_message_id_idx`, and `file_transfers_state_peer_idx`.
- `packages/rain_core/lib/messages/message_store.dart` adds `MessagePageCursor`, `watchConversationTail`, and `loadConversationPage`.
- `apps/rain/lib/application/state/messaging_providers.dart` starts message state from the default 50-message live tail and merges older pages on demand.
- `apps/rain/lib/presentation/widgets/home/chat_panel.dart` loads older local messages through pull-to-refresh before existing network refresh work.
- Remaining proof: large-history device/frame-budget validation.

Acceptance:

- Large conversation startup does not require loading full history.
- Query paths have explicit index coverage.
- Migration is tested.

Validation:

```powershell
dart run melos run analyze
dart run melos run test
./scripts/check_obsidian_vault.ps1
```

## Phase 7: File Transfer Streaming And Backpressure

Priority: P1

Status: Mitigated locally 2026-06-05.

Fixes: SAR-007.

Purpose: Make large transfers bounded and failure-safe.

Files:

- Modify: `apps/rain/lib/application/runtime/file_transfer_runtime.dart`
- Modify: `packages/peer_core/lib/src/default_peer_core.dart` only if peer-core backpressure contract must change.
- Modify: `packages/rain_core/lib/file_transfer/file_transfer_protocol.dart`
- Test: `apps/rain/test/**file**.dart`
- Test: `packages/peer_core/test/**`
- Update: `obsidian-vault/07-File Transfers/Streaming Architecture.md`
- Update: `obsidian-vault/07-File Transfers/Backpressure Strategy.md`

Steps:

- [x] Add tests for large receive, cancel mid-transfer, hash mismatch, slow receiver, disk write failure, and temp cleanup.
- [x] Keep receive sink open per active transfer instead of open/close per chunk.
- [x] Avoid unnecessary send-buffer copies.
- [x] Define high/low watermarks and timeout behavior in one contract.
- [x] Ensure failed transfer removes temp files and closes sinks.

Implementation Evidence 2026-06-05:

- `file_transfer_runtime.dart` now owns a per-transfer receive-sink registry, closes sinks on terminal paths, and deletes temp files on cancel/failure.
- The outgoing send loop carries one partial chunk and uses source-buffer views for full chunks where possible.
- `file_transfer_protocol.dart` centralizes chunk size, high/low watermarks, poll interval, and timeout constants.
- Focused tests passed for large receive, cancellation cleanup, hash mismatch cleanup, disk write failure, scripted send backpressure drain, and congestion timeout failure.

Acceptance:

- Memory and IO stay bounded during large transfers.
- Slow receiver causes backpressure, not uncontrolled buffering.
- Cancel/failure paths clean resources.

Validation:

```powershell
dart run melos run analyze
dart run melos run test
./scripts/check_obsidian_vault.ps1
```

## Phase 8: Release Gate Unification

Priority: P0/P1

Status: Mitigated locally 2026-06-05; fresh cloud workflow evidence remains required before claiming a specific release artifact is proven.

Fixes: SAR-009, SAR-011, BLK-006.

Purpose: Make every release artifact traceable to the same hard evidence.

Files:

- Modify: `.github/workflows/release.yml`
- Modify: `.github/workflows/build-artifacts.yml`
- Modify: `.github/workflows/validated-release.yml`
- Modify: `.github/workflows/ci.yml`
- Modify: `scripts/build_release.ps1`
- Update: `obsidian-vault/10-DevOps/Release Gates.md`
- Update: `obsidian-vault/00-Dashboard/Launch Readiness.md`

Steps:

- [x] Map every workflow to purpose: PR gate, fast artifact, hard release, docs/vault gate.
- [x] Ensure public/stable release cannot bypass analyze, tests, Firebase validation, emulator validation, and vault validation.
- [x] Mark demo signing as test-artifact only unless a production signing policy exists.
- [x] Add artifact metadata: branch, commit, version, channel, validation workflow run.
- [x] Add Remote Config deploy/readback proof requirement for production update prompts.

Implementation Evidence 2026-06-05:

- `release.yml` no longer publishes on direct tag push. It is manual-only, validates the selected target, requires Remote Config deploy/readback evidence, and blocks Windows/Android build plus GitHub release creation behind `validation-gate`.
- `build-artifacts.yml`, `fast-release.yml`, `validated-release.yml`, and `release.yml` all emit `rain-release-metadata.json` through `scripts/write_release_metadata.ps1`.
- `build-artifacts.yml` release notes label direct-download `rain-test-*` pages as `TEST ARTIFACT ONLY`.
- `fast-release.yml` and `validated-release.yml` require `remote_config_evidence_url` for production publishing.
- `packages/protocol_brain/test/release_contract_test.dart` locks the release gate dependency graph, metadata emission, test-artifact label, and production Remote Config evidence requirement.

Acceptance:

- There is no known weak release path in local workflow contract proof.
- Test artifacts are clearly labeled as test artifacts.
- Stable release artifacts point to validation evidence through `rain-release-metadata.json`.
- Remaining proof: run the changed workflows in GitHub Actions before promoting any specific artifact.

Validation:

```powershell
dart run melos run analyze
dart run melos run test
./scripts/check_obsidian_vault.ps1
```

CI validation must also pass after workflow edits.

## Phase 9: Obsidian Vault Semantic Enforcement

Priority: P1

Fixes: SAR-010.

Purpose: Make the vault tell truth, not just hold notes.

Files:

- Modify: `scripts/check_obsidian_vault.ps1`
- Modify or create: `obsidian-vault/18-Lessons Learned/Project Metrics.md`
- Modify or create: `obsidian-vault/20-Knowledge Graph/Repository Map.md`
- Modify: `obsidian-vault/17-Audit/Audit Resolution Tracker.md`
- Modify: `obsidian-vault/11-Technical Debt/Technical Debt Register.md`
- Modify: `obsidian-vault/12-Risks/Risk Register.md`
- Modify: `obsidian-vault/14-Blockers/BLOCKERS.md`

Steps:

- [x] Define required parseable table/section fields for blockers, risks, debt, tasks, and evidence.
- [x] Add script checks for missing owner, missing priority, missing evidence, stale review date, and unsupported status values where the register has a fixed status schema.
- [x] Add evidence ledger validation with command, date, branch, commit, result, and evidence summary/artifact/workflow link.
- [x] Fail validation when a blocker is closed without evidence.
- [x] Fail validation when a P0/P1 item has no next action-equivalent field.

Acceptance:

- Vault validation catches stale/unsupported operational claims.
- Future sessions can run one preflight and see current blockers, risks, debt, next actions, and evidence.

Validation:

```powershell
./scripts/check_obsidian_vault.ps1
```

Local result 2026-06-05: passed after adding semantic validation for [[Audit Resolution Tracker]], [[Technical Debt Register]], [[Risk Register]], [[BLOCKERS]], [[Project Metrics]], [[Recommended Next Actions]], and [[Repository Map]].

## Phase 10: Device And Media Reality Proof

Priority: P0 before public launch

Status: Scoped and executable proof hook added 2026-06-05; release proof remains blocked because no Android device/emulator was attached and cross-peer device directions were not run.

Fixes: BLK-001, BLK-007, SAR-001, SAR-004.

Purpose: Prove calls work where users actually run them.

Files:

- Modify: `obsidian-vault/09-Testing/Scenario Coverage Matrix.md`
- Modify: `obsidian-vault/09-Testing/Emulator Test Matrix.md`
- Modify: Appium or local QA harness files if selected.
- Modify: stable widget keys/locators only where missing.

Steps:

- [x] Define target matrix: Android to Android, Windows to Windows, Android to Windows, Windows to Android.
- [x] Include caller/receiver direction, mic denied, camera denied, network loss, app close, and stale lock cases.
- [x] Add an opt-in real media capture proof test: `apps/rain/integration_test/device_media_reality_proof_test.dart`.
- [x] Inspect current Appium/local QA harness and stable auth locators.
- [ ] Add call-flow Appium locators only after a real call smoke path is selected; existing call UI uses stable `rain-call-*` keys, while the Appium smoke config currently covers auth only.
- [x] Record device/emulator run evidence and blocker truth in vault.
- [x] Keep Appium instability non-blocking for development but blocking for public release if no replacement proof exists.

Evidence 2026-06-05:

- Context7 Flutter documentation check confirmed `integration_test` is the correct Flutter mechanism for device end-to-end tests and that `flutter test integration_test/...` can target attached Android devices.
- `C:\android-flutter-qa-toolkit\scripts\test-env.ps1` passed and detected the Android QA toolkit, Flutter 3.44.0, Dart 3.12.0, Java 17, Android SDK, Appium URL, and `D:\android-test-artifacts`.
- `flutter devices` from `apps\rain` found Windows, Chrome, and Edge only; `adb devices` listed no attached Android device.
- `flutter emulators` listed `QA_Medium_API_36_1`, but it was not running in this phase.
- Existing `apps\rain\qa.appium.json` targets only the auth toggle smoke. The latest saved Rain Appium logs under `D:\android-test-artifacts\rain\20260530-180653-appium-smoke` timed out in WebDriver and do not prove call/media behavior.
- `flutter analyze integration_test\device_media_reality_proof_test.dart` from `apps\rain` passed after the opt-in skip contract was corrected.
- `flutter test test\voice_call_runtime_media_path_test.dart --reporter expanded` from `apps\rain` passed after adding the opt-in integration proof file.
- `flutter test integration_test\device_media_reality_proof_test.dart --reporter expanded` timed out and is not pass evidence.
- `flutter test integration_test\device_media_reality_proof_test.dart -d windows --no-pub --reporter expanded` failed before test execution because the Windows Firebase plugin CMake generation could not find extracted Firebase C++ SDK targets; this is build-environment evidence, not media proof.
- `dart run melos run analyze` passed across the workspace after the Phase 10 proof hook and vault sync.
- `dart run melos run test` passed across the workspace after the Phase 10 proof hook and vault sync.

Acceptance:

- Voice/video setup reliability is proven across target directions or explicitly scoped down.
- Manual/device evidence is recorded with version, commit, OS/device, and result.

## Cross-Phase Commit Strategy

Use small commits:

- `docs: add senior audit remediation plan`
- `test: capture stale presence action gaps`
- `fix: centralize peer action connectivity snapshot`
- `test: cover firebase stale call locks`
- `fix: repair stale firebase call locks conservatively`
- `refactor: extract call error classifier`
- `refactor: extract call room reconciler`
- `fix: sanitize diagnostics recursively`
- `docs: declare local storage threat model`
- `fix: add message indexes and paged conversation reads`
- `fix: stream file receives through persistent sinks`
- `ci: unify release validation gates`
- `tools: enforce vault evidence semantics`

## Hard Stop Rules

Stop and reassess if:

- A call-lock fix deletes a newer lock.
- A presence fix creates duplicate action truth.
- A runtime refactor changes behavior before characterization tests exist.
- Diagnostics become more detailed before sanitizer proof passes.
- Release workflow edits create any artifact path without validation evidence.
- Vault status claims pass despite missing evidence.

## Final Definition Of Done

This plan is complete only when:

- SAR-001 through SAR-012 are closed or explicitly accepted with documented risk.
- All active P0 blockers in [[BLOCKERS]] have evidence-backed exit.
- `dart run melos run analyze` passes.
- `dart run melos run test` passes.
- Firebase backend validation passes where Firebase behavior changed.
- Firebase emulator integration passes where signaling/rules behavior changed.
- `./scripts/check_obsidian_vault.ps1` passes.
- Release artifacts cannot bypass the hard validation gate.
- Vault evidence proves the claims it makes.
