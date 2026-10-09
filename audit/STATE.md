# Audit State

## Done
T0.1 cd7d51b branch audit/rain-hardening created, WIP patch preserved
T1.1 5ac327b findings A (6 GIT findings)
T1.2 59a5c83 findings B (7 ARCH findings)

T1.3 a36e2e1 findings C (6 SIG findings)
T1.4 97b3597 findings D (4 RTC findings)
T1.5 83a76b5 findings E (7 SEC findings)
T1.6 2751bf1 findings F (5 APP findings)
T1.7 0f4ea59 findings G (4 DB findings)
T1.8 f5129ea findings H (4 BE findings)
T1.9 bddcc04 findings I (4 QUAL findings)
T1.10 212d609 findings J (5 TEST findings)
T1.11 f93c613 findings K (7 CI findings)
T1.12 ccff652 findings L (6 DOC findings) + severity table; 65 findings total
T2.1 3e5dc01 8 refactor targets
T2.2 fdffe84 plan: 23 phase-4 cards, 9 owner actions
T2.3 55713e2 vault spec: R-023..R-031, BLK-011..013, TD-023..028, ADR-011/012
T3.1 b466768 firebase_adapter.dart restored to HEAD (WIP in audit/wip patch); analyze clean, format clean, protocol_brain 276 pass
T3.2 0fda669 7 registers dated 2026-10-10; vault validator passes
T3.3 30992ec ci.yml PR filter now main+dev
T3.4 4943068 audit:moderate now 0 vulnerabilities (lockfile only); functions tests 37 pass
T3.5 7146e85 green baseline: analyze/format/tests/functions/vault pass
T4.02 4f28f0a key publish is best-effort; analyze clean; auth_identity tests pass
T4.04 18d275e pure cleanup planner + liveCallId guard; protocol_brain 285 pass; apps/rain analyze clean
## Blocked
T4.19 BLOCKED (SEC-006): depends on T4.01 (rules changes need RULES_TEST).
T4.03 BLOCKED (SEC-001): depends on T4.01 (rules changes need RULES_TEST).
T4.01 BLOCKED (BE-001): RULES_TEST cannot run on this machine. `npx --yes firebase-tools@13 emulators:exec --only database "node -e 1"` (run in backend/firebase) fails with: "Error: Could not spawn `java -version`. Please make sure Java is installed and on your system PATH." No Java found on PATH or in Android Studio/Program Files. Owner action: install a JDK (21) and re-run T4.01.

## Decisions
- D1 Canonical copy is D:\Rain.
- D2 The uncommitted firebase_adapter.dart edit is preserved as audit/wip/firebase_adapter-uncommitted.patch; HEAD logic is the baseline (restored in T3.1).
- D3 Work branch audit/rain-hardening is cut from dev. main/dev reconciliation happens in Phase 5 on branch integration/main-dev.
- D4 The Firebase project stays on Spark; Cloud Functions are optional, non-Spark extras.
- D5 Historical dart_defines.local.json values are treated as exposed; rotation is a manual owner action listed in the final report.

## Notes
- T3.5 baseline (2026-10-10): ANALYZE clean (4 packages), FORMAT clean (283 files), tests peer_core 76, protocol_brain 276, rain_core 61, apps/rain 744 pass + 20 skip, functions 37 pass, VAULT pass, npm audit:moderate 0 vulnerabilities.
- TEST gap for T3.1: FirebaseSignalingAdapter cannot be faked without new dependencies (no fake for FirebaseAuth/FirebaseDatabase); see TEST-001. Planned fix: T4.06.




