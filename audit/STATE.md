# Audit State

## Done
T0.1 cd7d51b branch audit/rain-hardening created, WIP patch preserved

## Blocked

## Decisions
- D1 Canonical copy is D:\Rain.
- D2 The uncommitted firebase_adapter.dart edit is preserved as audit/wip/firebase_adapter-uncommitted.patch; HEAD logic is the baseline (restored in T3.1).
- D3 Work branch audit/rain-hardening is cut from dev. main/dev reconciliation happens in Phase 5 on branch integration/main-dev.
- D4 The Firebase project stays on Spark; Cloud Functions are optional, non-Spark extras.
- D5 Historical dart_defines.local.json values are treated as exposed; rotation is a manual owner action listed in the final report.

## Notes

