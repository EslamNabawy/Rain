# 03 — PHASE 02: Stability & Hygiene

**Master ref:** `01_IMPLEMENTATION_MASTER_PLAN.md` · **Backlog:** `02_ENGINEERING_BACKLOG.md` (TASK-018,019,020,021, TASK-017*, DEBT-016*)
**Goal:** Close LOW debt (logging hygiene, LICENSE, repo cleanup, Windows merge-gate) and **scaffold** the two medium foundations that span later phases: RTDB rules fuzz harness + Crashlytics telemetry.
**Why now:** All independent; cheap; the scaffolds (017*/016*) are *started* here and *finished* in P5 so P3/P5 don't block on setup.
**Estimated effort:** 1 week. **Risk:** LOW.
**Prerequisites:** P1 complete (DoD met).
**Exit criteria:** P2 DoD (§10). **Deliverables:** CI gates added; LICENSE; fuzz scaffold runs; Crashlytics scaffold behind sanitizer.

---

## TASK-018 — Route `debugPrint` via sanitizer + fix stale audit doc

### Overview
- **Objective:** Replace the 27 `debugPrint` calls in `lib/` with `RainDebugLogService`; add a CI grep gate; correct `FLAWS_AND_FIXES_TODO.md` "0 print" claim.
- **Business/Technical value:** Consistent release logging; doc integrity (the old claim is false — 27 exist).
- **Dependencies:** none. **Risk:** LOW (Flutter strips `debugPrint` in release → not a leak; cosmetic/privacy-hygiene).
- **Debt:** DEBT-012.

### Current State
- 27 `debugPrint(` hits in `lib/` (`crash_diagnostics_service.dart:252,298,367`; `sound_effects_service.dart` ×8; `desktop_shell_controller.dart:84,93,100,122`; `main.dart:178`; `home_screen.dart:1750`; `rain_chat_widgets.dart:41`; `sound_event_router.dart:462,466`).
- `RainDebugLogService` + `DiagnosticsSanitizer` already exist (`crash_diagnostics_service.dart`, `diagnostics_sanitizer.dart`).
- `FLAWS_AND_FIXES_TODO.md` line ~130 claims *"No `print`/`debugPrint` left in production code"* — FALSE for current tree.

### Target State
- All 27 routed through `RainDebugLogService.log(...)` (which already sanitizes). CI fails if raw `debugPrint(` count > 0 in `lib/`.

### Implementation Breakdown
**Task 18.1 — Add CI grep gate** (0.5h)
- File: `.github/workflows/ci.yml` (near `Enforce Dart formatting`, `:109`).
- Add step: `run: | grep -rnE "debugPrint\(" apps/rain/lib packages/*/lib && exit 1 || echo "no raw debugPrint"` (fail on match).
- Validation: temporarily add a `debugPrint` → CI red.

**Task 18.2 — Route the 27 calls** (3h)
- Replace each `debugPrint('...')` with `RainDebugLogService.instance.log('...')` (or the existing injected logger in that class).
- Files: the 11 files listed above.
- Validation: `dart analyze`; grep returns 0.

**Task 18.3 — Fix stale doc** (0.5h)
- In `FLAWS_AND_FIXES_TODO.md`, correct the "0 print" claim → "27 routed via sanitizer in <date>".
- Validation: doc consistent with code.

### File-Level Changes
- MODIFY: 11 `lib/` files + `.github/workflows/ci.yml` + `FLAWS_AND_FIXES_TODO.md`.

### Code-Level Changes
- Functions: add `log(...)` calls; no new model. Logging: single sink.

### Testing / Validation
- □ CI gate red on raw print □ grep 0 in lib □ analyze passes □ doc fixed.

### Rollback
Per-file revert; CI step removal.

---

## TASK-019 — Add root LICENSE

### Overview
- **Objective:** Add a license (MIT or Apache-2.0) at repo root; link from README.
- **Value:** Legal distribution clarity (public GitHub repo, badges point to `EslamNabawy/Rain`).
- **Dep:** none. **Risk:** LOW. **Debt:** DEBT-013.

### Current State
- `README.md:364`: *"No root repository license file is currently declared."*

### Target State
- `LICENSE` present; `README.md` links it.

### Breakdown
**Task 19.1 — Choose + add** (0.5h): write `LICENSE` (MIT recommended for a small app). **Task 19.2 — Link** (0.25h): add `[License](LICENSE)` to README.

### Changes
- CREATE `LICENSE`. MODIFY `README.md`.

### Validation
□ `LICENSE` exists □ README link valid.

### Rollback
Delete file; revert README.

---

## TASK-020 — Clean untracked root artifacts

### Overview
- **Objective:** Remove/gitignore `IDEA.md`, `deps.txt` (stray dumps) from repo root.
- **Dep:** none. **Risk:** LOW. **Debt:** DEBT-014.

### Current State
- `git status`: `?? IDEA.md`, `?? deps.txt`, `?? FLAWS_AND_FIXES_TODO.md`.

### Target State
- Root clean of editor/dump artifacts; `.gitignore` covers `IDEA.md`/`deps.txt`. Keep `FLAWS_AND_FIXES_TODO.md` (still useful) or archive to `docs/`.

### Breakdown
**Task 20.1** (0.5h): add to `.gitignore`: `IDEA.md`, `deps.txt`. Move `FLAWS_AND_FIXES_TODO.md` → `docs/audit/` (update any links in `CONTINUITY.md`). **Task 20.2** (0.25h): `git rm --cached` if tracked (they're untracked → just ignore).

### Validation
□ `git status` clean of stray root files.

### Rollback
Revert `.gitignore`; move file back.

---

## TASK-021 — Windows build/config check in merge-gate CI

### Overview
- **Objective:** Add `windows-config-check` + `windows-build --config-only` to `ci.yml` + `main-merge-gate.yml` (currently only `build-artifacts.yml:149` builds Windows).
- **Value:** Windows breakage can't merge silently (residual F-014).
- **Dep:** none. **Risk:** LOW. **Debt:** DEBT-015.

### Current State
- `ci.yml:358` + `main-merge-gate.yml:193`: `flutter build apk --debug` only.
- `build-artifacts.yml:149-243`: `build-windows` on `windows-2022` exists (release path).

### Target State
- Merge-gate fails if `apps/rain/windows/CMakeLists.txt`, `runner/main.cpp`, `flutter/generated_plugin_registrant.cc` missing in PR diff.
- Optional `windows-build` job on `windows-2022` for PRs touching `apps/rain/**` or `packages/**`.

### Breakdown
**Task 21.1 — config-check job** (1.5h): add job reusing `build-artifacts.yml` Windows job pattern; assert files exist.
**Task 21.2 — build job** (1.5h): add `windows-build --config-only` on `windows-2022`, `if:` guard on touched paths.
**Task 21.3 — wire into gates** (0.5h): include in `ci.yml` + `main-merge-gate.yml`.

### Validation
□ PR deleting a Windows file fails merge-gate □ Windows config builds on touched PR.

### Rollback
Remove jobs from workflows.

---

## TASK-017* — RTDB rules fuzz/property harness (SCAFFOLD in P2, FINISH P5)

### Overview
- **Objective (scaffold):** Stand up a property/fuzz harness that generates random legal/illegal state transitions + time-boundary probes against `database.rules.json` in the Firebase emulator; assert allow/deny vs a spec table. Also create `database.rules.template.json` (commented) + a build step that strips comments.
- **Value:** Closes the rules-correctness blind spot (DEBT-009). Started now so P5 finishes without setup churn.
- **Dep:** none (needs emulator). **Risk:** LOW. **Debt:** DEBT-009.

### Current State
- `database.rules.json` ~776 lines dense booleans. Contract tests enumerate cases only.
- `scripts/ci_run_firebase_emulators.ps1` exists (per CONTINUITY) — reuse it.

### Target State (end of P5)
- `database.rules.template.json` (commented) → generated `database.rules.json` (byte-identical today).
- `apps/rain/test/*_rules_fuzz_test.dart` generates ≥200 transition cases.

### Breakdown (P2 scaffold only)
**Task 17.1 — Commented template** (2h): copy current rules into `database.rules.template.json` with `// section` headers; add `scripts/build_rules.ps1` that strips `//` lines → `database.rules.json`.
**Task 17.2 — Spec table + harness skeleton** (1h): create `apps/rain/test/rules_fuzz_spec.dart` (transition spec) + `rules_fuzz_test.dart` that runs N random cases against emulator, asserts vs spec. Leave at <20 cases initially (finish in P5).

### Validation
□ `build_rules.ps1` output byte-compares to current `database.rules.json` □ skeleton test runs in emulator.

### Rollback
Remove template + script; keep hand-maintained `database.rules.json`.

---

## DEBT-016* — Crashlytics behind sanitizer (SCAFFOLD in P2)

### Overview
- **Objective (scaffold):** Add `firebase_crashlytics` and route **only sanitized** crash records through it. Clears the Monitoring FAIL in `07_PRODUCTION_READINESS_CHECKLIST.md`.
- **Value:** Field diagnosability without PII leak.
- **Dep:** none. **Risk:** LOW (behind sanitizer). **Debt:** DEBT-016.

### Current State
- No `firebase_crashlytics`/`sentry` in `apps/rain/pubspec.yaml`.
- `DiagnosticsSanitizer` already redacts email/tokens/paths/SDP.

### Target State (end of P5)
- Crashlytics initialized; `CrashDiagnosticsService` sends sanitized payloads only.

### Breakdown (P2 scaffold only)
**Task 16a.1 — Add dep + init** (1.5h): add `firebase_crashlytics` to `apps/rain/pubspec.yaml`; init in `main.dart` after Firebase core. Gate behind a `RAIN_ENABLE_CRASHLYTICS` dart-define (off in demo).
**Task 16a.2 — Route sanitized records** (1.5h): in `crash_diagnostics_service.dart`, on fatal record, send `sanitizer.sanitize(record)` to Crashlytics `recordError` — NEVER raw.

### Validation
□ Crashlytics off in demo build □ sanitized payloads only □ no PII in reported string.

### Rollback
Remove dep + init; revert service.

---

## 10. Phase 2 Exit / DoD
- [ ] TASK-018/019/020/021 merged; CI fails on raw print + missing Windows file.
- [ ] 017* scaffold: `build_rules.ps1` byte-matches; fuzz skeleton runs in emulator.
- [ ] DEBT-016* scaffold: Crashlytics inits behind define; sanitized-only routing.
- [ ] `dart run melos run analyze` + `test` green.
- [ ] CONTINUITY + vault (security hardening note) updated; `check_obsidian_vault.ps1` green.

## 11. Phase Summary
- **Completed:** LOW debt closed; two medium scaffolds stood up (rules fuzz, telemetry) for later finish.
- **Remaining:** 017*/016* finish in P5; TASK-015 (P3) still blocks crypto.
- **Known issues:** Crashlytics adds a dependency — kept behind sanitizer + demo-off define to protect PII.
- **Metrics:** CI raw-print count (0); Windows merge-gate pass/fail; fuzz case count (grow in P5).
- **Go/No-Go:** **GO** if DoD met. No-Go if Windows job is flaky on `windows-2022`.

## 12. Decisions Log (P2)
- LICENSE = MIT (small app, permissive).
- Crashlytics gated off in demo builds (`RAIN_ENABLE_CRASHLYTICS`) — privacy.
- Rules template is additive now (byte-identical output) to avoid a rules redeploy risk mid-project.
