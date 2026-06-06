# Scenario Coverage Matrix

Last updated: 2026-06-06

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
| SCN-CALL-002 | Optional inbox mirror missing during end-call cleanup | Ending -> terminal room authoritative -> mirror cleanup best-effort | ASSUMP-002 | FG-003 | Firebase emulator regression for missing `voiceCallInboxes` row during `endCall`; Phase 2 emulator proof passed in `.\scripts\ci_run_firebase_emulators.ps1`. | Add device smoke only if inbox mirror cleanup becomes release-gated beyond RTDB proof. | BLK-002, BLK-003 | Covered |
| SCN-CALL-003 | Live newer call lock must not be repaired away | ClaimingLease -> live lock inspected -> Busy | ASSUMP-005 | FG-001 | Fake/contract lease tests cover stale/live/newer lock behavior; Phase 2 emulator proof asserts denied cleanup preserves live pair/user locks, room, and inbox state. | Add live Firebase or device smoke only if release requires proof outside local emulator. | BLK-002 | Partially Covered |
| SCN-CALL-004 | Terminal failed/busy room during media cleanup must not keep local active call state | Connected media -> Firebase terminal busy/failed -> UI failed/idle before cleanup -> file transfer allowed | ASSUMP-002, ASSUMP-005, ASSUMP-013 | FG-001, FG-002 | `runtime_interaction_guard_test.dart` covers failed terminal calls not blocking file transfer; `voice_call_runtime_diagnostics_contract_test.dart` covers state-before-cleanup and bounded cleanup source contracts; targeted `friend_flow_test.dart` terminal cases passed; `runtime_startup_test.dart` covers bounded Windows close contract. | Add fresh Android-to-Windows device smoke with voice call, file transfer after failed call, and Windows close proof. | BLK-001, BLK-002 | Partially Covered |
| SCN-CALL-005 | Split peer UI truth while data lane remains open | Data session connected -> call failed/recovering or presence stale -> unified projected peer status | ASSUMP-003, ASSUMP-009, ASSUMP-013 | FG-010 | `connection_diagnostics_test.dart` covers precedence for manual disconnect, recovering call, out-of-sync session, connected, data-lane-only, and failed call over connected data lane. `chat_panel_connectivity_test.dart` proves stale presence renders `Data lane only` while send still works through `canSendData`. `friend_flow_test.dart --plain-name "video renderer"` proves remote renderer failure records `peer_ui_state_split_detected` while a data session remains connected. | Add device smoke only if cross-peer UI can still diverge outside provider-based surfaces. | BLK-001 | Covered |
| SCN-CALL-006 | Stale data-peer ICE callback after disconnect | Connecting/exchangingIce -> disconnect/recreate -> queued local candidate callback -> ignored before Firebase write | ASSUMP-002, ASSUMP-011 | FG-011 | `protocol_brain_test.dart --plain-name "ICE"` covers live ICE write failure still failing the active session and queued local ICE after disconnect not writing the stale room. `rain_debug_log_service_test.dart --plain-name "signaling decorator"` covers sanitized ICE path templates in debug events and `lastCrash.context`. | Add live Firebase/device proof only if repeated diagnostics show active current-room ICE writes still denied after this lifecycle fix. | BLK-003 | Covered |
| SCN-CALL-010 | Cross-device voice/video call direction matrix | Fresh presence -> invite -> local media -> offer/answer/ICE -> connected/terminal cleanup | ASSUMP-001, ASSUMP-002, ASSUMP-009, ASSUMP-013 | FG-001, FG-002 | Local unit/widget/fake/emulator proof covers call state, Firebase locks, terminal cleanup, and media adapter contracts. | Run Android-to-Android, Windows-to-Windows, Android-to-Windows, and Windows-to-Android voice/video smoke with version, commit, device OS, permission, ICE/media, terminal, and artifact evidence. | BLK-001, BLK-007 | Gap |
| SCN-MEDIA-010 | Real platform media capture through Rain call media stack | Device/emulator -> enumerate media devices -> `DefaultCallMediaConnection.startLocalMedia` -> local audio/video tracks -> dispose | ASSUMP-009 | FG-001 | `apps/rain/integration_test/device_media_reality_proof_test.dart` was added as an opt-in executable proof using `FlutterWebRTCBridge` and `DefaultCallMediaConnection`; default runs skip unless `RAIN_DEVICE_MEDIA_PROOF=true`. | Run on an attached Android emulator/device or Windows host with microphone/camera availability. 2026-06-05 probes found no attached Android device; the default integration-test attempt timed out and is not pass evidence. | BLK-001, BLK-007 | Gap |
| SCN-DIAG-001 | Android picker returns platform-managed handle | Exporting diagnostics -> content/document handle -> fallback JSON | ASSUMP-008 | FG-007 | `crash_diagnostics_service_test.dart` covers content URI and `/document/...` fallback behavior. | Add Android smoke evidence if diagnostics export is release-gated. | BLK-005 | Covered |
| SCN-DIAG-002 | New diagnostic field contains sensitive payload | Runtime diagnostic event -> sanitizer -> exported report | ASSUMP-011 | FG-002, FG-007 | Phase 4 sanitizer/export tests cover nested identifiers, paths, file names, Firebase paths, tokens, passwords, SDP, ICE, message-like content, and stack text; `RainDebugLogService` uses the same sanitizer. | Add a focused regression sample whenever a new diagnostic field can carry identifiers, paths, content, signaling frames, files, or secrets. | BLK-005 | Covered |
| SCN-UPDATE-001 | Remote Config policy is stale after release | LoadingPolicy -> RemotePolicyOutdated | ASSUMP-004 | FG-006 | `force_update_service_test.dart` and settings tests cover stale policy UI. `version_metadata_test.dart` proves the checked-in Remote Config template reports `updateRequired` for previous `1.0.6+7` stable/demo Android/Windows installs after the `1.0.7+8` metadata bump. `Build Rain Apps` run 26963049075 published `rain-test-109-1` artifacts for SHA `f1904e7`. Live Remote Config readback for `rain-8fb4b` version 8 now advertises `1.0.7+8` for stable/demo Android/Windows. | Add device/app proof that old `1.0.6+7` installs read the live policy and current `1.0.7+8` installs no longer report `remotePolicyOutdated`. | BLK-004, BLK-006 | Partially Covered |
| SCN-REQ-001 | Online direct connect must not spend offline request quota | Fresh online presence -> direct connect path | ASSUMP-010 | FG-008 | Connection request runtime tests cover online peer denied before adapter mutation. | Add RTDB rules/emulator proof for online receiver denial and quota non-consumption. | BLK-009, BLK-003 | Partially Covered |
| SCN-FILE-001 | Peer lane disconnect during active transfer | Transferring -> disconnected -> progress stable/reset samples | ASSUMP-001 | FG-001 | File transfer speed tracker reset tests exist. | Add device/network disconnect proof during an active large transfer if release confidence requires it. | BLK-006 adjacent, TD-008 | Partially Covered |
| SCN-FILE-002 | Large file transfer with slow receiver/backpressure and terminal cleanup | Offered -> Accepted -> Transferring -> Completed/Failed/Canceled | ASSUMP-014, ASSUMP-011 | FG-009, FG-007 | 2026-06-05 Phase 7 focused `friend_flow_test.dart` cases cover persistent receive sink reuse, scripted high-to-low backpressure wait, hash mismatch cleanup, cancel cleanup after a written chunk, and disk write failure. `file_transfer_protocol_test.dart` locks chunk/watermark/poll/timeout constants. | Add real-network/device-scale proof for very large transfers under slow receiver conditions before closing release-scale confidence. | TD-008, R-011 | Partially Covered |

## Phase 10 Device Media Reality Matrix - 2026-06-05

Source: [[2026-06-05 Senior Audit Remediation Plan]]

| ID | Target Direction Or Fault | Required Evidence | Current Evidence | Status | Next Action |
| --- | --- | --- | --- | --- | --- |
| P10-A2A | Android caller to Android receiver, voice and video | Two Android endpoints, accepted friends, fresh presence, mic/camera allowed, connected media, clean hangup. | No attached Android device on 2026-06-05. `QA_Medium_API_36_1` exists but was not launched. | Gap | Launch/attach two Android endpoints or explicitly reduce launch scope. |
| P10-W2W | Windows caller to Windows receiver, voice and video | Two Windows app instances or two Windows hosts with distinct accounts, media connected, clean terminal state. | Not run in this phase. | Gap | Define supported local two-instance setup or require two Windows hosts. |
| P10-A2W | Android caller to Windows receiver, voice and video | Android and Windows endpoints, version/commit/device OS recorded, diagnostics exported on failure. | Prior docs identify this as the next real smoke after terminal cleanup fixes; no fresh run on 2026-06-05. | Gap | Run fresh smoke and record artifacts under `D:\android-test-artifacts` plus Windows diagnostics if needed. |
| P10-W2A | Windows caller to Android receiver, voice and video | Reverse-direction setup with same evidence as P10-A2W. | Not run in this phase. | Gap | Run after P10-A2W or explicitly scope direction out. |
| P10-MEDIA | Single-device media capture | `apps/rain/integration_test/device_media_reality_proof_test.dart` passes with real microphone and camera tracks. | Test exists and uses real `FlutterWebRTCBridge` plus `DefaultCallMediaConnection`; not executed successfully because no Android device was attached and the default integration-test probe timed out. | Gap | `flutter test integration_test\device_media_reality_proof_test.dart -d emulator-5554 --dart-define=RAIN_DEVICE_MEDIA_PROOF=true` from `apps\rain`. |
| P10-MIC-DENIED | Microphone permission denied | Denial produces typed media-permission failure, no stuck room/lock, sanitized diagnostics. | Local fake/unit proof exists; no device permission denial proof. | Partially Covered | Run Android permission-denied smoke using OS permission controls. |
| P10-CAMERA-DENIED | Camera permission denied | Video denial produces typed camera failure, no stale invite, sanitized diagnostics. | Local fake/unit proof exists; no device permission denial proof. | Partially Covered | Run Android and Windows camera-denied smoke. |
| P10-NETWORK-LOSS | Network loss during active call | UI transitions to reconnect/terminal without stale active-call guard; diagnostics classify network/ICE path. | Local runtime network-loss tests exist; no real device network toggle proof. | Partially Covered | Run device smoke with Wi-Fi/network toggle during active call. |
| P10-APP-CLOSE | App close during call/presence | Peer observes offline/terminal behavior without stale presence enabling call/request. | Presence/app-close local proof exists; no fresh Android/Windows device run. | Partially Covered | Run close/reopen smoke on Android and Windows. |
| P10-STALE-LOCK | Stale terminal/busy lock before new call | Stale lock cleaned only when policy allows; live locks preserved; new call setup works. | Phase 2 emulator proof exists; no live Firebase/device proof. | Partially Covered | Run live Firebase/device stale-lock smoke only if release gate requires proof beyond emulator. |

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

- Local validation exists, and hard release workflows now name auth scenario IDs plus vault validation. `Build Rain Apps` run 26957834309 proves exact commit, scenario gate, Android/Windows artifacts, and release-page publication for the account-deletion change. `Build Rain Apps` run 26963049075 proves the `1.0.7+8` update-warning metadata bump on pushed SHA `f1904e7` with Android/Windows artifacts and release-page publication. Live Remote Config deploy/readback now proves `rain-8fb4b` version 8 advertises `1.0.7+8`; device/app read proof remains.

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
