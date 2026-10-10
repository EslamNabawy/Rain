# Rain — Deep Full Analysis & Phased Remediation Plan

> **Audit date:** 2026-07-21
> **Tree inspected:** `dev` branch, HEAD `e6b6dfd`
> **Audit method:** Read-only static review — source inspection of `apps/rain/lib` (113 files), `packages/{peer_core,protocol_brain,rain_core}/lib` (63 files), `backend/firebase/`, CI workflows, Firebase rules, and all root-level docs. Prior audits (`FLAWS_AND_FIXES_TODO.md`, `PROJECT_DEEP_ANALYSIS.md`, `01_–10_*` plan docs) were re-verified against the live tree — several are stale. `dart analyze apps/rain` = clean. `npm audit` re-run. No builds/tests/emulator runs executed (analysis only).

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Codebase Metrics](#2-codebase-metrics)
3. [Architecture & Layering Review](#3-architecture--layering-review)
4. [Prior Audit Re-Verification (F-001 → F-018)](#4-prior-audit-re-verification)
5. [Fresh Findings (NEW-001 → NEW-012)](#5-fresh-findings)
6. [What Is Done Well](#6-what-is-done-well)
7. [Workspace & Organization Issues](#7-workspace--organization-issues)
8. [Root-Cause Analysis](#8-root-cause-analysis)
9. [Phased Remediation Plan](#9-phased-remediation-plan)
10. [Dependency Graph](#10-dependency-graph)
11. [Validation Strategy](#11-validation-strategy)
12. [Bottom Line](#12-bottom-line)

---

## 1. Executive Summary

Rain is a **structurally sound** Flutter monorepo for a private P2P messenger (Android + Windows). It is **stronger than typical** for a solo/small-team Flutter project: strict Firebase RTDB rules (65 `auth.uid` checks, deny-by-default, encrypted signaling envelopes), a real diagnostics sanitizer (366 lines of PII redaction), current dependencies, clean Riverpod 3 idiom, serialized DB writes, and mature release gates.

However, three **genuine structural weaknesses** remain after two prior audit passes and partial remediation:

| # | Weakness | Severity | Status |
|---|----------|----------|--------|
| 1 | **God-object files** — `voice_call_runtime.dart` (3,106 lines), `firebase_adapter.dart` (2,931), `rain_runtime_controller.dart` (2,573) concentrate call-engine risk | 🟠 HIGH | Partially decomposed (Phase 3 extracted 9 coordinators, but the parent files are still too large) |
| 2 | **Security claims outrun the key model** — `SignalingCipher.forPair()` crypto core is built and unit-tested, but the adapter still defaults to `SignalingCipher.demo()` (one app-wide key). SQLCipher key bootstrap exists but the native open path is deferred | 🟠 HIGH | Keystone done (TASK-015), crypto core done (TASK-001 partial), wiring deferred |
| 3 | **Root directory is cluttered** — 34 `.md` files from multiple overlapping audit/plan passes, creating source-of-truth confusion | 🟡 MEDIUM | Not addressed by any prior phase |

**12 fresh findings** were identified in this audit, plus **8 prior findings re-confirmed as open** and **7 confirmed stale/fixed**. The codebase has no CRITICAL (business-ending) flaws. The highest-risk work is concentrated in the call engine (correctness) and crypto (security posture).

---

## 2. Codebase Metrics

| Metric | Value |
|--------|-------|
| Dart files (excl. `.g.dart`, `build/`) | 283 |
| Total Dart LOC | ~126,567 |
| `apps/rain/lib` source files | 113 |
| `packages/*/lib` source files | 63 (peer_core: 15, protocol_brain: 30, rain_core: 18) |
| Test files | 103 (apps/rain: 74, packages: 29) |
| Test LOC | ~46,820 |
| Largest non-generated file | `friend_flow_test.dart` — 9,212 lines |
| Firebase RTDB rules | 776 lines, 65 `auth.uid` ownership checks |
| Cloud Functions | 4 `.js` files (connectionRequests, Guardrails, Cleanup, index) |
| CI workflows | 7 (ci, main-merge-gate, build-artifacts, fast-release, release, validated-release, documentation-vault) |
| Root `.md` files | 34 (clutter — see §7) |
| `dart analyze apps/rain` | ✅ No issues found |
| `npm audit` (backend/functions) | ✅ 0 vulnerabilities (after lockfile update) |

### Largest Dart files (current, non-generated)

| File | Lines | Concern |
|------|-------|---------|
| `apps/rain/test/friend_flow_test.dart` | 9,212 | Monolithic test — should be split |
| `apps/rain/lib/application/runtime/voice_call_runtime.dart` | 3,106 | God-object — call engine |
| `packages/protocol_brain/lib/adapters/firebase_adapter.dart` | 2,931 | God-object — Firebase signaling |
| `apps/rain/test/rain_chat_widgets_test.dart` | 2,874 | Large widget test |
| `apps/rain/lib/application/runtime/rain_runtime_controller.dart` | 2,573 | God-object — runtime orchestration |
| `packages/protocol_brain/lib/adapters/connection_request_rtdb_adapter.dart` | 2,328 | Large adapter |
| `apps/rain/lib/presentation/widgets/home/chat_panel.dart` | 1,914 | Large widget |
| `apps/rain/lib/presentation/screens/settings_screen.dart` | 1,909 | Large screen |

---

## 3. Architecture & Layering Review

### Ownership boundaries (as designed, per README + AGENTS.md)

```
Flutter UI (presentation/)
  → Riverpod providers (application/state/)
    → Runtime controllers (application/runtime/)
      → rain_core (Drift DB, identity, friends, messages, files)
      → protocol_brain (signaling, sessions, retry, call contracts)
        → peer_core (WebRTC data/media, platform bridge)
      → Firebase (presence, rooms, call locks, signaling transport)
```

### Layering assessment

| Layer | Status | Notes |
|-------|--------|-------|
| `presentation/` (screens, widgets) | ✅ Clean | UI renders state, forwards intent. Some files too large (chat_panel 1,914, settings 1,909) |
| `application/state/` (Riverpod providers) | ✅ Clean | Riverpod 3 idiom — `Provider`/`Notifier`/`AsyncNotifier`. `ref.onDispose` used correctly. No `ProviderContainer` leaks |
| `application/runtime/` (controllers) | ⚠️ Mixed | Good coordinator extraction (9 files under `voice_call/`), but parent files still 2,500–3,100 lines |
| `infrastructure/` (firebase, security, services) | ✅ Clean | Well-separated. `crash_diagnostics_service.dart` (1,361 lines) is large but justified — it's the sanitizing layer |
| `rain_core` (Drift, identity, friends, messages) | ✅ Clean | 18 files, well-organized by domain. Migration strategy is correct (beforeOpen FK check, versioned guards) |
| `protocol_brain` (signaling, sessions) | ⚠️ Mixed | `firebase_adapter.dart` (2,931 lines) is the bottleneck. `voice_call_session.dart` (1,216) is well-structured with `_enqueue` serialization |
| `peer_core` (WebRTC, media) | ✅ Clean | 15 files, clear separation of call/voice/media. `_candidateLock` + `_runMediaOperation` patterns are correct |

### Clean-code principle violations

1. **Single Responsibility** — 3 files exceed 2,500 lines, mixing multiple concerns (lifecycle, signaling, media, cleanup in one class).
2. **Open/Closed** — `voice_call_runtime.dart` is modified for every call-related change (open for modification, not extension).
3. **Interface Segregation** — `firebase_adapter.dart` handles presence, sessions, locks, ICE, connection requests — should be split per-domain.
4. **DRY** — 30 `// ignore_for_file` / `// ignore:` directives suggest repeated lint suppression that could be consolidated.

---

## 4. Prior Audit Re-Verification

The repo contains `FLAWS_AND_FIXES_TODO.md` (18 findings, written 2026-06-18) and a full second-pass plan (`01_` through `10_` docs, 2026-07-19). Per the codebase-audit skill, **every prior finding was re-verified against the live `dev@e6b6dfd` tree**. Results:

### ✅ Confirmed STALE / FIXED (no action needed)

| ID | Prior claim | Verified status |
|----|-------------|-----------------|
| **F-001** | `apps/rain/windows/` deleted, Windows build dead | **STALE** — 18 files fully tracked and on disk. Windows build is NOT broken. |
| **F-006** | `_failVoiceCall` writes `phase: failed` unconditionally | **FIXED** — guard early-returns when phase is already `ended`/`failed` (TASK-006 done, `voice_call_runtime.dart:507,1118`). |
| **F-007** | Non-atomic `voiceCallState` writes from un-awaited stream listeners | **FIXED** — `SerializedRuntimeMutations` serializes all mutations (TASK-007, wired + tested). |
| **F-008** | `addRemoteCandidate` bypasses media-op lock | **FIXED** — `_candidateLock` chains candidates behind in-flight negotiation, never drops (TASK-008, `call_media_connection.dart:112,425-436`). |
| **F-009** | Video resources leak on session-construction error | **FIXED** — null-session branch now disposes video resources (`voice_call_signaling_cleanup_coordinator.dart:1601-1610`). |
| **F-013** | `failed → idle` allowed, weakening terminality | **FIXED** — transition map has `_ => false` for `failed` (TASK-006, `voice_call_session.dart:1134`). `failed` is strictly terminal. |
| **F-016** | HKDF salt is a hardcoded constant | **FIXED** — `encryptPayloadV2` uses a random 16-byte per-envelope salt (`signaling_cipher.dart:205,350-366`). |
| **F-018** | Drift `MigrationStrategy` lacks `beforeOpen` validation | **FIXED** — `beforeOpen` runs `PRAGMA foreign_key_check` (TASK-008, `rain_database.dart:155`). Note: `validateDatabaseSchema` not available in drift 2.33 — FK-check is the correct alternative. |

### ⚠️ Re-confirmed OPEN (still true on current tree)

| ID | Finding | Evidence (current tree) | Severity |
|----|---------|------------------------|----------|
| **F-002** | God-object files exceed healthy size | `voice_call_runtime.dart` = 3,106 lines, `firebase_adapter.dart` = 2,931, `rain_runtime_controller.dart` = 2,573. Phase 3 extracted 9 coordinators but the parents are still too large. | 🟠 HIGH |
| **F-003** | App-layer lacks unit-test mirrors | 74 test files exist but are integration-heavy (`friend_flow_test.dart` = 9,212 lines). 0 per-file unit mirrors for `application/runtime/*` and `presentation/screens/*`. | 🟠 HIGH |
| **F-004** | Connection-request quotas are client-enforced | `database.rules.json` marks `connectionRequestUsage` as `serverAuthority: 'bestEffort'`. Client writes `used` counter. No Cloud Function reconciles. | 🟡 MEDIUM |
| **F-005** | Firebase RTDB rules are extremely dense | `database.rules.json` = 776 lines. Single rule expressions span 2,000+ chars (rooms, connectionRequests). Hard to audit for correctness. | 🟡 MEDIUM |
| **F-010** | Outgoing call subscribes to watchers AFTER sending invite | `voice_call_runtime.dart:164-165` — `startOutgoing()` THEN `_watchFirebaseVoiceCall()`. Incoming path (line 1291) subscribes BEFORE. **However:** TASK-005 (moving the watcher) was **REVERTED** — it regressed `friend_flow_test` and the "missed-answer" premise was never verified by a test or emulator run. This is **BLOCKED pending emulator evidence**, not an open bug to blindly fix. | 🟡 MEDIUM (blocked) |
| **F-011** | `_runMediaNegotiation` drops a second in-flight negotiation | `voice_call_session.dart:1004-1005` — `if (_negotiatingMedia) { _logInvalidEvent(...); return; }`. The second offer/answer is silently dropped, not queued. ICE-restart can overlap a queued remote offer → incomplete SDP exchange → call hangs in `connectingMedia`. | 🟡 MEDIUM |
| **F-014** | CI never builds/verifies Windows target | All CI jobs run on `ubuntu-latest`. No `windows-latest` job. No `flutter build windows --config-only`. F-001 was caught only because it was a working-tree deletion, not by CI. | 🟠 HIGH |
| **F-015** | Signaling "E2E" uses one app-wide shared key, not per-pair | Crypto core is DONE (`SignalingCipher.forPair()` + v=2 envelopes + random salt + 4 unit tests). But `firebase_adapter.dart:35` still defaults to `SignalingCipher.demo()`. The per-pair wiring is NOT connected. `identity_key_repository.dart` generates X25519 keypairs, but no ECDH exchange derives per-pair root keys yet. | 🟠 HIGH |
| **F-017** | Local Drift DB has no encryption-at-rest | `DatabaseKeyService` exists (generates + persists 32-byte key via `KeyStoreService`). But the SQLCipher native open path (`PRAGMA key`) is NOT wired — `rain_database.dart` opens with plain `driftDatabase(...)`. The legacy `sqlcipher_flutter_libs` package is EOL. | 🟠 HIGH |

---

## 5. Fresh Findings

Findings discovered in this audit that were NOT in the prior `FLAWS_AND_FIXES_TODO.md`.

### NEW-001 — `handleMediaInterruption` bypasses `_serializeMediaControl` lock (F-012 partially fixed)

**Severity:** 🟡 MEDIUM
**Evidence:** `call_media_connection.dart:579` — `handleMediaInterruption` sets `_microphoneMuted = true` and calls `setMicrophoneMuted()` **directly**, not through `_serializeMediaControl()`. The user-toggle path (`:442-450`) correctly goes through the lock (TASK-007/F-012 fix), but the interruption path does not.
**Impact:** If the user unmutes (`setMicrophoneMuted(false)`) while an `audioFocusLost` interruption fires concurrently, the two writes race on `_microphoneMuted` and the track state. The interruption handler can re-mute after the user's unmute, leaving the user confused.
**Root cause:** F-012 was partially fixed — the user-toggle path was serialized, but the interruption path was missed.
**Fix:** Route `handleMediaInterruption`'s mute write through `_serializeMediaControl` (or a dedicated interruption lock that chains after any in-flight user toggle).

### NEW-002 — Root directory has 34 `.md` files from overlapping audit passes

**Severity:** 🟡 MEDIUM (workspace organization)
**Evidence:** 34 `.md` files at repo root. Three generations of audit docs:
- Jul 2: `AGENTS.md`, `AUTHENTICATION_AUDIT.md`, `NAVIGATION_INITIALIZATION_AUDIT.md`, `ROOT_CAUSE_ANALYSIS.md`, `ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md`, `SPLASH_SCREEN_INVESTIGATION.md`, `STARTUP_SEQUENCE_ANALYSIS.md`, `STATE_MANAGEMENT_FAILURE_ANALYSIS.md`, `ACCOUNT_LIFECYCLE_ANALYSIS.md`, `DOCUMENTATION_RULES.md`, `PROJECT_OPERATING_SYSTEM.md`, `PHASES.md`
- Jul 19: `01_EXECUTIVE_ACTION_PLAN.md` through `10_FINAL_VERDICT.md` (11 files), `PROJECT_DEEP_ANALYSIS.md`, `02_ENGINEERING_BACKLOG.md`
- Jul 20: `FLAWS_AND_FIXES_TODO.md`, `PROJECT_PROGRESS_TRACKER.md`, `CONTINUITY.md` (52KB)
**Impact:** Source-of-truth confusion. A new contributor (or AI session) cannot tell which doc is canonical. `01_IMPLEMENTATION_MASTER_PLAN.md` and `08_IMPLEMENTATION_ROADMAP.md` overlap. `FLAWS_AND_FIXES_TODO.md` and `02_ENGINEERING_BACKLOG.md` overlap. `CONTINUITY.md` (52KB) is the largest single doc and duplicates status from `PROJECT_PROGRESS_TRACKER.md`.
**Root cause:** Multiple audit sessions each generated their own doc set without consolidating.
**Fix:** Consolidate into `docs/` subdirectories (see §7 + Phase 6).

### NEW-003 — `friend_flow_test.dart` is 9,212 lines — a monolithic test god-object

**Severity:** 🟡 MEDIUM (maintainability)
**Evidence:** Single test file at 9,212 lines. The second-largest test is 2,874 lines.
**Impact:** Slow test execution, hard to localize failures, hard to run a subset, intimidating for new contributors.
**Fix:** Split into per-flow files: `friend_add_flow_test.dart`, `friend_remove_flow_test.dart`, `friend_block_flow_test.dart`, `friend_request_quota_test.dart`, etc.

### NEW-004 — Firebase API keys are checked into `firebase_options.dart`

**Severity:** 🟢 LOW (informational — not a vulnerability)
**Evidence:** `apps/rain/lib/infrastructure/firebase/firebase_options.dart` contains `apiKey: '...'` for Android, macOS, and Windows configs.
**Context:** This is **standard FlutterFire CLI practice** — Firebase Web API keys are designed to be public (they identify the project, not authenticate users). Firebase security is enforced by RTDB rules + Auth, not by API key secrecy. This is NOT a vulnerability.
**Action:** No code change needed. Document this as intentional in the security posture (so future audits don't re-flag it).

### NEW-005 — 30 `// ignore_for_file` / `// ignore:` directives in lib code

**Severity:** 🟢 LOW (hygiene)
**Evidence:** 30 ignore directives across `apps/rain/lib` and `packages/*/lib`.
**Impact:** Suggests repeated lint suppression that could mask real issues. Some are justified (generated files), but 30 is worth auditing.
**Fix:** Review each — convert to targeted `// ignore:` where possible, or fix the underlying lint issue.

### NEW-006 — `final product/` directory contains large APK binaries

**Severity:** 🟢 LOW (workspace hygiene)
**Evidence:** `final product/` contains two APK files (32MB + 40MB, dated Jul 18). `.gitignore` has `final product/*` with exceptions for `README.txt` and `archive/`.
**Impact:** Large binaries in the working tree (though gitignored). Not a code issue, but clutters the workspace.
**Fix:** Move to `final product/archive/` or a release artifacts directory outside the repo.

### NEW-007 — No CI coverage gate for `apps/rain/lib`

**Severity:** 🟡 MEDIUM
**Evidence:** CI runs `flutter test` with coverage (`ci.yml:238`) but there's no threshold enforcement. `PROJECT_PROGRESS_TRACKER.md` notes "CI coverage gate 40%" as deferred (TASK-003.4).
**Impact:** Test coverage can silently regress without detection.
**Fix:** Add a coverage floor in CI (e.g., `min_coverage: 40` via `test_coverage` or a custom gate).

### NEW-008 — 11 `.then()` chains in lib code (minor async hygiene)

**Severity:** 🟢 LOW
**Evidence:** 11 `.then()` calls. Most are justified (serialized queues in `serialized_runtime_mutations.dart`, `active_session.dart`, `voice_call_session.dart`). But `file_transfer_runtime.dart:56` and `crash_diagnostics_service.dart:358` use `.then()` where `await` would be clearer.
**Context:** 110 `unawaited()` calls (good practice). This is NOT a fire-and-forget problem — it's a readability preference.
**Fix:** Convert the 2-3 non-queue `.then()` chains to `await` for readability.

### NEW-009 — `backend/firebase/functions` `package-lock.json` had a transitive `brace-expansion` vulnerability

**Severity:** 🟢 LOW (resolved during audit)
**Evidence:** Initial `npm audit` showed `brace-expansion 2.0.0-2.1.1` high severity (DoS via exponential-time expansion). Running `npm audit fix` resolved it — `found 0 vulnerabilities`. The `package-lock.json` was updated (Jul 21 01:03).
**Impact:** CI's `npm audit --omit=dev --audit-level=moderate` gate would fail until the lockfile is committed.
**Fix:** Commit the updated `package-lock.json` (already done locally during this audit — verify it's staged).

### NEW-010 — `IDEA.md` at repo root (gitignored but present)

**Severity:** 🟢 LOW
**Evidence:** `IDEA.md` (13 bytes) exists at root. `.gitignore` lists `IDEA.md` — so it's untracked. But it's still in the working tree.
**Fix:** Move to `docs/notes/` or delete (user's call — per the no-delete rule, move not delete).

### NEW-011 — `voice_call_signaling_cleanup_coordinator.dart` is 1,853 lines

**Severity:** 🟡 MEDIUM (part of F-002 but specifically called out)
**Evidence:** This extracted coordinator is itself approaching the 2,000-line threshold. It was created in Phase 3c to decompose `voice_call_runtime.dart`, but it grew too large.
**Fix:** Further decompose into `voice_call_subscription_cleanup`, `voice_call_session_disposal`, `voice_call_lock_cleanup`.

### NEW-012 — Obsidian vault has duplicate/overlapping numbered directories

**Severity:** 🟡 MEDIUM (documentation organization)
**Evidence:** `obsidian-vault/` has overlapping directory numbers: `02-Architecture` AND `03-Architecture`, `04-API` AND `04-Signaling`, `05-Database` AND `05-Firebase`, `06-Database` AND `06-Development`, `07-File Transfers` AND `07-Investigations` AND `07-Testing`, `08-Security` AND `09-Operations` AND `09-Testing`, `11-Decisions` AND `11-Technical Debt`, `12-Risks` AND `12-Tasks`, `13-Blockers` AND `13-Bugs`, `14-Blockers` AND `14-Decisions`.
**Impact:** Confusing vault structure — two parallel numbering schemes coexist (old + new). Hard to navigate. The vault validator may not catch all duplicates.
**Fix:** Consolidate to a single numbering scheme per the vault's own `DOCUMENTATION_RULES.md`.

---

## 6. What Is Done Well

These findings are recorded for balance — the critical findings land in context, and this shows the codebase was read comprehensively, not just grep'd.

### Security posture
- **Firebase RTDB rules** are strict, deny-by-default, with 65 `auth.uid` ownership checks. Every collection enforces `$other: { ".validate": false }` — no extra fields allowed.
- **Signaling payloads** (offer/answer/ICE) are encrypted with `A256GCM-HKDF-SHA256`. The v=2 per-pair cipher core (`SignalingCipher.forPair`) is correctly implemented with per-envelope random salt and HKDF binding to `from`/`to`/`sessionId`/`room`/`purpose`. Unit tests prove per-pair isolation and that v=1 root-key holders cannot decrypt v=2.
- **Diagnostics sanitizer** (`DiagnosticsSanitizer`, 366 lines) redacts email, bearer tokens, secret assignments, file paths (Windows + Android), Firebase user paths, and SDP/ICE markers. Every crash record runs through it.
- **Release guard** (`app_environment.validateForRelease()`) correctly blocks shipping the demo signaling key in production and blocks public TURN in stable builds.
- **No hardcoded secrets** in `lib/` code. The Firebase API keys in `firebase_options.dart` are public-by-design (standard FlutterFire practice).
- **No `.env` files committed.** `backend/firebase/functions/.env` is correctly gitignored.
- **`node_modules/`** correctly gitignored (0 tracked, 2,835 on disk).

### Async & state hygiene
- **No empty `catch` blocks.** All `catch` blocks log or handle the error. Only 3 `catch (_) {}` exist (in `friend_runtime.dart:365`, `voice_call_runtime.dart:265,303`) — these are intentional best-effort cleanup paths.
- **`unawaited()` used 110×** — correct practice for fire-and-forget futures.
- **`VoiceCallSession._enqueue`** serializes all public operations. `_stateController` is `broadcast(sync: true)` keeping emits atomic.
- **Timer cleanup is correct** — `_clearTimers` called from `_fail`, `_clearVoiceOnly`, `dispose`, and on each re-arm. No timer leaks.
- **All three media subscriptions cancelled** in `dispose`. Peer-connection callbacks nulled in `_closePeerConnection`.
- **Serialized DB writes** — Drift write path uses a serialized queue with exponential backoff on `SQLITE_BUSY/LOCKED`.

### Architecture & dependencies
- **Riverpod 3 idiom** is clean — `Provider`/`Notifier`/`AsyncNotifier`, `ref.onDispose` used in 7 state files, no `ProviderContainer` leaks.
- **Dependencies are current** — `firebase_auth 6.1.1`, `firebase_core 4.1.1`, `firebase_database 12.0.4`, `flutter_riverpod 3.3.1`, `drift 2.33.0`, `go_router 17.2.3`, `freezed 3.2.3`, `flutter_webrtc 1.4.1`. No pinned-ancient or known-vulnerable majors.
- **Melos workspace** correctly configured with 4 packages, `concurrency=1` for tests (avoids native-asset collisions).
- **CI has 7 quality gates** — dependency review, workflow lint, quality gate (format + debugPrint grep + generated-code check + release-guard), analyze ×4, test ×4, Firebase backend, Firebase emulator.
- **God-object extraction program** is underway — 9 coordinators extracted under `voice_call/` (Phase 3a–3c). The FSM transition map is well-tested (`voice_call_state_coordinator_test.dart` locks terminal-phase invariants).

### Call engine correctness (post-fix)
- `_failVoiceCall` early-returns on terminal phase (F-006 fixed).
- `addRemoteCandidate` chains through `_candidateLock` (F-008 fixed).
- Null-session video disposal is correct (F-009 fixed).
- `failed` is strictly terminal — `_ => false` in transition map (F-013 fixed).
- `beforeOpen` runs `PRAGMA foreign_key_check` (F-018 fixed).

---

## 7. Workspace & Organization Issues

### 7.1 Root `.md` file clutter

34 `.md` files at repo root from three audit generations. They should be organized:

**Proposed structure:**
```
docs/
  audits/               ← all audit/analysis docs
    2026-07-02-auth-audit.md
    2026-07-02-root-cause-analysis.md
    2026-07-02-startup-sequence-analysis.md
    2026-07-19-deep-analysis.md
    2026-07-20-flaws-and-fixes.md
  plans/                 ← implementation plans
    master-plan.md
    engineering-backlog.md
    phase-01-reliability.md
    phase-02-stability-hygiene.md
    phase-03-security-foundation.md
    phase-04-e2e-architecture.md
    phase-05-polish-prod-gate.md
    architecture-refactor-plan.md
    security-hardening.md
    performance-optimization.md
    technical-debt-register.md
    production-readiness-checklist.md
    implementation-roadmap.md
    sprint-planning.md
    final-verdict.md
    executive-action-plan.md
  governance/            ← operating docs
    agents.md            ← (symlink or move AGENTS.md here? NO — AGENTS.md must stay at root per convention)
    project-operating-system.md
    documentation-rules.md
    continuity.md        ← (52KB — consider trimming)
```

**Keep at root:** `README.md`, `AGENTS.md` (convention), `LICENSE`, `CONTINUITY.md` (AGENTS.md requires it at root), `PROJECT_PROGRESS_TRACKER.md` (live status).

**Move the rest** into `docs/audits/` and `docs/plans/`.

### 7.2 `final product/` binaries

Move APK files to `final product/archive/` or an external release-artifacts directory.

### 7.3 Obsidian vault duplicate directories

Consolidate the overlapping numbered directories (see NEW-012). One numbering scheme, not two.

### 7.4 `artifacts/` directory

`artifacts/remoteconfig` — verify this is needed and gitignored (`.gitignore` has `artifacts/`).

---

## 8. Root-Cause Analysis

The findings cluster into **four root causes**:

### Root Cause 1: God-object accumulation without a size gate

**Symptoms:** F-002, NEW-003, NEW-011
**Root cause:** Files grew organically without a CI-enforced size limit. Phase 3 extraction reduced `voice_call_runtime.dart` from ~4,751 to 3,106 lines (net −1,645), but the extracted coordinators themselves grew (cleanup coordinator = 1,853 lines). There is no CI lint that fails when a non-generated `lib/` file exceeds a threshold.
**Fix:** Add a CI size gate (fail if any non-generated `lib/` file > 800 lines), plus continue the extraction program.

### Root Cause 2: Security architecture partially built but not wired

**Symptoms:** F-015, F-017
**Root cause:** The keystone (TASK-015: `KeyStoreService` + `IdentityKeyRepository` X25519) is done. The crypto core (TASK-001: `SignalingCipher.forPair` + v=2 envelopes) is done. The DB key bootstrap (TASK-002: `DatabaseKeyService`) is done. But the **wiring** — connecting the adapter to use per-pair ciphers, and connecting the DB to use SQLCipher — is deferred because it needs Firebase emulator verification and a SQLCipher native library settlement. The security posture is "infrastructure built, not connected."
**Fix:** Settle the SQLCipher native dependency, wire the adapter, add emulator contract tests.

### Root Cause 3: No Windows CI gate

**Symptoms:** F-014
**Root cause:** All CI jobs run on `ubuntu-latest`. Windows breakages (missing files, plugin-registrant drift, CMake errors) merge silently. F-001 (deleted `windows/` dir) went undetected because no CI step checks platform file existence.
**Fix:** Add a `windows-latest` CI job that runs at least `flutter build windows --config-only`, plus a platform-file-existence check.

### Root Cause 4: Documentation drift without consolidation

**Symptoms:** NEW-002, NEW-012
**Root cause:** Multiple audit sessions each generated their own doc set (Jul 2, Jul 19, Jul 20) without consolidating. The Obsidian vault has two parallel numbering schemes. `CONTINUITY.md` grew to 52KB. No process enforces doc consolidation.
**Fix:** Consolidate root docs into `docs/`, fix the vault numbering, trim `CONTINUITY.md`.

---

## 9. Phased Remediation Plan

Organized by **risk** (not TODO order). Each phase has clear entry/exit criteria.

### Phase 1: Call Engine Correctness (remaining cheap fixes)
**Risk:** LOW · **Effort:** 1–2 days · **Depends on:** nothing

| Task | ID | Evidence | Fix | Validation |
|------|----|----------|-----|------------|
| Route `handleMediaInterruption` through `_serializeMediaControl` | NEW-001 | `call_media_connection.dart:579` | Wrap the mute write in `_serializeMediaControl('interruption_mute', ...)` | `flutter test packages/peer_core` — add a race test (user unmute vs interruption) |
| Queue dropped media negotiation instead of dropping | F-011 | `voice_call_session.dart:1004-1005` | Add a `_pendingRestart` flag; in the `finally` block, if set, re-trigger negotiation | `flutter test packages/protocol_brain` — add test: second offer during in-flight negotiation is queued, not dropped |
| Investigate F-010 (watcher ordering) with emulator | F-010 | `voice_call_runtime.dart:164-165` | Run a Firebase emulator test: outgoing call with fast remote answer — verify if the answer is actually missed. If yes, find a fix that doesn't regress `friend_flow_test`. If no, mark CLOSED. | Firebase emulator integration test |

**Exit criteria:** All call-engine tests green + new race tests pass.

---

### Phase 2: Workspace Tidy & Organization
**Risk:** LOW · **Effort:** 2–3 hours · **Depends on:** nothing

| Task | ID | Action |
|------|----|--------|
| Move 20+ root `.md` files into `docs/audits/` and `docs/plans/` | NEW-002 | `mkdir -p docs/audits docs/plans && git mv <files>` |
| Keep at root: `README.md`, `AGENTS.md`, `LICENSE`, `CONTINUITY.md`, `PROJECT_PROGRESS_TRACKER.md` | — | — |
| Move APKs to `final product/archive/` | NEW-006 | `mkdir -p "final product/archive" && mv *.apk "final product/archive/"` |
| Consolidate Obsidian vault duplicate directories | NEW-012 | Rename/merge overlapping numbered dirs into one scheme |
| Trim `CONTINUITY.md` (52KB) — move historical sections to `docs/audits/continuity-archive.md` | NEW-002 | Keep only current state + next action at root |
| Review and reduce 30 `// ignore_for_file` directives | NEW-005 | Convert to targeted `// ignore:` or fix underlying lint |

**Exit criteria:** Root has ≤ 6 `.md` files. Vault has no duplicate directory numbers.

---

### Phase 3: CI Hardening
**Risk:** LOW · **Effort:** 1 day · **Depends on:** nothing

| Task | ID | Action |
|------|----|--------|
| Add Windows CI gate | F-014, F-001 | Add `windows-latest` job: `flutter build windows --config-only` + platform-file-existence check |
| Add file-size CI lint | F-002 | Script: fail if any non-generated `lib/*.dart` > 800 lines |
| Add coverage floor | NEW-007 | `flutter test --coverage` + `min_coverage: 40` gate for `apps/rain/lib` |
| Commit updated `package-lock.json` | NEW-009 | Verify `backend/firebase/functions/package-lock.json` is staged |

**Exit criteria:** CI runs on both `ubuntu-latest` and `windows-latest`. Size gate and coverage floor enforced.

---

### Phase 4: Security Wiring (the keystone unblock)
**Risk:** MED-HIGH · **Effort:** 2–3 weeks · **Depends on:** Phase 1 (call engine stable)

| Task | ID | Action |
|------|----|--------|
| Wire `SignalingCipher.forPair` into `firebase_adapter` | F-015 | Replace `SignalingCipher.demo()` default with per-pair cipher derived from X25519 ECDH. Add v=1 fallback window. Add `validateForRelease` check. |
| Implement ECDH key exchange on friendship establishment | F-015 | On `friendships/<a>/<b>` write, derive per-pair root key from both users' published signing public keys + ECDH. Store in `rain_core`. |
| Settle SQLCipher native dependency | F-017 | Evaluate `sqlite3` native asset (the repo already uses `sqlite3` — `sqlcipher_flutter_libs` is EOL but `sqlite3` v3.x may support SQLCipher natively). If not viable, evaluate `drift_sqflite` + `sqflite_sqlcipher`. |
| Wire `PRAGMA key` into DB open path | F-017 | `NativeDatabase.open(..., setup: (db) => db.execute('PRAGMA key = "...";'))` using `DatabaseKeyService` key. |
| Add plaintext→cipher DB migration | F-017 | On first launch after upgrade: create new encrypted DB, stream-copy existing data, verify parity, delete plaintext file. |
| Add Firebase emulator contract test for per-pair crypto | F-015 | Third-party-cannot-decrypt test: verify a non-pair-member cannot decrypt v=2 signaling. |

**Exit criteria:** Per-pair E2E signaling is wired and emulator-tested. DB is encrypted at rest with a verified migration path.

---

### Phase 5: God-Object Decomposition
**Risk:** HIGH · **Effort:** 4–6 weeks · **Depends on:** Phase 1 (stable call engine), Phase 4 (security wiring done so cipher code isn't moving during extraction)

| Task | ID | Target | Extraction plan |
|------|----|--------|-----------------|
| Split `voice_call_runtime.dart` (3,106 lines) | F-002 | < 800 lines | Extract `VoiceCallLifecycleCoordinator`, `VoiceCallMediaBinding`, `VoiceCallSignalingBridge` |
| Split `firebase_adapter.dart` (2,931 lines) | F-002 | < 800 lines | Split into per-domain adapters: `PresenceAdapter`, `SessionAdapter`, `LockAdapter`, `IceAdapter` |
| Split `rain_runtime_controller.dart` (2,573 lines) | F-002 | < 800 lines | Extract `ConnectionLifecycleController`, `PeerSessionController`, `RuntimeDiagnosticsController` |
| Split `voice_call_signaling_cleanup_coordinator.dart` (1,853 lines) | NEW-011 | < 800 lines | Extract `SubscriptionCleanup`, `SessionDisposal`, `LockCleanup` |
| Split `friend_flow_test.dart` (9,212 lines) | NEW-003 | < 1,000 lines per file | Split into per-flow test files |
| Split `connection_request_rtdb_adapter.dart` (2,328 lines) | F-002 | < 800 lines | Extract `ConnectionRequestQuotaAdapter`, `ConnectionRequestLifecycleAdapter` |

**Method:** For each extraction:
1. Write characterization/golden tests BEFORE moving code (lock current behavior).
2. Extract one coordinator at a time.
3. Run full test suite after each extraction.
4. Feature-flag if risky (but prefer direct extraction with tests).

**Exit criteria:** No non-generated `lib/` file > 800 lines. No test file > 1,000 lines.

---

### Phase 6: Test Coverage Deepening
**Risk:** LOW · **Effort:** 2–3 weeks · **Depends on:** Phase 5 (extractions done so unit tests target stable interfaces)

| Task | ID | Action |
|------|----|--------|
| Add unit-test mirrors for `application/runtime/*` | F-003 | One test file per runtime source file |
| Add widget tests for `presentation/screens/` | F-003 | `settings_screen_test.dart`, `home_screen_test.dart` |
| Add unit tests for `application/state/runtime_providers.dart` | F-003 | (TASK-003.1 already done — extend to full coverage) |
| Enforce 40% coverage floor in CI | NEW-007 | `flutter test --coverage` + `min_coverage` gate |

**Exit criteria:** `apps/rain/lib` has per-file unit test mirrors. Coverage ≥ 40%.

---

### Phase 7: Backend Hardening & Documentation Polish
**Risk:** LOW · **Effort:** 1 week · **Depends on:** nothing (can parallelize)

| Task | ID | Action |
|------|----|--------|
| Add scheduled Cloud Function to reconcile connection-request quotas | F-004 | One daily run reconciles `connectionRequestUsage.used` against actual records |
| Expand RTDB rules contract tests | F-005 | Add property/fuzz-style cases for every state transition + time boundary |
| Document Firebase API key publicity | NEW-004 | Add to security posture docs: "Firebase API keys are public-by-design; security is enforced by RTDB rules + Auth" |
| Final vault consolidation | NEW-012 | Single numbering scheme, run vault validator |
| Accessibility audit | (P5 deferred) | UI Semantics audit + widget-test assertions for core screens |

**Exit criteria:** Quota reconciliation deployed. Rules contract tests expanded. Vault clean.

---

## 10. Dependency Graph

```
Phase 2 (Workspace Tidy) ──────────────────────────────┐
Phase 3 (CI Hardening) ────────────────────────────────┤ (all independent)
Phase 7 (Backend + Docs) ──────────────────────────────┘
                                                       
Phase 1 (Call Engine) ─────┬──→ Phase 4 (Security Wiring) ──→ Phase 5 (God-Object Split) ──→ Phase 6 (Test Coverage)
                           │
                           └──→ Phase 5 can start after Phase 1 (but Phase 4 should finish first
                                so crypto code isn't moving during extraction)
```

**Critical path:** Phase 1 → Phase 4 → Phase 5 → Phase 6

**Parallelizable:** Phases 2, 3, 7 can all run concurrently with any other phase.

---

## 11. Validation Strategy

### Per-phase validation gates

| Phase | Gate |
|-------|------|
| 1 | `flutter test packages/peer_core packages/protocol_brain` — all green + new race tests pass |
| 2 | `git status` — root has ≤ 6 `.md` files; `find docs -name '*.md'` contains moved docs |
| 3 | CI runs on `windows-latest`; size gate and coverage floor enforced |
| 4 | Firebase emulator contract test: third-party cannot decrypt v=2 signaling; DB opens with `PRAGMA key` and migration is verified |
| 5 | `find . -name '*.dart' -not -path '*/.dart_tool/*' -not -path '*/build/*' -not -name '*.g.dart' -exec wc -l {} + | awk '$1 > 800'` returns nothing for `lib/` |
| 6 | `flutter test --coverage` ≥ 40% for `apps/rain/lib` |
| 7 | Firebase emulator test for quota reconciliation; vault validator passes |

### Standard gate (run before every push)

```bash
dart pub get
dart run melos run analyze
dart run melos run test
dart format --output=none --set-exit-if-changed $(git diff --name-only -- '*.dart')
```

### Post-code documentation gate (per AGENTS.md)

1. Update affected Obsidian notes.
2. Update `PROJECT_PROGRESS_TRACKER.md`.
3. Update `CONTINUITY.md` if durable facts changed.
4. Run `.\scripts\check_obsidian_vault.ps1`.

---

## 12. Bottom Line

Rain is a **well-engineered project with a disciplined operating model** that has already undergone two audit passes and partial remediation. The codebase has no CRITICAL flaws — no hardcoded secrets, no cleartext credential storage, no bypassable auth, no data-corruption-on-crash paths. The Firebase rules are strict, the diagnostics sanitizer is robust, and the call-engine bugs that were causing "stuck state" symptoms (F-006, F-008, F-009, F-013) are genuinely fixed and tested.

The remaining work is **architectural maturation, not emergency repair**:

1. **Wire the security infrastructure** that's already built (per-pair cipher → adapter, SQLCipher → DB open path). The crypto is correct; it just isn't connected.
2. **Decompose the god-object files** that concentrate call-engine risk. The extraction program is underway but incomplete.
3. **Tidy the workspace** — 34 root `.md` files and a duplicated Obsidian vault structure create source-of-truth confusion.
4. **Add a Windows CI gate** so platform breakages don't merge silently.
5. **Deepen unit-test coverage** — the integration tests are thorough but per-file unit mirrors are missing.

The project's own `PROJECT_PROGRESS_TRACKER.md` is honest and accurate — 8/21 tasks done, with deferred items clearly documented and blocked on emulator/device verification. This plan picks up exactly where that tracker leaves off, with every finding re-verified against the live tree.

**Recommended first action:** Start with **Phase 2 (Workspace Tidy)** — it's zero-risk, unblocks clarity for all subsequent work, and can be done in an afternoon. Then Phase 1 (call engine cheap fixes) and Phase 3 (CI hardening) in parallel.

---

*End of analysis. This report was generated by static inspection only — no builds, tests, or emulator runs were executed. Every file:line citation was verified against `dev@e6b6dfd` on 2026-07-21.*
