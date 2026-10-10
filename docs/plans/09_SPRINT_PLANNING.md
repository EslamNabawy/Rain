# 09 — Sprint Planning

Five sprints converting `02_ENGINEERING_BACKLOG.md` into shippable increments. Each: objectives, tasks, duration, risks, deliverables, Definition of Done.

> Sequencing rule from `01`: **TASK-015 unblocks TASK-001/002**. Do cheap reliability fixes (005/006/007/008/016) before the XL refactor (004).

---

## Sprint 1 — Critical Reliability (1 week)
**Objectives:** Kill the cheap, high-impact call-correctness bugs; establish session-terminal discipline.
**Tasks:**
- TASK-005 — watcher before `startOutgoing()` (XS)
- TASK-006 — remove `failed→idle` (XS)
- TASK-007 — mute lock (S)
- TASK-008 — `beforeOpen` validation (S)
- TASK-016 — session-reuse guard (S)
**Risks:** Low. TASK-006 touches FSM shared with TASK-004 — land before extraction.
**Deliverables:** 5 merged PRs; call teardown/answer tests green.
**DoD:** `dart analyze` + `melos run test` green; integration tests prove fast-answer + no terminal resurrection.

## Sprint 2 — Stability & Hygiene (1 week)
**Objectives:** Close LOW debt; start testability; add monitoring foundation.
**Tasks:**
- TASK-018 — `debugPrint`→sanitizer + doc fix (S)
- TASK-019 — LICENSE (XS)
- TASK-020 — root cleanup (XS)
- TASK-021 — Windows merge-gate (S)
- TASK-017 (start) — RTDB rules template + fuzz harness scaffold (M, partial)
- DEBT-016 (start) — Crashlytics behind sanitizer (M, scaffold)
**Risks:** LOW. Crashlytics adds a dependency — keep behind sanitizer to protect PII.
**Deliverables:** CI gates added; LICENSE present; fuzz harness runs in emulator.
**DoD:** Merge-gate fails on missing Windows file + >0 raw prints; RC privacy verified.

## Sprint 3 — Security Foundation (2 weeks)
**Objectives:** Build the keystore that unblocks real crypto.
**Tasks:**
- TASK-015 — `flutter_secure_storage` + `KeyStoreService` + `IdentityKeyRepository` + `Identity` keypair migration (M)
- TASK-002 — SQLCipher DB open + plaintext→cipher migration (M)
**Risks:** MED. Irreversible migration — copy to new cipher file, delete plaintext only after verified copy. Private key never leaves secure store.
**Deliverables:** Encrypted DB on disk; secure key round-trip on Android+Windows.
**DoD:** `rain_database_test` asserts non-plaintext file + full row copy; keystore round-trip test green.

## Sprint 4 — Real E2E + Architecture (4–6 weeks)
**Objectives:** Per-pair signaling; begin god-object extraction.
**Tasks:**
- TASK-001 — per-pair X25519 + random salt + `v=2` envelope w/ `v=1` fallback (L)
- TASK-003 — app-layer unit tests + split `friend_flow_test.dart` (L, parallel)
- TASK-004 — extract `VoiceCallLifecycleCoordinator` / `MediaBinding` / `SignalingBridge` / `LockCoordinator` (XL, after 006)
**Risks:** HIGH. TASK-001 is breaking (versioned envelopes mitigate). TASK-004 needs golden tests first.
**Deliverables:** Signaling confidentiality is per-pair; `lib/` file count + mirror tests up; no `lib/` file >800 lines.
**DoD:** `signaling_cipher_test` proves per-pair keys differ + random salt; CI line-limit gate active; coverage floor 40%.

## Sprint 5 — Polish & Production Gate (1–2 weeks)
**Objectives:** Close remaining debt; pass Production Readiness (07).
**Tasks:**
- TASK-017 (finish) — fuzz harness 200+ cases (M)
- DEBT-017 — CODEOWNERS + branch protection (S)
- Accessibility pass (a11y) → resolve UNKNOWN in 07
- Documentation sync: correct README privacy caveat (L-5), vault update per AGENTS.md
**Risks:** LOW.
**Deliverables:** Production Readiness 3 FAILs → PASS; a11y PASS/FAIL recorded; vault validator green.
**DoD:** `07_PRODUCTION_READINESS_CHECKLIST.md` shows 0 FAIL; `check_obsidian_vault.ps1` passes.

---

## Sprint Dependency View
```mermaid
flowchart LR
  S1[S1 Reliability<br/>005,006,007,008,016] --> S2[S2 Hygiene<br/>018,019,020,021,017*,016*]
  S2 --> S3[S3 Security Foundation<br/>015,002]
  S3 --> S4[S4 E2E + Arch<br/>001,003,004]
  S4 --> S5[S5 Polish<br/>017,017*,a11y,CODEOWNERS]
```
\* = started in S2, finished in S5.

## Capacity note
Sprint 4 is the long pole (XL + L). If velocity is tight, ship TASK-003 (tests) in S4 and defer TASK-004 extraction to a follow-on "Sprint 6 — Extraction Continuation" rather than rushing it — extraction quality matters more than speed.
