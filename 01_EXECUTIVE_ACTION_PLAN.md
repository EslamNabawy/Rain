# 01 — Executive Action Plan

**Source of truth:** `PROJECT_DEEP_ANALYSIS.md` (generated 2026-07-19, branch `dev@6ed4a00`).
**Scope:** Second-pass engineering review. Re-evaluate every reported issue, drop false positives, merge duplicates, surface cross-component interaction risks, and produce an actionable, file-level backlog.
**Method caveat:** Static + targeted-source review only. `dart analyze` was the only command executed (passed). No `flutter test` / emulator runs were performed in either pass. Confidence levels are stated per issue.

---

## 1. Source-Truth Re-evaluation Summary

The first-pass report contained **1 CRITICAL-tier (none), 4 HIGH, 8 MEDIUM, 5 LOW** items. Second-pass result:

| Original | Verdict | Action |
|---|---|---|
| H-1 signaling shared key | **KEEP (HIGH)** | Becomes TASK-001 |
| H-2 cleartext DB | **KEEP (HIGH)** | Becomes TASK-002 |
| H-3 no app-layer unit tests | **KEEP (HIGH)** | Becomes TASK-003 |
| H-4 god-object files | **KEEP (HIGH)** | Becomes TASK-004 |
| M-1 watcher ordering | **KEEP (MED)** | Becomes TASK-005 |
| M-2 `failed→idle` | **KEEP (MED)** | Becomes TASK-006 |
| M-3 mute race | **KEEP (MED)** | Becomes TASK-007 |
| M-4 no `beforeOpen` | **KEEP (MED)** | Becomes TASK-008 |
| M-5 RTDB rules complexity | **MERGED → TASK-017** (doc debt) | Lowered to debt |
| M-6 constant HKDF salt | **MERGED INTO TASK-001** (same root cause: key model) | No separate task |
| M-7 27 `debugPrint` | **DOWNGRADED → INFO** | False-positive-adjacent: `debugPrint` is a **release no-op** in Flutter (stripped in `--release`). Not a leak. → TASK-018 cleanup only |
| M-8 quota server-enforced | **CLOSED as false-positive-after-rerank** | Prior audit already corrected; current code is correct. No task. |
| L-1 no LICENSE | **KEEP (LOW)** | TASK-019 |
| L-2 untracked root junk | **KEEP (LOW)** | TASK-020 |
| L-3 Windows not in merge-gate | **KEEP (LOW)** | TASK-021 |
| L-4 9,212-line test | **MERGED INTO TASK-003** | |
| L-5 README overstates privacy | **MERGED INTO TASK-001** docs | |

**Net unique tasks: 21** (TASK-001…TASK-021), of which 1 is a discovered interaction risk (TASK-015).

---

## 2. False Positives Removed

1. **M-8 quota client-enforced** — Already corrected in first pass; current `connectionRequests.js` enforces server-side via `reserveSenderQuota` RTDB transaction + injectable dependency. No action.
2. **M-7 as a security/leak finding** — `debugPrint` does nothing in Flutter release builds. Downgraded from MEDIUM to INFO/cleanup. Not a confidentiality risk.
3. **"0 print in production" contradiction** — Real *documentation* error in the old `FLAWS_AND_FIXES_TODO.md`, but it is a doc defect, not a code defect. Captured as TASK-018 (route-through-sanitizer + doc fix) at LOW.

---

## 3. Discovered Interaction Risks (not in first pass)

- **TASK-015 (HIGH, discovered): Key-management vacuum blocks BOTH H-1 and H-2.** There is **no `flutter_secure_storage` in any `pubspec.yaml`** and **`Identity` carries only `username`/`displayName`/`gender`** (`packages/rain_core/lib/identity/identity.dart:15-18`). Per-pair E2E (H-1) and SQLCipher DB key (H-2) both require a hardware-backed secret store + an identity-keypair column. Neither exists. H-1 and H-2 are therefore *blocked* until TASK-015 lands. This cross-component dependency was not explicit in the first pass.
- **TASK-016 (MED, discovered): `failed→idle` + session-replacement interaction.** `voice_call_session.dart:1134` allows `failed→idle`, and `ending→idle`, `incomingRinging→idle`. If a caller reuses a `VoiceCallSession` instance after `failed` (instead of constructing a new one), media-disposed state can be re-entered. Tightly coupled to H-4 extraction — fix together.
- **TASK-017 (LOW, discovered): dense RTDB rules × no fuzz coverage.** Rules are ~776 lines of single-expression boolean logic (`database.rules.json`). The contract tests cover enumerated transitions only. A property/fuzz harness is missing; this is a *testing-architecture* gap, not just a doc gap.

---

## 4. Top-5 Moves (impact ÷ effort)

1. **TASK-005** (M-1 watcher ordering) — 2-line move, kills missed-answer calls. Do first.
2. **TASK-015** (key store + identity keypair) — unblocks H-1/H-2; foundation, not a feature.
3. **TASK-006** (remove `failed→idle`) — 1-line deletion + test; removes half-dead resurrection.
4. **TASK-007** (mute lock) — small serialization; removes mute/interrupt divergence.
5. **TASK-004** (god-object split) — largest effort but de-risks the entire call surface.

Full Top-20 by impact-to-effort is in `10_FINAL_VERDICT.md`.

---

## 5. Recommendation

Do **not** start H-1/H-2 implementation until TASK-015 (key store + identity keypair) is merged — otherwise the crypto work has nowhere safe to store keys. Sequence: **TASK-005 → TASK-015 → TASK-001/002 → TASK-006/007/008 → TASK-003/004 → cleanup/LOW.**

Files the leadership should expect to touch: `packages/rain_core/lib/identity/identity.dart`, `packages/rain_core/lib/database/rain_database.dart`, `packages/protocol_brain/lib/adapters/signaling_cipher.dart`, `packages/protocol_brain/lib/src/voice_call_session.dart`, `apps/rain/lib/application/runtime/voice_call_runtime.dart`, `apps/rain/pubspec.yaml`.

*This plan is the single source of truth for the 9 companion files (02–10).*
