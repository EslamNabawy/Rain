# 2026-06-04 Multi-Issue Stability Investigation

Related: [[Current Architecture]], [[Project Memory]], [[Risk Register]], [[Technical Debt Register]], [[BLOCKERS]], [[Scenario Intelligence Agent]], [[System Model]], [[State Graph]], [[Failure Graph]]

## Scope

This is an investigation and remediation plan only. Production code was not modified in this pass.

Reported issues:

1. Incorrect connection status UI: UI shows "Not Connected" or equivalent while P2P messaging works.
2. Slow Windows shutdown: closing the Windows app takes about five seconds.
3. Splash screen theme flash: a white flash appears before the dark splash.
4. Presence desync after PC restart: mobile remains connected/online while reopened PC shows disconnected.
5. Desktop camera failure: voice works, mobile video works, desktop camera fails.
6. Delayed call-end screen: initiator sees delayed ended screen while the other peer sees it immediately.
7. Gender avatar not displayed on mobile: Vivo Y11 Android 7 shows first-letter fallback instead of the expected gender avatar.

Evidence level:

- Static repository review completed.
- Required vault/governance notes reviewed.
- Existing tests and prior diagnostics referenced where relevant.
- No live Android/Windows reproduction was executed during this investigation.
- No code validation was required because no production code changed.

## NODE 0 - Environment Verification

| Item | Result |
| --- | --- |
| Repository path | `C:/Users/eslam/OneDrive/Desktop/GoodStuff/Rain` |
| Branch | `dev` |
| Git status before documentation | Clean tracked tree, untracked `.obsidian/` workspace metadata |
| Workspace health | Required repo and vault files were accessible |
| Vault accessibility | `obsidian-vault/` accessible; `07-Investigations/` was missing and was created for this report |

## NODE 1 - Knowledge Synchronization

### Mission Summary

Rain is a peer-to-peer Flutter application with Firebase/RTDB signaling, local Drift persistence, Riverpod state, direct WebRTC data channels, voice/video call sessions, file transfers, presence, update policy, diagnostics, and release gates. Current launch risk is concentrated around state-machine interactions rather than isolated UI defects.

### Relevant Architecture

- `RainRuntimeController` owns presence, peer listener tracking, direct connect, file/call coordination, lifecycle shutdown, and local store mutations.
- `VoiceCallRuntime` is implemented as an extension over `RainRuntimeController`; it owns call signaling, WebRTC media sessions, terminal room reconciliation, call state publishing, renderer attachment, and cleanup.
- `connectionsProvider` mirrors `SessionManager` events into `PeerConnectionView` state.
- `voiceCallProvider` mirrors `RainRuntimeController.watchVoiceCallState()`.
- UI connect/call/file gates derive from local Riverpod snapshots: friend presence, connection diagnostics, call state, file transfer state, and runtime availability.
- Firebase is signaling/presence/control-plane only; voice/video media does not pass through Firebase.

### Relevant Risks

- R-001: PC-to-mobile voice/video setup can fail or remain stuck.
- R-002: stale Firebase call locks can report false busy.
- R-003: presence can remain online after app close or stale sessions.
- R-004: media capture, permissions, transceivers, or renderers can fail during setup.
- R-006: update prompt behavior can fail for old builds.
- R-007: oversized `VoiceCallRuntime` causes regression risk.
- R-008: `RainRuntimeController` owns too many domains.
- R-009: call terminal state has multiple truths.
- R-020: blocked actions may not show clear user-facing messages.
- R-022: startup/loading can render shell or protected routes before readiness.

### Relevant Blockers

- BLK-001: Voice/video call setup reliability is not fully proven.
- BLK-002: False busy/stale call locks remain a launch blocker.
- BLK-008: Presence staleness can misroute connect/call/request actions.
- BLK-010: Auth/session/startup readiness is mitigated for account deletion but broader device proof remains open.

### Relevant Technical Debt

- TD-001: oversized `VoiceCallRuntime`.
- TD-002: `RainRuntimeController` is too broad.
- TD-003: distributed call lease and terminal ownership.
- TD-004: implicit async call state machine.
- TD-014: broad UI rebuild/provider coupling.
- TD-016: WebRTC/media failure classification.
- TD-019: call UI instability.
- TD-022: startup route/global gate complexity.

## NODE 2 - Repository Discovery

### Affected Packages

- `apps/rain`: app runtime, state providers, UI, Android resources, force update flow, desktop window lifecycle.
- `packages/peer_core`: WebRTC media connection, capture constraints, route diagnostics.
- `packages/protocol_brain`: session manager, WebRTC data-session signaling, voice signaling contracts/adapters.
- `packages/rain_core`: identity, friend records, presence persistence, file transfer state.

### Affected Modules

- Connection/status: `apps/rain/lib/application/state/runtime_providers.dart`, `apps/rain/lib/application/state/connection_diagnostics.dart`, `apps/rain/lib/presentation/widgets/home/chat_panel.dart`, `apps/rain/lib/presentation/screens/home_screen.dart`.
- Presence/session lifecycle: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`, `apps/rain/lib/application/runtime/friend_runtime.dart`.
- Calls/file gates: `apps/rain/lib/application/runtime/voice_call_runtime.dart`, `apps/rain/lib/application/runtime/runtime_interaction_guard.dart`, `apps/rain/lib/application/runtime/file_transfer_runtime.dart`, `apps/rain/lib/application/state/call_surface_providers.dart`.
- Windows shutdown: `apps/rain/lib/infrastructure/window/desktop_shell_controller.dart`, `apps/rain/lib/application/runtime/app_exit_coordinator.dart`.
- Splash: `apps/rain/android/app/src/main/res/values/styles.xml`, `apps/rain/android/app/src/main/res/values-night/styles.xml`, `apps/rain/android/app/src/main/res/drawable/launch_background.xml`, `apps/rain/android/app/src/main/res/drawable-v21/launch_background.xml`, `apps/rain/lib/main.dart`, `apps/rain/lib/presentation/screens/splash_screen.dart`, `apps/rain/lib/presentation/screens/rain_app.dart`.
- Camera/video: `apps/rain/lib/application/runtime/media_device_settings.dart`, `apps/rain/lib/application/runtime/video_call_renderers.dart`, `packages/peer_core/lib/src/call/call_media_connection.dart`.
- Avatar/gender: `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`, `apps/rain/lib/application/runtime/friend_runtime.dart`, `apps/rain/lib/application/state/identity_providers.dart`, `packages/rain_core/lib/friends/friend_store.dart`, `packages/rain_core/lib/identity/identity.dart`, `apps/rain/pubspec.yaml`.

### Related Tests

- `apps/rain/test/voice_call_runtime_diagnostics_contract_test.dart`
- `apps/rain/test/voice_call_runtime_media_path_test.dart`
- `apps/rain/test/runtime_startup_test.dart`
- `apps/rain/test/friend_flow_test.dart`
- `apps/rain/test/rain_chat_widgets_test.dart`
- `apps/rain/test/settings_screen_test.dart`
- `packages/peer_core/test/call_media_connection_test.dart`
- `packages/peer_core/test/voice_media_connection_test.dart`
- `packages/protocol_brain/test/*voice*` and connection request adapter tests
- `packages/rain_core/test/rain_core_test.dart`

### Existing TODOs

No `TODO`, `FIXME`, or `HACK` markers were found in affected Dart implementation areas.

## NODE 3 - Task Understanding

### Requested Change

Investigate the seven reported stability/UX defects, identify root causes and weak points, and produce a full Obsidian investigation with prioritized remediation, risk matrix, roadmap, test plan, technical debt impact, architecture impact, blocker impact, and project memory updates.

### Assumptions

- The reports describe current behavior from installed or locally run Rain builds.
- Prior 2026-06-04 call/file/shutdown diagnostics remain relevant for call-state and shutdown symptoms.
- This phase intentionally avoids production code changes.

### Unknowns

- Exact device logs for the current seven-issue set were not supplied in this request.
- Exact Android theme mode at the time of the splash flash was not captured.
- Exact desktop camera failure message and Windows camera privacy state were not captured.
- Exact peer/call state at the time of the delayed ended screen was not captured.

### Scope Boundaries

- In scope: repository/vault analysis, RCA, remediation plan, validation strategy.
- Out of scope for this phase: code changes, release-gate trigger, live device reproduction, Remote Config deployment.

No blocking ambiguity remains for planning. The unknowns above become validation requirements.

## NODE 4 - Impact Analysis

| Area | Impact |
| --- | --- |
| Architecture Impact | High. Multiple issues point to split ownership between runtime state, Riverpod mirrors, presence, session manager, and call terminal state. |
| Database Impact | Medium. Friend presence/gender rows and active file/call transfer records influence visible state and gates. No schema migration is required for the proposed first fixes unless richer presence/session metadata is persisted. |
| Firebase Impact | High. Presence, voice call rooms, active call locks, inbox mirrors, and update Remote Config all affect user-visible behavior. |
| WebRTC Impact | High. Direct messaging, voice/video capture, data-channel routing, call hangup, media cleanup, and renderer attachment are involved. |
| Security Impact | Medium. Fixes must not loosen Firebase rules, expose diagnostics payloads, or allow unauthorized call/file/session state mutation. |
| Performance Impact | Medium. Shutdown latency, provider rebuilds, renderer setup, and presence reconciliation can affect older Android and Windows UX. |
| Operational Impact | High. These symptoms are release-gate relevant and should be covered by emulator/device smoke evidence before promotion. |
| Migration Impact | Low initially. Most fixes should be runtime/provider logic and test additions. Persisted richer session metadata could require Drift migration if chosen. |
| Documentation Impact | High. Risks, blockers, technical debt, scenario graph, and memory should be updated after implementation phases. |

## NODE 5 - Pattern Discovery

Research order was internal-first:

1. Existing Rain implementation reviewed.
2. Existing package patterns reviewed.
3. Existing architecture/vault notes reviewed.
4. No external research was needed for this phase.

Recurring existing patterns:

- Runtime state is mirrored to Riverpod through stream subscriptions and provider-specific `_replaceRuntime()` methods.
- Presence is resolved through backend `online + lastHeartbeat + state` and written to local `FriendStore`.
- Calls rely on Firebase terminal room state plus local `VoiceCallState` transitions.
- File transfer and connection request gates use `RuntimeInteractionGuard`.
- UI status often uses local derived state rather than querying the authoritative runtime at action time.

## NODE 6 - Architecture Validation

| Boundary | Result | Evidence |
| --- | --- | --- |
| Package ownership | Pass with risk | `apps/rain` owns app orchestration/UI; `peer_core` owns media connection; `protocol_brain` owns session/signaling contracts; `rain_core` owns local domain stores. Current fixes should preserve this. |
| Repository boundaries | Pass | No external service or new dependency is needed for first remediation. |
| Riverpod boundaries | Fail | Multiple UI gates derive from stale/mirrored provider state instead of one peer/call capability snapshot. `connectionsProvider`, `voiceCallProvider`, `friendsProvider`, and runtime readiness can diverge. |
| Firebase ownership | Pass with risk | Firebase remains control-plane only. Risk is stale presence/terminal room ordering and lock cleanup, not ownership violation. |
| WebRTC ownership | Pass with risk | WebRTC capture/session logic is in `peer_core` and call runtime wrappers. Risk is insufficient typed diagnostics and Windows device proof. |

Architecture conflicts:

- The app needs a single authoritative peer capability/call capability surface for UI gating.
- `VoiceCallRuntime` and `RainRuntimeController` remain too large for reliable incremental fixes.
- Call terminal state and cleanup must be further separated so cleanup cannot delay user-visible terminal state.

## Issue 1 - Incorrect Connection Status UI

### Executive Summary

The connection UI can show disconnected/offline/ready while P2P messaging still works because UI status is derived from `connectionsProvider` and local friend presence, while message delivery can continue through an active runtime/session path.

### Root Cause Analysis

Probable RCA: split source of truth.

Evidence:

- `ConnectionDiagnostics.fromConnection()` treats `PeerConnectionView.session` as the connection truth and falls back to local `isPeerOnline`.
- `ConnectionsController` rebuilds from `SessionManager` events but resets to empty when the matched runtime is unavailable.
- `ChatPanel` derives `isPeerOnline` from `friendsProvider` and action capability from a mix of friend state, connection diagnostics, `voiceCallProvider`, file transfer state, and runtime readiness.
- `RainRuntimeController` can still have `brain.getSession(peerId)` connected and send/flush messages even if the UI mirror missed or cleared the session snapshot.

Confidence: High for source-of-truth split; medium for the exact runtime sequence without live logs.

### Affected Components

- `connectionsProvider`
- `ConnectionDiagnostics`
- `ChatPanel`
- `RainRuntimeController.connectPeer()`
- `SessionManager`
- `FriendStore.updatePresence()`

### Failure Sequence

1. A peer session becomes connected or remains connected.
2. Messages continue through runtime/session.
3. `connectionsProvider` loses, misses, or clears the mirrored `Session` snapshot, or `friendsProvider` reports stale offline presence.
4. `ConnectionDiagnostics` falls through to offline/ready/disconnected.
5. UI reports not connected while the data channel still works.

### Severity

High. It makes users distrust the connection state and can misroute connect/request/call actions.

### User Impact

Users see a broken connection indicator while chat works, or they are asked to reconnect unnecessarily.

### Technical Impact

State divergence can also affect file transfer, voice call preflight, offline request routing, and support diagnostics.

### Risks

- R-003, R-008, R-010, R-020.
- Fixes that only rename labels will hide the bug without solving action gating.

### Recommended Solution

Create a runtime-owned `PeerConnectivitySnapshot` or equivalent capability model that combines:

- active `SessionManager` session state,
- data-channel/chat send readiness,
- presence freshness and session id,
- manual disconnect/recovery intent,
- connection coordinator retry/backoff state,
- last successful inbound/outbound data event.

Use that snapshot for:

- link status display,
- Connect/Disconnect enablement,
- offline request routing,
- voice/video call preflight,
- file-transfer preflight.

Then make `connectionsProvider` a view of that model instead of an independent state owner.

### Alternatives

- Add periodic `syncPeer()` calls from UI build/action paths. Lower effort, but still leaves multiple truth sources.
- Treat successful message send/receive as "connected" in diagnostics. Helpful as a patch, but incomplete for call/file gates.

### Validation Strategy

- Provider test: connected `SessionManager` session plus stale local `FriendRecord.isOnline=false` renders connected-with-presence-warning, not offline.
- Provider test: transient runtime loading does not erase visible connected state unless session generation changes.
- Widget test: messages can send while presence is stale; status differentiates data connected from presence stale.
- Integration/device test: PC restart/mobile open flow updates both peers deterministically.

### Regression Risks

- Offline request quota could be bypassed if presence and data readiness are conflated.
- Manual disconnect must still suppress auto-reconnect.

### Complexity / Effort

Medium-large. Requires provider/API refactor and broad tests, but no new dependency.

## Issue 2 - Slow Windows Shutdown

### Executive Summary

Windows close is bounded but still waits on the app-wide exit coordinator before destroying the window. Runtime shutdown performs call cleanup, file cancellation, peer disconnect, listener unregister, presence offline write, subscription cancellation, and voice-session disposal.

### Root Cause Analysis

Probable RCA: user-facing window close is coupled to serialized runtime cleanup.

Evidence:

- `DesktopShellController.onWindowClose()` awaits `AppExitCoordinator.instance.shutdown()` before `windowManager.destroy()` and `exit(0)`.
- `AppExitCoordinator` waits for all registered handlers with an 8 second timeout.
- `RainRuntimeController.closeForAppExit()` calls `_shutdown()`.
- `_runShutdown()` can end active calls, fail transfers, disconnect peers, unregister listeners, set presence offline, dispose current voice call session, stop request runtime, and cancel stream subscriptions.
- Voice cleanup steps are bounded, but several cleanup steps can still stack.

Confidence: High for shutdown architecture; medium for the exact five-second wait without stopwatch logs.

### Affected Components

- `DesktopShellController`
- `AppExitCoordinator`
- `RainRuntimeController._runShutdown()`
- `VoiceCallRuntime._disposeCurrentVoiceCallSession()`
- Firebase adapter presence/signaling writes
- WebRTC session disposal

### Failure Sequence

1. User clicks close.
2. Window close is intercepted because `setPreventClose(true)` is active.
3. App waits for exit coordinator handlers.
4. Runtime shutdown waits for cleanup chain.
5. Window is destroyed only after cleanup finishes or timeout expires.

### Severity

High for desktop UX; medium operationally because forced task-kill can skip cleanup.

### User Impact

The app feels stuck and the user may kill the process manually.

### Technical Impact

Manual process kill can leave presence, call locks, or in-flight transfers stale.

### Risks

- R-001, R-002, R-003, R-009.
- Reducing cleanup too aggressively can worsen stale presence/locks.

### Recommended Solution

Split shutdown into critical and best-effort phases:

1. Critical close budget: publish local terminal UI state, set presence offline, persist transfer/call cancellation intent.
2. Window close budget: destroy the window after a short hard cap, e.g. 750-1500 ms.
3. Best-effort cleanup: call/session/listener disposal continues only within a bounded process-exit budget.
4. Add per-handler and per-step stopwatch diagnostics so future reports identify the exact slow operation.

### Alternatives

- Lower `AppExitCoordinator.timeout`. Simpler, but hides which handler is slow.
- Fire-and-forget all cleanup. Fast, but likely increases stale Firebase/WebRTC artifacts.

### Validation Strategy

- Unit test with slow exit handler proves desktop close proceeds after the close budget.
- Runtime test with slow WebRTC dispose proves presence offline and terminal call state publish before cleanup wait.
- Manual Windows smoke: close with no session, active data session, active call, active transfer.
- Diagnostics assertion: exported log contains shutdown step durations.

### Regression Risks

- Presence may remain online if offline write is moved out of critical phase.
- Active call lock cleanup may become less reliable if terminal write is not prioritized.

### Complexity / Effort

Medium. Mostly lifecycle orchestration and tests.

## Issue 3 - Splash Screen Theme Flash

### Executive Summary

The launch drawable is dark, but Android `NormalTheme` in non-night mode uses the light system background. During the native-to-Flutter handoff, a white window background can appear before the dark Flutter splash paints.

### Root Cause Analysis

Probable RCA: platform theme handoff mismatch.

Evidence:

- `values/styles.xml` uses `Theme.Light.NoTitleBar` for `LaunchTheme` and `NormalTheme`.
- `NormalTheme` sets `android:windowBackground` to `?android:colorBackground`, which is light in non-night mode.
- `drawable/launch_background.xml` and `drawable-v21/launch_background.xml` are dark `#061017`.
- `RainSplashScreen` itself uses `RainColors.backgroundDark`.
- `RainStartupApp` renders a default `MaterialApp` during bootstrap without an explicit dark theme, though its splash scaffold is dark.

Confidence: High.

### Affected Components

- Android native themes/resources.
- Flutter bootstrap/splash app.
- Rain startup surface.

### Failure Sequence

1. OS starts activity with `LaunchTheme`.
2. Flutter embedding switches to `NormalTheme`.
3. Non-night `NormalTheme` exposes light `?android:colorBackground`.
4. Flutter dark splash paints after the white frame/window background is visible.

### Severity

Medium. Visual polish issue, but it damages startup quality and is noticeable on old Android devices.

### User Impact

White flash before dark Rain splash.

### Technical Impact

Signals that native and Flutter startup surfaces are not fully aligned.

### Risks

- R-022.
- A fix must preserve required-update/startup gate behavior.

### Recommended Solution

- Set both `LaunchTheme` and `NormalTheme` window backgrounds to the same Rain dark launch background in `values` and `values-night`.
- Add Android 12+ splash resources if needed for API 31+ (`windowSplashScreenBackground`) using the same dark color.
- Give the bootstrap `MaterialApp` an explicit dark Rain theme or `ThemeData.dark()` to avoid any default light frame.

### Alternatives

- Remove `NormalTheme` background. Less deterministic.
- Rely on user dark mode. Does not fix non-night system mode.

### Validation Strategy

- Android emulator screenshot/video on light system mode and dark system mode.
- First-frame visual smoke on Android 7 and current API.
- Widget/golden-style test for bootstrap splash using dark background.

### Regression Risks

- Incorrect theme resource names can break Android startup.
- Android 12 splash resources must not conflict with current Flutter embedding.

### Complexity / Effort

Small-medium.

## Issue 4 - Presence Desync After PC Restart

### Executive Summary

Presence and data-session state can desynchronize across restart because stale mobile-side session/presence and new PC runtime/session generation are reconciled through separate mechanisms.

### Root Cause Analysis

Probable RCA: presence freshness and peer session lifecycle are not represented as one session-owned connectivity state in UI/action gates.

Evidence:

- Presence freshness is resolved from backend `online`, heartbeat, and state.
- Local friend presence is seeded into `FriendStore` and watched through `adapter.watchPresence()`.
- `FriendRuntime._handlePeerPresenceExpired()` ends calls/transfers and disconnects the peer when presence becomes false.
- Shutdown attempts `adapter.setPresence(username, false)`, but it can be delayed by the cleanup chain.
- `connectionsProvider` and UI status can lose the session mirror independently from local friend presence.
- Session id exists in backend presence snapshots, but UI gates do not consistently compare old peer sessions against new presence session id.

Confidence: Medium-high.

### Affected Components

- Firebase presence adapter.
- `RainRuntimeController._resolveBackendPresence()`
- `FriendRuntime._watchPresence()` / `_handlePeerPresenceExpired()`
- `ConnectionsController`
- `ChatPanel` action gates.

### Failure Sequence

1. PC closes or restarts.
2. Mobile retains stale peer connection/presence state until backend offline write or heartbeat expiry is observed.
3. PC starts a new runtime/session generation.
4. PC UI sees no connected session and shows disconnected.
5. Mobile may still show connected/online because its local mirror has not reconciled stale presence/session ownership.

### Severity

Critical for connection/call reliability because it can cause false online, false busy, failed calls, and blocked offline request path.

### User Impact

Users see contradictory states on both devices and cannot trust connect/call status.

### Technical Impact

Stale presence can cascade into call locks, connection requests, and file-transfer gates.

### Risks

- R-002, R-003, R-009, R-016, R-020.
- FG-001 and FG-008 in [[Failure Graph]].

### Recommended Solution

- Promote presence session id and heartbeat age into the peer connectivity snapshot.
- On observing a new peer `sessionId`, invalidate old data-session assumptions for that peer unless a current data-channel heartbeat proves continuity.
- Make remote app close/restart produce a terminal peer intent: `presenceExpired`, `sessionSuperseded`, or `transportLost`.
- Reconcile `ConnectionDiagnostics` from both data-session and presence-session ownership, not local presence alone.
- Keep `onDisconnect`/server-side presence cleanup as the primary Firebase safety net, but do not rely on it as the only UI truth.

### Alternatives

- Shorten presence freshness window. Faster detection, but higher false offline risk on weak networks.
- Force reconnect on every startup. Simpler, but disruptive and may consume signaling resources.

### Validation Strategy

- Two-device integration: PC online, mobile connected, PC killed, mobile detects presence/session expiry and clears connected status.
- Restart integration: PC restarts with new session id, mobile invalidates old session and can reconnect.
- Emulator/fake adapter test for stale raw online + old heartbeat.
- Widget test for stale presence warning while data session remains connected.

### Regression Risks

- Over-eager invalidation can drop valid sessions during network blips.
- Manual disconnect and auto-recovery boundaries must remain explicit.

### Complexity / Effort

Large. This is a cross-cutting connectivity model fix.

## Issue 5 - Desktop Camera Failure

### Executive Summary

Because voice works and mobile video works, the highest-probability fault is local Windows camera capture/device/renderer behavior, not global call signaling. The current code has typed paths for camera capture and renderer failure but needs better Windows preflight and user-facing diagnostics.

### Root Cause Analysis

Probable RCA: desktop video path failure in one of three zones:

1. Selected camera device id is stale or unavailable.
2. `getUserMedia` video constraints fail on Windows due to permission/device/driver/capability.
3. RTC video renderer initialization or local stream attachment fails.

Evidence:

- `MediaDeviceSettings.loadVideoInputCapabilities()` detects missing selected devices but call start only receives the selected id provider indirectly.
- `CallMediaConnection._selectedVideoInputDeviceId()` falls back to default if selected id is missing.
- Video call capture uses `video` constraints with `facingMode: user` or selected `deviceId` plus fixed 320x240 to 640x480 constraints.
- `CallMediaConnection._captureLocalMedia()` maps video capture exceptions to camera permission required.
- `VideoCallRenderers.ensureInitialized()` and `attachLocalStream()` can fail separately from capture.
- `_VideoVoiceMediaConnection._attachLocalVideoStream()` logs renderer error but does not directly fail the call.

Confidence: Medium without Windows media logs.

### Affected Components

- `MediaDeviceSettings`
- `CallMediaConnection`
- `VideoCallRenderers`
- `VoiceCallRuntime` video path
- Windows privacy/device environment

### Failure Sequence

1. User starts video call from Windows.
2. Voice/audio path succeeds or is available.
3. Video capture or renderer setup fails.
4. Call either fails with generic camera/media copy or proceeds without visible local video.
5. User sees desktop camera failure while mobile video works.

### Severity

High. Video call core feature fails for desktop.

### User Impact

Users cannot use desktop camera or cannot tell whether the issue is permission, missing device, busy device, or renderer.

### Technical Impact

Generic media errors make support and diagnostics harder.

### Risks

- R-004, R-005, R-020.
- Misclassifying `cameraUnavailable` as permission denied can send users to the wrong fix.

### Recommended Solution

- Add a Windows video preflight before starting video call:
  - enumerate video inputs,
  - validate selected id,
  - attempt short camera-only capture,
  - dispose stream,
  - report typed result: no camera, selected camera missing, permission denied, busy/in use, capture constraints failed, renderer failed.
- Clear stale selected camera id automatically when it no longer appears.
- Surface the typed result in settings and call start error copy.
- Record diagnostics for selected device id presence, device count, capture result, renderer texture id, local first frame state.

### Alternatives

- Always use default camera by clearing selection. Simpler, but loses user preference.
- Lower/remove video constraints. May fix some devices, but does not solve permission/device diagnostics.

### Validation Strategy

- `peer_core` tests for stale selected camera id, denied capture, no video track, and constraint failure taxonomy.
- App tests for settings/call preflight messages.
- Manual Windows smoke with integrated camera, USB camera, camera disabled, camera busy in another app, no camera.
- Verify diagnostics export contains typed video preflight outcome.

### Regression Risks

- Camera preflight can briefly activate privacy indicators.
- Preflight must dispose streams quickly to avoid blocking the actual call capture.

### Complexity / Effort

Medium.

## Issue 6 - Delayed Call-End Screen

### Executive Summary

The initiator's ended screen depends on `VoiceCallState` transitioning from non-idle to idle. The local hangup path publishes `ending` immediately, but waits for durable terminal Firebase write before publishing idle. The remote peer can observe the terminal room and render ended earlier.

### Root Cause Analysis

Probable RCA: local terminal UI state is still delayed by terminal write durability in some local hangup paths.

Evidence:

- `HomeScreen._maybeShowEndedCallSummary()` only shows the ended surface when `next.phase == VoiceCallPhase.idle` and the previous phase was non-idle/non-failed.
- `hangUpVoiceCall()` calls `_endVoiceCallForPeer(notifyPeer: true)`.
- `_endVoiceCallForPeer()` sets `VoiceCallPhase.ending`, then awaits `_writeTerminalRoomBeforeSessionHangup()`.
- Only after a durable write does it call `_voiceCallStateAfterLocalEnd()`, which returns `VoiceCallState.idle()` for normal hangup.
- Remote terminal room reconciliation can call `_settleVoiceCallAfterTerminalRace()` and publish idle independently.

Confidence: High for the UI delay mechanism.

### Affected Components

- `VoiceCallRuntime._endVoiceCallForPeer()`
- `VoiceCallRuntime._writeTerminalRoomBeforeSessionHangup()`
- `HomeScreen._maybeShowEndedCallSummary()`
- `CallEndPresentationController`

### Failure Sequence

1. Initiator presses hang up.
2. Local state changes to `ending`.
3. Initiator waits for terminal Firebase write attempts/retries.
4. Remote sees terminal room state and transitions to idle/ended.
5. Initiator only shows ended surface after local idle transition.

### Severity

High. It makes call termination feel inconsistent and can keep file/call gates blocked during `ending`.

### User Impact

The person who hangs up sees delayed feedback.

### Technical Impact

Delayed idle can keep `RuntimeInteractionGuard._callBlocksFileTransfer()` true.

### Risks

- R-001, R-002, R-005, R-009, R-020.
- Changing terminal ordering incorrectly can leave remote peer unnotified.

### Recommended Solution

- Introduce an explicit ended-presentation event or terminal summary that is published immediately on local hangup before Firebase write retries.
- Keep `VoiceCallState` cleanup safe: local UI can show ended immediately while background terminal write/session cleanup continues.
- Ensure file-transfer gates treat locally terminal `ending` with completed local terminal intent as non-blocking after a short controlled transition.
- Preserve durable terminal write retry diagnostics and remote notification.

### Alternatives

- Transition to idle before terminal write. Fast UI, but risks losing local call context for diagnostics and remote notification.
- Keep current state but show ended surface on `ending`. Easier UI change, but can misrepresent failed terminal write unless modeled carefully.

### Validation Strategy

- Runtime test: local hangup emits ended presentation/idle-equivalent UI event before delayed terminal write completes.
- Runtime test: terminal write failure still shows correct failure or retry message without reblocking file transfers indefinitely.
- Widget test: call-ended surface appears immediately for local hangup.
- Two-device manual smoke: local and remote ended surfaces appear within the target latency.

### Regression Risks

- Call-again action could run before cleanup completes unless guarded by cleanup-in-progress state.
- Need idempotent handling of late terminal room echoes.

### Complexity / Effort

Medium.

## Issue 7 - Gender Avatar Not Displayed On Mobile

### Executive Summary

The avatar widget only shows the first-letter fallback when the `gender` argument is null or not `male`/`female`. The most likely issue is missing/unrecognized gender data in the mobile friend record or identity sync path. A secondary risk is the SVG asset path with spaces on older Android, but the asset folder is declared in `pubspec.yaml`.

### Root Cause Analysis

Probable RCA: gender data does not reach `RainAvatar` on the affected mobile path.

Evidence:

- `RainAvatar._avatarAssetForGender()` maps only `male` and `female`.
- If gender is null/unrecognized, it renders the first-letter fallback.
- Friend list/chat/call surfaces pass `friend.gender?.name`.
- Friend runtime fetches backend identity and persists `_backendGender(backendIdentity?.gender) ?? existing?.gender`.
- Identity provider parses backend gender similarly.
- `pubspec.yaml` includes `"assets/gender avatar/"`.
- `rain_chat_widgets_test.dart` already covers gender asset selection when gender is known.

Confidence: Medium-high for data-path issue; low-medium for asset path issue without Android 7 asset logs.

### Affected Components

- `RainAvatar`
- `FriendRuntime`
- `FriendStore`
- `IdentityController`
- Firebase/backend identity gender field
- Android asset/SVG rendering

### Failure Sequence

1. Friend gender is missing, null, not synchronized, or not one of `male`/`female`.
2. UI passes null/unrecognized `gender` to `RainAvatar`.
3. Avatar resolver returns null asset.
4. Widget renders first-letter fallback.

### Severity

Medium. Visual/profile issue, but it indicates identity metadata sync may be unreliable.

### User Impact

Expected gender avatar is missing on mobile.

### Technical Impact

Potential metadata propagation bug across backend identity, local friend store, and UI.

### Risks

- Identity/profile data can appear inconsistent across devices.
- SVG asset loading on Android 7 may have hidden platform-specific failure modes.

### Recommended Solution

- Add diagnostics/test coverage to prove backend gender reaches `FriendRecord.gender` after login, relationship sync, incoming request, accepted friendship, and profile update.
- Add a widget/provider regression where a mobile friend record with gender renders SVG asset.
- Consider moving assets from `assets/gender avatar/` to a no-space path such as `assets/gender_avatar/` for platform robustness.
- Add a debug diagnostic when `RainAvatar` falls back due to missing/unrecognized gender in contexts where a friend record exists.

### Alternatives

- Always show gender avatar from current user's gender. Incorrect for friend avatars.
- Hard-code fallback by display name. Not reliable and not acceptable.

### Validation Strategy

- Unit test `_backendGender()` parsing and friend sync preserves gender.
- App/provider test for relationship sync from backend identity with gender.
- Widget test on Android-targeted asset manifest if possible.
- Manual Android 7 smoke on Vivo Y11 or emulator-equivalent.

### Regression Risks

- Asset path rename requires updating tests and all references.
- Diagnostics must not expose sensitive user profile data beyond safe enum values.

### Complexity / Effort

Small-medium.

## Cross-Issue Analysis

Common roots:

- Split state ownership: runtime, Riverpod providers, local Drift state, and Firebase presence/signaling can disagree.
- Async cleanup controls visible state: call/file/close flows can wait for WebRTC/Firebase cleanup before UI/action gates unblock.
- Presence is used as a hard action gate even when data-session state has independent evidence.
- Terminal state needs stricter separation between user-visible terminal intent and best-effort backend/media cleanup.
- Diagnostics are improving but still lack per-step timing and typed media/preflight details for these reports.

Most related failure chains:

- Stale presence -> false online/connected -> call attempt -> stale lock/busy -> file transfer blocked.
- Local terminal call state -> UI surface hidden/delayed -> `VoiceCallState` non-idle -> file transfer blocked.
- Runtime transient null/provider mirror reset -> UI disconnected -> data channel still active.
- Native startup theme handoff -> white frame -> dark Flutter splash.
- Missing profile metadata -> avatar fallback.

## NODE 7 - Remediation Plan

### Prioritized Fix Order

1. Peer/call capability snapshot and state reconciliation.
   - Fixes connection status, presence desync, incorrect call/file gates, and "not in call but file blocked" class symptoms.
2. Local call terminal presentation before cleanup/write waits.
   - Fixes delayed ended screen and reduces stale active call/file-transfer blocking.
3. Shutdown critical-vs-best-effort split with timing diagnostics.
   - Fixes Windows close latency and improves stale cleanup evidence.
4. Desktop video preflight and typed camera/renderer diagnostics.
   - Fixes desktop camera supportability and likely root cause.
5. Android native/Flutter splash theme alignment.
   - Fixes white flash.
6. Gender avatar data-path and asset-path hardening.
   - Fixes mobile avatar fallback and metadata proof.

### Risk Matrix

| Issue | Severity | Probability | Primary Risk IDs | Launch Impact |
| --- | --- | --- | --- | --- |
| Connection status split | High | High | R-003, R-008, R-020 | High |
| Slow Windows shutdown | High | Medium | R-001, R-002, R-003 | High |
| Splash flash | Medium | High | R-022 | Medium |
| Presence desync after restart | Critical | High | R-002, R-003, R-009 | Critical |
| Desktop camera failure | High | Medium | R-004, R-005 | High |
| Delayed call-end screen | High | High | R-001, R-009, R-020 | High |
| Gender avatar fallback | Medium | Medium | Profile metadata consistency | Medium |

### Remediation Roadmap

Phase A - Connectivity and gate correctness:

- Add authoritative peer capability snapshot.
- Update link status, connect/request/call/file preflights to consume it.
- Add tests for stale presence + active data session, runtime transient loading, and restart session id change.

Phase B - Call terminal UX:

- Publish local ended presentation immediately on local hangup.
- Make terminal cleanup/write retries background-safe and idempotent.
- Add tests proving file transfer unblocks after terminal local intent.

Phase C - Shutdown:

- Add shutdown stopwatch diagnostics.
- Split critical offline/terminal intent from best-effort cleanup.
- Prove close latency with fake slow handlers and Windows manual smoke.

Phase D - Media:

- Add desktop video preflight and typed error taxonomy.
- Clear missing selected camera id.
- Add Windows manual/device smoke checklist.

Phase E - Startup visuals:

- Align Android `NormalTheme` with dark launch background.
- Add API 31+ splash background if needed.
- Add visual smoke.

Phase F - Avatar/profile:

- Prove gender sync pipeline.
- Harden asset path and fallback diagnostics.
- Validate on Android 7.

### Test Plan

- Unit/provider tests:
  - connectivity snapshot derivation,
  - stale presence/session id supersession,
  - call terminal presentation ordering,
  - file-transfer gate after terminal call,
  - desktop video preflight taxonomy,
  - gender sync and avatar asset selection.
- Widget tests:
  - link status with data connected + presence stale,
  - immediate ended surface on local hangup,
  - dark startup splash surface,
  - avatar on friend list/chat/call surfaces.
- Integration/fake adapter tests:
  - PC kill/restart with mobile still open,
  - terminal room write delay/failure,
  - stale call locks after failed setup.
- Device/manual smoke:
  - Android 7 splash and avatar,
  - Windows close latency,
  - Windows camera capture with integrated/USB/busy/disabled/no camera,
  - mobile-to-PC and PC-to-mobile voice/video call end.

### Technical Debt Impact

- TD-001/TD-004 worsen if more call fixes are patched directly into `VoiceCallRuntime` without extracting terminal/capability boundaries.
- TD-002 worsens if connectivity snapshot is added inside `RainRuntimeController` without a clear model/adapter boundary.
- TD-014 improves if UI consumes narrower selected state slices.
- TD-016 improves with typed desktop camera/video preflight.
- TD-019 improves with deterministic ended presentation.

### Architecture Impact

Required architecture change: introduce a first-class connectivity/capability model that is authoritative for UI gates. This should be derived from runtime/session/presence, not independently owned by presentation widgets.

Recommended ownership:

- `protocol_brain`: raw data session state.
- `RainRuntimeController` or extracted coordinator: peer capability aggregation.
- Riverpod providers: views/subscriptions of capability state only.
- UI: render/action consumers only.
- `peer_core`: media capture and typed media failure taxonomy.

### Blocker Impact

- BLK-001 remains open until call direction, camera, terminal, and reconnect smoke evidence passes.
- BLK-002 remains open until terminal local intent cannot leave hidden active calls or stale busy locks.
- BLK-008 remains open until presence/session id reconciliation is proven.
- BLK-010 remains mitigated for auth/account deletion, but startup visual/device proof remains relevant.

### Project Memory Updates

Add durable memory after this investigation:

- A multi-issue stability investigation was created on 2026-06-04.
- The dominant root is split runtime/provider/presence/call state ownership.
- Next implementation should start with peer/call capability state reconciliation before isolated UI fixes.
- No production code changed in the investigation phase.

## Production Readiness Review

| Area | Finding |
| --- | --- |
| Security | Do not loosen Firebase rules for terminal/presence fixes. Diagnostics must keep payload redaction. |
| Logging | Add per-step shutdown timing and typed camera/preflight outcomes. |
| Recovery paths | Presence/session supersession and terminal local intent need deterministic recovery. |
| Firebase quota impact | Avoid extra polling-heavy fixes; prefer existing watchers plus targeted reconciliation. |
| WebRTC failure modes | Must classify capture, permission, renderer, ICE/TURN, terminal, and cleanup separately. |
| Operational risks | Release gate should require device/emulator evidence for call/presence/camera/startup flows before promotion. |

## Version Control Preparation

Suggested staging command after this documentation pass:

```powershell
git add obsidian-vault/07-Investigations/2026-06-04` Multi-Issue` Stability` Investigation.md CONTINUITY.md obsidian-vault/AI-Memory/Project` Memory.md
```

Suggested semantic commit message:

```text
docs: add multi-issue stability investigation
```

## Completion Status For This Phase

- Investigation complete.
- Production implementation not started.
- Code validation not executed because no production code changed.
- Vault synchronization required: this report plus project memory/continuity update.
- Vault validation required after documentation updates.
