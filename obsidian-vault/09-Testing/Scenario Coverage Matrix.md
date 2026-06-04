# Scenario Coverage Matrix

Last updated: 2026-06-04

## Purpose

Map scenario-intelligence outputs to existing tests, validation gaps, blockers, risks, and release-gate actions.

This is the applied bridge between [[Scenario Intelligence Agent]], [[Assumption Register]], [[Failure Graph]], [[Test Strategy]], [[Coverage Dashboard]], and [[Release Gates]].

## Coverage Status Values

- Covered: deterministic local or emulator validation exists and was previously recorded.
- Partially Covered: some local tests exist, but a critical platform, emulator, device, or release-gate proof is missing.
- Gap: no adequate deterministic coverage is documented.
- Accepted: residual risk is explicitly accepted in launch/readiness notes.

## Scenario Matrix

| Scenario ID | Target Flow | State Path | Violated Assumption | Failure Chain | Existing Evidence | Gap / Next Test | Related Blocker | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SCN-AUTH-001 | Cached identity restore after backend deletion | Authenticated -> session validation -> LoggedOut | ASSUMP-007 | FG-004 | `apps/rain/test/auth_identity_source_of_truth_test.dart` covers deleted backend identity and uid mismatch; hard release workflows run this scenario ID explicitly. | Cloud gate passed in `Build Rain Apps` run 26957834309 at `883886a`. | BLK-010 | Covered |
| SCN-AUTH-002 | Login after account tombstone with surviving Auth | Authenticated Auth user -> login -> backend proof missing -> LoggedOut | ASSUMP-007 | FG-004 | `auth_identity_source_of_truth_test.dart` covers login refusing to recreate missing backend account; `integration_account_deletion_emulator_test.dart` proves a tombstoned surviving Auth user cannot recreate profile or `userSearch`. | Cloud gate passed in `Build Rain Apps` run 26957834309 at `883886a`. | BLK-010, BLK-003 | Covered |
| SCN-AUTH-003 | Delete account bad password | Authenticated -> DeletingAccount preflight -> Authenticated | ASSUMP-001, ASSUMP-007 | FG-004 | `apps/rain/test/runtime_startup_test.dart` covers preserving local identity before failed reauth; `settings_screen_test.dart` covers password prompt/error; hard release workflows run this scenario ID explicitly. | Cloud gate passed in `Build Rain Apps` run 26957834309 at `883886a`. | BLK-010 | Covered |
| SCN-AUTH-004 | Delete account backend partial failure | Authenticated -> DeletingAccount destructive -> LoggedOut with error | ASSUMP-002 | FG-004 | `apps/rain/test/runtime_startup_test.dart` covers local clear after backend failure; `integration_account_deletion_emulator_test.dart` proves emulator tombstone/search cleanup. | Cloud gate passed in `Build Rain Apps` run 26957834309 at `883886a`. | BLK-010, BLK-003 | Covered |
| SCN-PRES-001 | Stale raw-online presence before call/connect/request | Online -> Stale -> Offline decision | ASSUMP-003 | FG-001, FG-008 | `friend_flow_test.dart` stale backend presence cases; protocol presence contract tests. | Add release-gate targeted presence scenario and Android/Windows smoke proof if needed. | BLK-008, BLK-009 | Partially Covered |
| SCN-CALL-001 | Terminal room before late local SDP write | Negotiating -> terminal room observed -> Failed/Ended without write crash | ASSUMP-002, ASSUMP-009 | FG-002 | Runtime terminal-sensitive write preflight tests from Phase 08/2026-06-04 validation. | Add device-direction proof for PC-to-mobile and mobile-to-PC. | BLK-001 | Partially Covered |
| SCN-CALL-002 | Optional inbox mirror missing during end-call cleanup | Ending -> terminal room authoritative -> mirror cleanup best-effort | ASSUMP-002 | FG-003 | Firebase emulator regression for missing `voiceCallInboxes` row during `endCall`. | Add all terminal-room mirror variants to emulator matrix. | BLK-002, BLK-003 | Partially Covered |
| SCN-CALL-003 | Live newer call lock must not be repaired away | ClaimingLease -> live lock inspected -> Busy | ASSUMP-005 | FG-001 | Fake/contract lease tests cover some stale/live lock behavior. | Add emulator tests for newer live locks across pair/user paths. | BLK-002 | Gap |
| SCN-CALL-004 | Terminal failed/busy room during media cleanup must not keep local active call state | Connected media -> Firebase terminal busy/failed -> UI failed/idle before cleanup -> file transfer allowed | ASSUMP-002, ASSUMP-005, ASSUMP-013 | FG-001, FG-002 | `runtime_interaction_guard_test.dart` covers failed terminal calls not blocking file transfer; `voice_call_runtime_diagnostics_contract_test.dart` covers state-before-cleanup and bounded cleanup source contracts; targeted `friend_flow_test.dart` terminal cases passed; `runtime_startup_test.dart` covers bounded Windows close contract. | Add fresh Android-to-Windows device smoke with voice call, file transfer after failed call, and Windows close proof. | BLK-001, BLK-002 | Partially Covered |
| SCN-DIAG-001 | Android picker returns platform-managed handle | Exporting diagnostics -> content/document handle -> fallback JSON | ASSUMP-008 | FG-007 | `crash_diagnostics_service_test.dart` covers content URI and `/document/...` fallback behavior. | Add Android smoke evidence if diagnostics export is release-gated. | BLK-005 | Covered |
| SCN-DIAG-002 | New diagnostic field contains sensitive payload | Runtime diagnostic event -> sanitizer -> exported report | ASSUMP-011 | FG-002, FG-007 | Sanitizer/export tests exist for selected fields; diagnostics notes require no SDP/ICE/password/message/file bytes. | Add recursive sanitizer matrix for tokens, SDP, ICE, ciphertext, message text, file bytes. | BLK-005 | Gap |
| SCN-UPDATE-001 | Remote Config policy is stale after release | LoadingPolicy -> RemotePolicyOutdated | ASSUMP-004 | FG-006 | `force_update_service_test.dart` and settings tests cover stale policy UI. `version_metadata_test.dart` now proves the checked-in Remote Config template reports `updateRequired` for previous `1.0.6+7` stable/demo Android/Windows installs after the `1.0.7+8` metadata bump. | Add release artifact evidence that deployed Remote Config manifest matches commit/version and old installed apps read the deployed value. | BLK-004, BLK-006 | Partially Covered |
| SCN-REQ-001 | Online direct connect must not spend offline request quota | Fresh online presence -> direct connect path | ASSUMP-010 | FG-008 | Connection request runtime tests cover online peer denied before adapter mutation. | Add RTDB rules/emulator proof for online receiver denial and quota non-consumption. | BLK-009, BLK-003 | Partially Covered |
| SCN-FILE-001 | Peer lane disconnect during active transfer | Transferring -> disconnected -> progress stable/reset samples | ASSUMP-001 | FG-001 | File transfer speed tracker reset tests exist. | Add large-transfer slow receiver/backpressure proof. | BLK-006 adjacent, TD-008 | Partially Covered |

## Applied Blocker Pass - 2026-06-04

### BLK-001: Voice/Video Call Setup Reliability

Scenario-derived weak points:

- Device-direction proof is still missing for PC-to-mobile and mobile-to-PC call setup.
- Terminal-room preflight exists locally, but release proof needs real device logs or emulator/device smoke artifacts.
- ICE/TURN route and first-frame evidence remain weaker than Firebase/signaling evidence.

Next tests:

- Add a call setup scenario that records presence freshness, room timeline, lock state, ICE route, media permission, and terminal state for both directions.
- Promote terminal-room late-write regression into hard release gate.
- Add a device smoke for SCN-CALL-004: mobile-to-PC voice call failure/retry, file send after terminal call, and Windows close after call cleanup.

### BLK-003: Firebase Rules And Spark-Safe Behavior

Scenario-derived weak points:

- Account deletion tombstone/upsert/search denial now has Firebase emulator proof in `integration_account_deletion_emulator_test.dart`.
- Connection request quota and online receiver denial need rules/emulator proof.
- Call lock live/newer lock repair must be proven in emulator, not only fake paths.

Next tests:

- Keep tombstoned `users/{username}` refusing `userSearch` re-add and profile upsert in the hard Firebase emulator gate.
- Add emulator cases for online receiver request denial without quota mutation.
- Add pair/user lock newer-live denial cases.

### BLK-006: Release Workflow Gate Evidence

Scenario-derived weak points:

- Local validation exists, and hard release workflows now name auth scenario IDs plus vault validation. `Build Rain Apps` run 26957834309 proves exact commit, scenario gate, Android/Windows artifacts, and release-page publication for the account-deletion change. The `1.0.7+8` metadata bump proves checked-in policy behavior for previous `1.0.6+7`, but deployed Remote Config manifest proof remains missing.

Next tests:

- Require release summaries to list scenario IDs covered or explicitly skipped.

### BLK-010: Auth Session And Startup Readiness

Scenario-derived weak points:

- Local tests cover the main lifecycle, hard release workflows now include account deletion, login/no-recreate, startup protected-route, and bad-password scenarios by ID, and Firebase emulator proof now covers tombstone cleanup plus post-delete denial.

Next tests:

- Keep these auth scenario IDs in the hard release gate and add device/emulator proof for the remaining partially covered call, presence, request, update, and diagnostics scenarios.

## Maintenance Rules

- Add one row for each scenario used in release-gate, blocker, or risk analysis.
- Do not mark a scenario Covered unless a named test or validation exists.
- Use Partially Covered when local tests exist but device, emulator, or release-gate proof remains missing.
- Link every Gap to a blocker, risk, debt item, or recommended next action.

Related: [[Failure Graph]], [[Assumption Register]], [[Emulator Test Matrix]], [[Coverage Dashboard]].
