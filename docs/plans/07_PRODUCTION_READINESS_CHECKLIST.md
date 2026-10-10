# 07 — Production Readiness Checklist

Pass/Fail against `dev@6ed4a00`. **FAIL** = must fix before production claim; **PARTIAL** = works but gap; **PASS** = verified this pass.

| Area | Status | Evidence / Note |
|---|---|---|
| **Architecture** | PARTIAL | Clean layer split (app/runtime/brain/peer/core) per `README.md`; but god-objects (DEBT-004) concentrate call logic. |
| **Performance** | PARTIAL | WAL+busy_timeout+foreign_keys set (good). No profiling run; P-1/P-3 inferred. |
| **Security** | **FAIL** | H-1 shared signaling key; H-2 cleartext DB; M-6 constant salt. Core privacy gaps. |
| **Reliability** | PARTIAL | Strong Firebase rules, sanitized diagnostics, mature async. But M-1 watcher ordering can stall calls; M-4 no schema-rollback. |
| **Scalability** | PARTIAL | Drift named indexes present (`rain_database.dart`); no read-replica split (P-3). |
| **Accessibility** | UNKNOWN | No a11y audit performed; widgets lack Semantics noted in AGENTS.md QA rules but not verified. |
| **Testing** | PARTIAL | 1,000+ tests pass (per CONTINUITY); but 0 app-layer mirror tests (DEBT-003); 9k-line suite (DEBT-003). |
| **Documentation** | PARTIAL | Excellent vault + AGENTS.md; but stale "0 print" claim (DEBT-012) + README overstates privacy (L-5). |
| **Monitoring** | **FAIL** | No Crashlytics/Sentry/telemetry (DEBT-016). Blind in production. |
| **Deployment** | PARTIAL | Mature release gates (manual-only, RC evidence, emulator tests); Windows missing from merge-gate (DEBT-015). |
| **Maintainability** | PARTIAL | `dart analyze` clean ✅; god-objects + giant tests hurt it (DEBT-003/004). |
| **Developer Experience** | PARTIAL | Melos + good docs; no CODEOWNERS (DEBT-017); no coverage gate. |
| **Observability** | PARTIAL | Local `CrashDiagnosticsService` + sanitizer strong; no remote aggregation. |
| **Disaster Recovery** | PARTIAL | Firebase RTDB + Functions; DB plaintext→cipher migration needs rollback plan (TASK-002). |
| **Backup Strategy** | PARTIAL | RTDB has cleanup Functions; no documented local-DB backup/export cadence for user data. |

### Verdict gate
- **3 FAIL** (Security ×2, Monitoring ×1) → not production-ready by these criteria.
- Cheapest path to reduce FAILs: TASK-015 → TASK-002 (clears Security-DB FAIL) + add Crashlytics (clears Monitoring FAIL) + TASK-001 (clears Security-E2E FAIL).
- Accessibility UNKNOWN should become a real FAIL-or-PASS after one a11y pass (recommend before store submission).
