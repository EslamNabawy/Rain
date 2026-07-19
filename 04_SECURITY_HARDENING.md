# 04 — Security Hardening Plan

Ranked checklist. Urgency ranks: **P0 (now)** / **P1 (this quarter)** / **P2 (hygiene)**. Source: `PROJECT_DEEP_ANALYSIS.md` H-1, H-2, M-6 + discovered TASK-015/016/017.

---

## □ Secrets Management  — **P0**
- [ ] **TASK-001/015:** No `flutter_secure_storage` in any `pubspec.yaml`; signaling root key is a `dart-define` (`RAIN_SIGNALING_ENCRYPTION_KEY`, `app_environment.dart:138,241`). Add OS-backed store; never bake the production signaling key or the future DB/identity keys into the binary.
- [ ] Confirm `backend/firebase/functions/.env` is gitignored (it is — `.gitignore:12-13`) and **no service-account JSON is tracked** (`git ls-files | grep service-account` returned clean — verified).
- [ ] Rotate any signaling key that may have been shared in a public demo build (demo key is correctly rejected in prod via `validateForRelease`, `app_environment.dart:241-246` — keep that gate).

## □ Encryption  — **P0**
- [ ] **TASK-002 (H-2):** Local Drift DB is cleartext (`rain_database.dart:303-316`, no `PRAGMA key`). Add SQLCipher.
- [ ] **TASK-001 (H-1):** Signaling uses one app-wide key + constant salt `rain-signaling-v1` (`signaling_cipher.dart:22-40,164`). Move to per-pair X25519 + random per-envelope salt.
- [ ] **TASK-001 (M-6):** Randomize HKDF salt per envelope (transmit alongside).

## □ Secure Storage  — **P0**
- [ ] **TASK-015:** Hardware-backed keystore (Android Keystore / Windows Credential Store via `flutter_secure_storage`) for: identity private key, SQLCipher DB key, per-pair root keys.

## □ Authentication  — **P1**
- [ ] `resolveAuthUsername` (`connectionRequestGuardrails.js:150`) resolves `users` by `uid` with a `limitToFirst(2)` and requires exactly 1 match — good. Add a test for the `matches.length !== 1` (backendUnavailable) branch (currently only happy-path covered).
- [ ] Account-deletion tombstone path (`users/{username}` legacy row claimable only by matching auth email+uid) — verified present in rules; add a contract test for the "uid exists + mismatch email" denial.

## □ Authorization  — **P1**
- [ ] **TASK-017:** RTDB rules correctness depends on enumerated contract tests only. Add property/fuzz harness. (65 `auth.uid` checks already present — strong.)
- [ ] Connection-request quota is server-enforced via `reserveSenderQuota` transaction (`connectionRequests.js:194,1113,1287`) — **verified correct**; add a single daily reconciliation Function for defense-in-depth drift.

## □ Input Validation  — **P1**
- [ ] Backend already validates `USERNAME_PATTERN`, `REQUEST_ID_PATTERN`, `requireObjectData` (`connectionRequestGuardrails.js:3-4,118`). ✅ Strong.
- [ ] Dart side: validate `Identity.username` shape at the repository boundary (`identity.dart:39`); reject empty/oversized displayName before Drift write.

## □ Output Encoding  — **P2**
- [ ] Diagnostics sanitizer (`crash_diagnostics_service.dart`, `diagnostics_sanitizer.dart`) redacts email/tokens/paths/SDP — ✅ strong. Ensure crash export never includes `Identity.username`+message-content together in one redacted blob (verify in `crash_diagnostics_service_test.dart`).

## □ Logging and Auditing  — **P2**
- [ ] **TASK-018 (M-7, downgraded):** 27 `debugPrint` in `lib/` — harmless in release (Flutter strips them) but should route through `RainDebugLogService` for consistency + doc integrity. Add CI grep gate.
- [ ] No remote crash/audit telemetry exists (`firebase_crashlytics`/`sentry` absent). For production, add Crashlytics with the **same sanitizer** upstream (privacy-critical).

## □ Dependency Updates  — **P2**
- [ ] Functions `npm audit` cleared (commit `6ed4a00`). ✅
- [ ] Dart deps current (firebase_auth 6.5.1, drift 2.33.0, flutter_webrtc 1.4.1). ✅ Add Dependabot/Renovate for both `pubspec` + `functions/package.json`.

## □ Security Headers  — **P2 (N/A for desktop/Android app)**
- [ ] Not applicable (no web server). Skip; document why in vault.

---

## Urgency ranking (top→bottom)
1. **P0 — Encryption: TASK-002** (cleartext DB) — device-theft exposure.
2. **P0 — Secrets/Storage: TASK-015** — unblocks TASK-001/002 safely.
3. **P0 — Encryption: TASK-001** (shared-key E2E) — core privacy promise.
4. **P1 — Authorization: TASK-017** (rules fuzz).
5. **P1 — Auth: tombstone + uid-mismatch tests.**
6. **P2 — Logging: TASK-018**, Dependency bot, Crashlytics-with-sanitizer.

> Trade-off note: TASK-001/002 are P0 *privacy* risks but require TASK-015 first; the key store is the true P0 sequencing gate. Until TASK-015 lands, document H-1/H-2 honestly as "accepted, not mitigated" (ADR-010 Option A) rather than claim mitigation.
