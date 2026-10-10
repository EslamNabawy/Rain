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
T4.05 253d8cb presence stays online during call/transfer when backgrounded; 5 new tests
T4.06 9155f4b reduced scope: registration rollback ordering unit-tested (4 tests); full DB/auth ports deferred to backlog
T4.07 13fdff2 encryptionState() + db_encryption_inactive event; open path unchanged
T4.08 4a7ed16 destroy robust to close errors; peer_core 77 pass
T4.09 deaef93 waitForDrain throws StateError on closed channel; peer_core 80 pass
T4.10 ad79d19 crossed invites: lower username keeps call; decision unit-tested (runtime-level glare test not added)
T4.11 71138df early candidate queue + notifyPeer on ringing timeout; protocol_brain 291 pass
T4.12 e1e4cb9 APP-003 test added; APP-002 fallback implemented without runtime-level test (private helper)
T4.13 696e78e 3 upgrade tests added; createTable is already idempotent so no guard needed
T4.14 03078d6 serializedWrite is re-entrant; offer+unread+transfer and failTransfer in one transaction; all apps/rain tests pass
T4.16 ccb88dd allowBackup=false + extraction rules; Android build not run (R7)
T4.17 6ff2037 ensureKeyPair verifies private key; login re-publishes key best-effort
T4.18 fda079f trustedUpdateUrl allow-list (https + github Rain repos or build host)
T4.20 c8186f8 service no longer imports firebase_auth; 2 broker tests
T4.21 4feaa3f protocol_brain_firebase.dart + testing.dart; boundary test; all packages green
T4.22 95778ab lazy FirebaseFunctions; source-contract test (adapter cannot be constructed in unit tests)
T4.23 b9e5348 flutter-action and gh-release pinned by SHA; v4 artifact/checkout aligned; dependabot.yml added
T5.1 95cbb07 integration/main-dev: origin/main merged (38 conflicts resolved); analyze/format clean; tests peer_core 80, protocol_brain 294, rain_core 69, apps/rain 774 pass + 20 skip, functions 37, vault pass; pushed, not merged into main/dev
T6.1 ebcca4e vault synced (R-024..R-032, BLK-011..013, TD-025..030, ADR-012/013, CONTINUITY); validator passes
T4.01 ecfafeb 16 rules cases pass on firebase-tools 13 + JDK 21; CI step added (firebase-tools 15.18.0 not run locally); confirms SEC-001
T4.03 e86e8ad rule added (base64 44 chars, rotation allowed, owner-only via parent write); 18 rules cases pass
T4.19 69ade05 userSearch read limited to orderByKey + limitToFirst<=20; 19 rules cases pass
SEC-002 aeed593 v=2 wired for rooms/* signaling (resolver, rules v1|v2+salt, 20 rules tests); voice-call envelopes remain v=1
CI-002 f79786c ci.yml now covers format, analyze, unit tests, functions, rules tests, emulator tests, vault, builds
CI-002b 63703cd redundant PR CI workflows removed; auto-prerelease on push to main (rain-ci-N) no longer happens
## Blocked
T4.15 SKIPPED (DB-003): premise invalid - no table declares a foreign key, so the beforeOpen foreign_key_check can never fail. DB-003 downgraded to P3 in audit/01-findings.md; quarantine-on-open-failure moved to backlog.

## Decisions
- D1 Canonical copy is D:\Rain.
- D2 The uncommitted firebase_adapter.dart edit is preserved as audit/wip/firebase_adapter-uncommitted.patch; HEAD logic is the baseline (restored in T3.1).
- D3 Work branch audit/rain-hardening is cut from dev. main/dev reconciliation happens in Phase 5 on branch integration/main-dev.
- D4 The Firebase project stays on Spark; Cloud Functions are optional, non-Spark extras.
- D5 Historical dart_defines.local.json values are treated as exposed; rotation is a manual owner action listed in the final report.

## Notes
- 2026-10-10 follow-up: JDK 21 installed (winget Microsoft.OpenJDK.21) at the owner's request; T4.01 (ecfafeb), T4.03 (e86e8ad) and T4.19 (69ade05) completed; RTDB rules tests 19/19 pass on firebase-tools 13. Note: T4.03 allows key rotation (not immutable) because a lost key is regenerated (T4.17).
- Phase 4 end (2026-10-10): ANALYZE clean, FORMAT clean, tests peer_core 80, protocol_brain 294, rain_core 67, apps/rain 760 pass + 20 skip, functions 37, vault pass. Blocked: T4.01/T4.03/T4.19 (no Java). Skipped: T4.15 (premise invalid). Reduced: T4.06. A stray empty-subject commit (ef1c897) exists from a mistaken helper call; history is not rewritten (R2).
- T3.5 baseline (2026-10-10): ANALYZE clean (4 packages), FORMAT clean (283 files), tests peer_core 76, protocol_brain 276, rain_core 61, apps/rain 744 pass + 20 skip, functions 37 pass, VAULT pass, npm audit:moderate 0 vulnerabilities.
- TEST gap for T3.1: FirebaseSignalingAdapter cannot be faked without new dependencies (no fake for FirebaseAuth/FirebaseDatabase); see TEST-001. Planned fix: T4.06.




