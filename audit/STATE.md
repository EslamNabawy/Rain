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
## Blocked

## Decisions
- D1 Canonical copy is D:\Rain.
- D2 The uncommitted firebase_adapter.dart edit is preserved as audit/wip/firebase_adapter-uncommitted.patch; HEAD logic is the baseline (restored in T3.1).
- D3 Work branch audit/rain-hardening is cut from dev. main/dev reconciliation happens in Phase 5 on branch integration/main-dev.
- D4 The Firebase project stays on Spark; Cloud Functions are optional, non-Spark extras.
- D5 Historical dart_defines.local.json values are treated as exposed; rotation is a manual owner action listed in the final report.

## Notes
- TEST gap for T3.1: FirebaseSignalingAdapter cannot be faked without new dependencies (no fake for FirebaseAuth/FirebaseDatabase); see TEST-001. Planned fix: T4.06.




