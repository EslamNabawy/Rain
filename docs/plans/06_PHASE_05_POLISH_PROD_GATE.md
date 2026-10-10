# 06 — PHASE 05: Polish & Production Gate

**Master ref:** `01_IMPLEMENTATION_MASTER_PLAN.md` · **Backlog:** `02_ENGINEERING_BACKLOG.md` (TASK-017 finish, DEBT-017, a11y, README/ADR/docs)
**Goal:** Finish the two scaffolds from P2 (RTDB rules fuzz harness, Crashlytics), add CODEOWNERS + branch protection, run an accessibility pass, and close documentation so `07_PRODUCTION_READINESS_CHECKLIST.md` shows **0 FAIL**.
**Why now:** All hard work (P1–P4) is done; this is the gate. Accessibility is currently UNKNOWN in the readiness checklist — must resolve before store.
**Estimated effort:** 1–2 weeks. **Risk:** LOW.
**Prerequisites:** P1–P4 complete (DoD met).
**Exit criteria:** P5 DoD (§10) → Production Readiness 0 FAIL.

---

## TASK-017 (FINISH) — RTDB Rules Fuzz/Property Harness

### Overview
- **Objective:** Finish the P2 scaffold: `database.rules.template.json` (commented) → generated `database.rules.json` (byte-identical); `rules_fuzz_test.dart` generates ≥200 random transition + time-boundary cases against the emulator, asserting allow/deny vs a spec table.
- **Value:** Closes the rules-correctness blind spot (DEBT-009). Removes DEBT-009.
- **Dep:** P2 scaffold (017*). **Risk:** LOW.

### Current State
- `database.rules.json` ~776 lines dense booleans. Contract tests enumerate cases only.
- P2 created `database.rules.template.json` + `scripts/build_rules.ps1` (byte-matches) + `rules_fuzz_spec.dart` + skeleton `rules_fuzz_test.dart`.

### Target State
- Generated `database.rules.json` byte-identical to current (no behavior change).
- ≥200 generated cases (legal/illegal transitions × time boundaries) pass in emulator.

### Breakdown
**Task 17f.1 — Expand spec table** (2d): enumerate every `($from,$to)` transition per rules section (voiceCalls, activeVoicePairs, activeVoiceUsers, connectionRequests, connectionRequestUsage, rooms, presence, users) + time-boundary probes (`now` vs `expiresAt`).
**Task 17f.2 — Fuzz generator** (2d): `rules_fuzz_test.dart` builds random valid/invalid payloads + random auth (Alice/Bob/ stranger) + random `now`; asserts RTDB emulator allow/deny matches spec. Target ≥200 cases, seeded for reproducibility.
**Task 17f.3 — CI wiring** (0.5d): add `rules_fuzz` to `ci_run_firebase_emulators.ps1` + `ci.yml` emulator job.

### Validation
□ `build_rules.ps1` output byte-matches current `database.rules.json` □ ≥200 fuzz cases pass □ emulator job green.

### Rollback
Remove fuzz job; keep hand-maintained `database.rules.json`.

---

## DEBT-016 (FINISH) — Crashlytics Behind Sanitizer

### Overview
- **Objective:** Finish P2 scaffold — route **only sanitized** crash records to Crashlytics; confirm demo build keeps it off.
- **Value:** Clears Monitoring FAIL (`07_PRODUCTION_READINESS_CHECKLIST.md`).
- **Dep:** P2 scaffold (016*). **Risk:** LOW.

### Current State
- P2 added `firebase_crashlytics` dep + init gated by `RAIN_ENABLE_CRASHLYTICS` (off in demo). `CrashDiagnosticsService` not yet routing.

### Target State
- On fatal record, `crash_diagnostics_service.dart` sends `diagnosticsSanitizer.sanitize(record)` to `FirebaseCrashlytics.instance.recordError` — NEVER raw.
- Demo build: define off → no Crashlytics init, no network egress.

### Breakdown
**Task 16f.1 — Route sanitized** (1d): in `crash_diagnostics_service.dart`, on fatal, call sanitizer then `recordError`. Assert in `crash_diagnostics_service_test.dart` that the payload passed to a fake Crashlytics contains NO raw email/token/path.
**Task 16f.2 — Demo-off proof** (0.5d): build with `RAIN_ENABLE_CRASHLYTICS=false`; assert no Crashlytics network call (or init guarded).

### Validation
□ Sanitized-only payloads (test) □ Demo off → no egress □ Analyze+test green.

### Rollback
Revert service + dep.

---

## DEBT-017 — CODEOWNERS + Branch Protection

### Overview
- **Objective:** Add `CODEOWNERS` covering `apps/rain/lib/application/runtime/**`, `packages/protocol_brain/**`, `backend/firebase/**`; require PR review on `dev`/`main` (branch protection in repo settings — manual, documented).
- **Value:** Protects call-runtime from unreviewed merge (DEBT-017).
- **Dep:** none. **Risk:** LOW.

### Current State
- No `CODEOWNERS` (confirmed). Branch protection status unknown (repo setting).

### Target State
- `CODEOWNERS` present; repo settings: `dev`/`main` require ≥1 review + `ci.yml` + `main-merge-gate.yml` green.

### Breakdown
**Task 17c.1 — CODEOWNERS** (0.5d): create at repo root with globs above.
**Task 17c.2 — Protection doc** (0.5d): note in `AGENTS.md`/vault the required manual branch-protection settings (GitHub UI step — can't be done via file alone).

### Validation
□ `CODEOWNERS` present □ review requirement documented.

### Rollback
Delete `CODEOWNERS`.

---

## Accessibility Pass (resolves UNKNOWN in readiness)

### Overview
- **Objective:** Run an a11y audit of core screens (`home_screen.dart`, `chat_panel.dart`, `settings_screen.dart`, `rain_call_overlay.dart`) — Semantics labels, focus order, contrast, touch targets.
- **Value:** Resolves the UNKNOWN Accessibility cell in `07_PRODUCTION_READINESS_CHECKLIST.md`; needed before store.
- **Dep:** none. **Risk:** LOW.

### Current State
- `AGENTS.md` QA rules require `Semantics` for automation-visible widgets; a11y not yet verified by audit.

### Target State
- Every interactive widget has `Semantics` (label/action); focus traversable; min 48×48 touch targets; contrast ≥4.5:1 on primary text.

### Breakdown
**Task a11y.1 — Audit** (2d): use Flutter `Semantics` debugger + manual pass; log gaps in vault `09-Testing/Accessibility`.
**Task a11y.2 — Fixes** (3d): add `Semantics` to missing widgets; fix focus traps; verify with `flutter test` widget semantics assertions.

### Validation
□ Core screens Semantics-complete □ widget test asserts labels □ readiness Accessibility = PASS/FAIL recorded.

### Rollback
Per-widget revert.

---

## Documentation Closure

### Overview
- README privacy caveat (L-5): state honestly that signaling is per-pair E2E (post TASK-001) + DB encrypted (post TASK-002); remove the overstated "encrypted before storage = private" phrasing.
- ADR-010: mark Option B (encryption) DONE.
- `CONTINUITY.md`: append P1–P5 completion + validation evidence.
- Vault: close DEBT-001/002/003/004/005/006/007/008/009/010/011/012/013/014/015/016/017; update risk register (crypto/migration risks added in P3/P4); update architecture notes (R-1..R-6 delivered).
- Run `.\scripts\check_obsidian_vault.ps1`.

---

## 10. Phase 5 Exit / DoD
- [ ] TASK-017 finished: `build_rules.ps1` byte-matches; ≥200 fuzz cases pass; CI emulator job green.
- [ ] DEBT-016 finished: sanitized-only Crashlytics; demo off proven.
- [ ] DEBT-017: `CODEOWNERS` + protection documented.
- [ ] A11y: core screens Semantics-complete; readiness Accessibility ≠ UNKNOWN.
- [ ] Docs: README/ADR/CONTINUITY/vault updated; `check_obsidian_vault.ps1` green.
- [ ] `07_PRODUCTION_READINESS_CHECKLIST.md` shows **0 FAIL**.
- [ ] `dart run melos run analyze` + `test` green.

## 11. Phase Summary
- **Completed:** Production gate cleared. All 17 debt items closed or documented.
- **Remaining:** none blocking; future = monitoring tuning, group calls (out of scope per README).
- **Known issues:** A11y findings may surface widget changes — keep small.
- **Metrics:** Production Readiness FAIL count (target 0); fuzz case count (≥200); a11y Semantics coverage (100% core screens).
- **Go/No-Go:** **GO** if DoD met + readiness 0 FAIL. **No-Go** if a11y reveals a blocking defect or vault validator red.

## 12. Decisions Log (P5)
- Fuzz harness seeded (reproducible) — not random-per-run.
- Crashlytics strictly sanitized — privacy non-negotiable.
- A11y fixes kept minimal to avoid scope creep.
