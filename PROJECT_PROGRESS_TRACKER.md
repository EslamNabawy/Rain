# PROJECT PROGRESS TRACKER

**Live status of the Rain implementation master plan.** Source: `01_IMPLEMENTATION_MASTER_PLAN.md` + phase docs `02_PHASE_01_*.md` … `06_PHASE_05_*.md`.
**Upstream audit:** `PROJECT_DEEP_ANALYSIS.md`, `02_ENGINEERING_BACKLOG.md` (TASK-001…021).
**Rule:** Update after every task. Keep % honest.

---

## 1. Overall Progress
- **Phase progress:** P1 DONE+ · P2 DONE · P3 IN PROGRESS · P4 PARTIAL (ECDH + v2 fallback) · CI HARDENED · WORKSPACE TIDIED.
- **Task progress:** 10 / 21 tasks DONE (TASK-006, 007, 008, 015, 018, 019, 020, + TASK-003.1, + NEW-001, + F-011). TASK-005 reverted/blocked. TASK-016 verified-covered. TASK-002 key-bootstrap + TASK-001 crypto core done (wiring deferred). TASK-001.3 ECDH derivation + TASK-001.4 v=1/v=2 decrypt fallback done (adapter wiring still deferred).
- **Debt closed:** 4 / 17 (DEBT-012 logging, DEBT-013 LICENSE, DEBT-014 root cleanup, + brace-expansion npm vuln).
- **Production Readiness FAILs:** 3 (Security ×2, Monitoring) — target 0 by end of P5.
- **CI:** All gates green on `dev@0941eef`. Validated release `rain-validated-5-1` published (3 artifacts).
- **New fixes this session:** TASK-001.3 (ECDH `derivePairKeyMaterial` — local X25519 private + peer public → shared secret → `pairKeyMaterial` for `SignalingCipher.forPair`), TASK-001.4 (`decryptPayload` auto-routes v=2 envelopes to `decryptPayloadV2`), +7 unit tests (3 ECDH: round-trip, cross-pair isolation, stability; 4 v=1/v=2 fallback: decrypt v=2 with pair key, reject v=2 without pair key, legacy v=1, plaintext pass-through). All 4 packages GREEN (+61 rain_core, +276 protocol_brain, +744 rain, peer_core).

---

## 2. Phase Progress

| Phase | Name | Status | Tasks DONE | Exit gate |
|---|---|---|---|---|
|| 1 | Call Reliability Hardening | DONE | 3/5 (TASK-006/007/008 DONE; TASK-005 REVERTED; TASK-016 covered) | Exit: tests green + analyze clean (both met) |
|| 2 | Stability & Hygiene | DONE* | 3/6 (TASK-018/019/020 DONE; TASK-021/017*/016* DEFERRED — need CI runner/emulator) | Exit: analyze+tests green (met); scaffolds deferred w/ documented reason |
|| 3 | Security Foundation | IN PROGRESS | 1/2 (TASK-015 DONE; TASK-002 PARTIAL: key bootstrap DONE, native open path DEFERRED — EOL sqlcipher lib) | Go if keystore round-trips + DB non-plaintext |
| 4 | Real E2E + Architecture | NOT STARTED | 0/3 | Go if per-pair keys proven + no lib/>800 |
| 5 | Polish & Production Gate | NOT STARTED | 0/4* | Go if readiness 0 FAIL |

\* P2 = 018,019,020,021 + 017*(scaffold) + DEBT-016*(scaffold). P5 = 017(finish)+DEBT-016(finish)+DEBT-017+a11y+docs.

---

## 3. Task Checklist (TASK-001…021)

| ID | Title | Phase | Status | Owner | Notes |
|---|---|---|---|---|
|| 005 | Watcher before startOutgoing | P1 | ✗ REVERTED/BLOCKED | | REVERTED: reorder regresses `friend_flow_test` permission-error path (`adapter.rooms` empty) + contradicts in-repo rationale ("watcher-first causes caller permission denials when room absent"). "Missed-answer" premise UNVERIFIED — needs prod evidence before re-touching. |
| 006 | Remove failed→idle | P1 | ✅ DONE | | `voice_call_session.dart:1134` `_ => false`; + regression test `failed session is terminal...` (protocol_brain, GREEN) |
|| 007 | Mute lock serialize | P1 | ✅ DONE | | `call_media_connection.dart` `_mediaControlLock` + `_serializeMediaControl()` wraps setMicrophoneMuted/setCameraMuted/setDeafened (F-012). + race test (peer_core, GREEN) |
| 008 | beforeOpen validation | P1 | ✅ DONE | | `rain_database.dart` MigrationStrategy.beforeOpen runs `PRAGMA foreign_key_check` on open. NOTE: drift 2.33 has no `validateDatabaseSchema` export; table-introspection unreliable inside open txn, so FK-check only. + test (rain_core, GREEN) |
| 016 | Session reuse guard | P1 | ✅ COVERED (no code) | | Falsified: existing guards (`_isLiveVoiceCallSession` + interaction guard) + tests already cover it. `runtime_interaction_guard_test.dart` (duplicate retry blocked) + friend_flow `duplicate incoming invite`/`cancel during outgoing` all GREEN. No change needed. |
|| 018 | debugPrint→sanitizer | P2 | ✅ DONE | | 21 `debugPrint` in `lib/` routed to new `RainDebugLog` (sanitized sink) in `rain_debug_log_service.dart`; wired in `main.dart`. CI grep gate added to `ci.yml`+`main-merge-gate.yml` (excludes `crash_diagnostics_service.dart` — lowest sanitizing layer, would be circular import). Stale FLAWS doc claim (L129) fixed. Analyze+tests GREEN. |
| 019 | LICENSE | P2 | ✅ DONE | | MIT `LICENSE` added; README links it. |
| 020 | Root cleanup | P2 | ✅ DONE | | `IDEA.md`/`deps.txt` gitignored (verified no longer untracked). |
| 021 | Windows merge-gate | P2 | ⏸ DEFERRED | | Needs `windows-2022` runner + emulator in CI — cannot verify locally. Plan/code is ready; gate added only after a dry CI run. |
| 017* | Rules fuzz scaffold | P2 | ⏸ DEFERRED | | Needs Firebase emulator (not available locally). Finish in P5. |
| 016* | Crashlytics scaffold | P2 | ⏸ DEFERRED | | Adds `firebase_crashlytics` dep + emulator test; privacy-gated. Finish in P5. |
|| 015 | Key store + identity keypair | P3 | ✅ DONE | | **KEYSTONE** — done. `KeyStoreService` interface + `InMemoryKeyStoreService` (rain_core); `FlutterSecureStorageKeyStoreService` (apps/rain, fss ^10.3.1). `IdentityKeyRepository` X25519 generate-once + round-trip (rain_core, test GREEN). `IdentityTable.signingPublicKey` col + schema 6→7 migration (guarded `_hasTable`). RTDB `publishIdentitySigningKey` on `SignalingAdapter` + wired into `identity_providers.register`. Analyze+full test GREEN (all 4 pkgs). |
|| 002 | SQLCipher DB | P3 | 🟡 PARTIAL (key bootstrap) | ⏸ DEFERRED (open path) | **Key bootstrap DONE** (verifiable): `DatabaseKeyService` generates+persists 32-byte base64 DB key via `KeyStoreService` (rain_core, test GREEN). **Open path + plaintext→cipher migration DEFERRED**: requires a SQLCipher-enabled `sqlite3` native lib; the legacy `sqlcipher_flutter_libs` pkg is **end-of-life** (its own docs say unneeded after `sqlite3` v3.x, which the repo uses) and is unverifiable in this env (native-asset load fails, no Android/Windows build here). Must settle the native dep + emulator/device-verify before wiring `PRAGMA key` + migration. |
|| 001 | Per-pair X25519 E2E | P4 | 🟡 PARTIAL (crypto core + ECDH + v2 fallback) | ⏸ DEFERRED (adapter wiring) | **Crypto core DONE** (verifiable): `SignalingCipher.forPair(...)` + `encryptPayloadV2`/`decryptPayloadV2` + `isEncryptedEnvelopeV2` in `signaling_cipher.dart`. Per-pair HKDF binds `from`/`to`/`sessionId`/`room`/`purpose`/`v=2` + random 16-byte per-envelope salt. 4 unit tests prove: round-trip, per-pair isolation, random-salt diff, v=1 root-key holder cannot decrypt v=2. **ECDH derivation DONE** (TASK-001.3, verifiable): `IdentityKeyRepository.derivePairKeyMaterial(peerPublicKey)` computes X25519 ECDH shared secret from local private key + peer public key → base64 `pairKeyMaterial` for `SignalingCipher.forPair()`. 3 unit tests: round-trip (both parties agree), cross-pair isolation (Alice↔Bob ≠ Alice↔Carol), stability across repeated calls. **v=1/v=2 decrypt fallback DONE** (TASK-001.4, verifiable): `decryptPayload` now detects v=2 envelopes and auto-routes to `decryptPayloadV2`; v=1 and plaintext pass-through unchanged. 4 unit tests. Analyze + all 4 pkg tests GREEN (+7 tests). **Adapter wiring (TASK-1.3 runtime) + v=1 fallback window (1.4 deploy) + `validateForRelease` (1.5) DEFERRED**: need Firebase emulator contract test (third-party-can't-decrypt) + adapter code path changes — unverifiable locally. |
|| 003 | App unit tests + split 9k | P4 | 🟡 PARTIAL (3.1 done) | ⏸ DEFERRED (3.2/3.3/3.4) | **3.1 DONE** (verifiable): `apps/rain/test/application/state/runtime_providers_test.dart` mirrors `runtime_providers.dart` pure providers via `ProviderContainer` + `appBootstrapProvider.overrideWithValue` (in-memory DB + NoopSignalingAdapter). Analyze+rain test GREEN. **3.2/3.3/3.4 DEFERRED**: coordinator unit tests (need TASK-004 extraction first), `friend_flow_test.dart` 9k split (large, parallel w/ 001), CI coverage gate 40% (needs `flutter test --coverage` parsing — unverifiable here). |
|| 004 | God-object split | P4 | 🟡 PARTIAL (4.1 golden) | ⏸ DEFERRED (4.2-4.8) | **4.1 golden DONE** (verifiable): `voice_call_state_coordinator_test.dart` now locks terminal-phase invariants — `canClearExpiredStartBlock` is false for `failed`/`idle`/`ending` (TASK-006/016 no-resurrection guarantee) and true for the 4 live phases. Analyze+rain test GREEN (+744). **4.2-4.8 DEFERRED**: actual extractions of `voice_call_runtime.dart` (3,106) / `firebase_adapter.dart` (2,912) / `rain_runtime_controller.dart` (2,573) into coordinators/adapters — HIGH-risk XL refactor needing the emulator/golden harness + Windows/Android verification, unverifiable locally. |
|| 017 | Rules fuzz finish | P5 | ⏸ DEFERRED | | needs Firebase emulator (≥200 cases) — same constraint as 017* |
|| 016 | Crashlytics finish | P5 | ⏸ DEFERRED | | sanitized-only routing needs emulator/demo-build proof — same as 016* |
|| 017c | CODEOWNERS | P5 | ✅ DONE | | `CODEOWNERS` created at repo root covering runtime/protocol_brain/backend/firebase/rain_core/ci. Branch protection is a manual GitHub-setting step (documented inline). |
|| a11y | Accessibility pass | P5 | ⏸ DEFERRED | | needs UI Semantics audit + widget-test assertions; cannot verify blind locally. Core screens Semantics status UNKNOWN until audited. |
|| docs | README/ADR/vault | P5 | 🟡 PARTIAL | ⏸ DEFERRED (vault) | README privacy caveat made honest re: TASK-001 (per-pair cipher core done, adapter wiring pending) + TASK-002 (key bootstrap done, SQLCipher native open path pending). ADR-010/vault/CONTINUITY deferred per AGENTS (vault sync not required this session). |

---

## 4. Blockers
- **BLOCKER-1 (critical path):** TASK-001 and TASK-002 are **blocked** until TASK-015 (key store) merges. Do not start P4 crypto or the SQLCipher migration before P3 completes.
- **BLOCKER-2 (RESOLVED):** `dart run melos list` works (auto-discovers workspace) — all validation gates unblocked.
- **BLOCKER-3 (platform):** Windows `flutter_secure_storage` is file-backed, not TPM — accepted for v1 but document; if it misbehaves in P3, fallback to default encrypted file.
- **BLOCKER-4 (NEW — TASK-005):** "Watcher-before-startOutgoing" reorder REVERTED. It regresses the `friend_flow_test` permission-error path and contradicts the existing in-repo test rationale. The 2026-06-18 "missed-answer" premise is UNVERIFIED — do NOT re-apply without production evidence (e.g. a real Firebase emulator run showing a dropped fast answer). TASK-005 demoted from "best ratio" to "blocked/pending investigation."

---

## 5. Risks
| Risk | Phase | Mitigation | Status |
|---|---|---|---|
| Per-pair crypto breaks old builds | P4 | Versioned envelopes v=1 fallback N weeks | OPEN (plan) |
| SQLCipher migration corrupts DB | P3 | Copy to NEW cipher file; delete plaintext only after parity | OPEN (plan) |
| God-object extraction drifts behavior | P4 | Characterization/golden tests before each move; feature-flag | OPEN (plan) |
| Keystore missing on Windows | P3 | flutter_secure_storage default fallback | OPEN (plan) |
| TASK-016 wrong assumption | P1 | Falsifiable reuse-guard test; demote to doc if disproven | OPEN (plan) |

---

## 6. Notes
- 2026-07-19: Second-pass audit + 10 deliverables + master plan generated. No code written then.
- 2026-07-19 (exec): Tooling verified (`dart run melos list` works; `dart analyze` clean baseline).
- **TASK-006 DONE**: removed `failed→idle` transition (`voice_call_session.dart`), added regression test (GREEN in protocol_brain full suite: "All tests passed!").
- **TASK-005 REVERTED**: reordering `_watchFirebaseVoiceCall` before `startOutgoing()` broke `friend_flow_test.dart:3272` (`adapter.rooms.single` → "No element" because the room is created by `startOutgoing`, and the synthetic watcher error fires before it runs). Also contradicts the in-repo test rationale at `voice_call_runtime_media_path_test.dart:42`. The "fast-answer dropped in subscription gap" premise from the 2026-06-18 audit is NOT confirmed by any test — treat as unverified. Demoted to BLOCKED.
- Confident (High) for code-path findings; Medium for TASK-016 + Windows keystore behavior. TASK-005 now LOW-confidence premise.

---

## 7. Decisions Log
- Phase order = reliability → hygiene → security-foundation → E2E/arch → polish. Keystone = TASK-015.
- LICENSE = MIT. Crashlytics gated off in demo builds (privacy).
- DB migration writes to NEW file; original preserved until verified copy (safe revert).
- TASK-004 extractions feature-flagged individually (no big-bang refactor).

---

## 8. Change Log
| Date | Change | By |
|---|---|---|
| 2026-07-19 | Created master plan + 5 phase docs + progress tracker | Hermes Agent (planning) |
| 2026-07-19 (exec) | **P2 complete (partial).** TASK-018 (21 `debugPrint` → `RainDebugLog` sanitized sink + CI grep gate in ci.yml/main-merge-gate.yml; stale FLAWS doc L129 fixed), TASK-019 (MIT LICENSE + README link), TASK-020 (`IDEA.md`/`deps.txt` gitignored) — all DONE. TASK-021 (Windows merge-gate), TASK-017* (rules fuzz), TASK-016* (Crashlytics) DEFERRED: require `windows-2022` CI runner + Firebase emulator, not locally verifiable. Full `melos run analyze` + `melos run test` (incl. rain +739) GREEN. | Hermes Agent |
| 2026-07-21 | **P1 + P3 CI hardening + workspace tidy.** NEW-001 (media interruption → `_serializeMediaControl` lock), F-011 (`_pendingMediaRestart` queue instead of drop), CI Windows config-only gate, CI file-size lint (3200 hard / 800 warn), CI coverage floor soft gate (lcov-free parsing), npm audit clean (brace-expansion vuln fixed), workspace tidy (34→6 root .md moved to `docs/`), vault date refresh. All 4 pkg tests GREEN. | Hermes Agent |
| 2026-07-21 (P4) | **Phase 4 verifiable slice.** TASK-001.3: `IdentityKeyRepository.derivePairKeyMaterial(peerPublicKey)` — ECDH X25519 shared secret derivation (local private + peer public → base64 `pairKeyMaterial`), 3 unit tests (round-trip, cross-pair isolation, stability). TASK-001.4: `SignalingCipher.decryptPayload` auto-routes v=2 envelopes to `decryptPayloadV2` (v=1 + plaintext unchanged), 4 unit tests. All 4 pkg tests GREEN (rain_core +61, protocol_brain +276, rain +744, peer_core). Adapter wiring still DEFERRED (needs emulator). | Hermes Agent |

---

## 9. Next Actions (immediate)
1. **P1 + P2 core DONE. P4 verifiable slice DONE.** 10 tasks complete (006,007,008,018,019,020) + 001.3/001.4 (ECDH + v2 fallback). Deferred: 005 (blocked), 021/017*/016* (need CI/emulator), 001 adapter wiring (needs emulator).
2. **Commit P4 slice** on `dev` — changes are local-only (not yet committed). Recommend: `git add packages/rain_core/lib/identity/identity_key_repository.dart packages/rain_core/test/identity_key_repository_test.dart packages/protocol_brain/lib/adapters/signaling_cipher.dart packages/protocol_brain/test/signaling_cipher_test.dart PROJECT_PROGRESS_TRACKER.md`.
3. **Remaining Phase 4 (DEFERRED):** adapter wiring (replace `SignalingCipher.demo()` with per-pair cipher at runtime), v=1 fallback window, `validateForRelease` check, Firebase emulator contract test (third-party-cannot-decrypt). All need emulator/device verification.
4. **Phase 5 (God-Object Decomposition):** extractions of `voice_call_runtime.dart` (3,106) / `firebase_adapter.dart` (2,931) / `rain_runtime_controller.dart` (2,573) — HIGH-risk XL refactor, needs golden harness + Windows/Android verification.
5. **TASK-005:** leave BLOCKED until Firebase-emulator proof of missed fast-answer.
6. **SQLCipher (TASK-002):** key bootstrap done; native open path deferred — settle `sqlite3` native dep first.

---

*This file is the single live status surface. Edit the checkboxes + % after every task. Keep the "Next Actions" block pointing at the current work.*
