# Rain Call Runtime Stability And Device Capability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan phase by phase. Use `superpowers:subagent-driven-development` for parallel read-only review or disjoint implementation slices only after phase boundaries are locked.

**Goal:** Make Rain startup loading, peer connection cleanup, voice/video call setup, retry behavior, call duration, mute state, disconnect/reconnect, call UI surfaces, and camera controls deterministic across Android and Windows.

**Architecture:** Fix this from the bottom up. First lock evidence and state ownership, then repair signaling leases and terminal cleanup, then harden media setup and renderer failure paths, then fix app state/UI. Do not start with visual tweaks while stale Firebase call locks or stale local call state can still lie to the UI.

**Tech Stack:** Flutter, Riverpod, GoRouter, Firebase Realtime Database voice signaling, `protocol_brain`, `peer_core`, `flutter_webrtc`, Melos validation, Android and Windows manual gates.

**Critical Rules:**

- Commit after every completed phase.
- Do not build until the final gate unless a phase explicitly requests a focused smoke build.
- Do not regress the currently working voice path while fixing video.
- Keep one active call globally unless a later approved plan changes that product rule.
- Treat stale remote state, app close, local media failure, and renderer failure as normal runtime events, not exceptional crashes.

---

## Dependency Map

1. Evidence and state ownership must come first, because the same stale call state explains multiple symptoms.
2. Startup shell gating can be fixed early because it is independent and reduces visual confusion during app boot.
3. Firebase call lease cleanup must be fixed before retry, busy, and cross-device call behavior.
4. Terminal state reconciliation must be fixed before phone/computer stale "running call" bugs.
5. Media and renderer crash hardening must be fixed before video UI polish.
6. Clock, mute, reconnect, and UI fixes come after the runtime can tell the truth.
7. Device capability detection comes before hiding laptop-only invalid controls.
8. Full automated and manual gates happen at the end.

---

## Phase 00: Evidence Lock And Failure Taxonomy

**Purpose:** Stop guessing. Convert every reported symptom into a named failure class with an owner layer and acceptance test target.

- [x] Create `docs/qa/2026-05-24-rain-call-runtime-stability-audit.md`.
- [x] Record the observed failures as separate rows:
  - Startup loading shows bottom navigation.
  - PC to phone voice call returns `peer busy` on first attempt and succeeds only after retry confusion.
  - Call duration remains `0`.
  - Local mute causes remote mute text to flicker.
  - PC to phone video request fails and Windows app closes.
  - Remote app close does not fully dispose the connection.
  - Phone to computer video call leaves phone in a false active-video state.
  - Phone manual disconnect prevents reconnect.
  - Expanded call popup and top call manager duplicate controls.
  - Laptop shows flip-camera control with no rear camera.
- [x] For each row, assign one primary owner:
  - App shell/navigation.
  - Firebase call lease/signaling.
  - Local call runtime state.
  - Peer session/media setup.
  - Renderer/video resources.
  - Call surface UI.
  - Media device capability inventory.
- [x] Add the expected terminal state for every failure path: `idle`, `failed`, `ended`, or `disconnected`.
- [x] Add a short "do not fix by UI masking" note for busy locks, stale active calls, and renderer crashes.
- [x] Commit with message: `docs: audit Rain call runtime failures`.

## Phase 01: Startup Splash Gate Ownership

**Purpose:** Make the splash screen own all app startup loading states and prevent the bottom navigation shell from appearing while the root runtime is still loading.

- [x] Inspect current shell conditions in `apps/rain/lib/presentation/navigation/app_routes.dart`.
- [x] Inspect startup surfaces in:
  - `apps/rain/lib/main.dart`
  - `apps/rain/lib/presentation/screens/root_screen.dart`
  - `apps/rain/lib/presentation/screens/splash_screen.dart`
- [x] Introduce a single app-shell readiness decision that includes update gate, identity readiness, and runtime readiness.
- [x] Ensure `RainNavigationShell` hides bottom navigation whenever `RootScreen` would show `RainSplashScreen`.
- [x] Remove or bypass the old quick loading surface if it duplicates the real splash experience.
- [x] Add or update tests:
  - `apps/rain/test/root_screen_test.dart`
  - a navigation-shell test proving bottom navigation is hidden while runtime loading is active.
- [x] Acceptance:
  - Cold start shows only the Rain splash loading surface.
  - No bottom navigation appears until the app is ready for normal navigation.
  - Existing signed-in startup still lands on the correct home route.
- [x] Commit with message: `fix: gate navigation behind Rain startup readiness`.

## Phase 02: Firebase Call Lease And Busy Lock Hygiene

**Purpose:** Fix the first root cause behind `peer busy`: stale or incorrectly retained active voice/video pair locks.

- [x] Audit `packages/protocol_brain/lib/adapters/firebase_adapter.dart` call creation, active pair claiming, stale pair reclaim, room terminal update, and cleanup paths.
- [x] Audit runtime paths that call Firebase call cleanup from `apps/rain/lib/application/runtime/voice_call_runtime.dart`.
- [x] Define one authoritative lock invariant:
  - A pair lock exists only while a non-terminal call room is alive.
  - Any local setup failure must write a terminal room state and release the matching pair lock.
  - Any remote terminal room state must release local runtime state.
  - Stale locks are reclaimable by age and by terminal room state.
- [x] Add protocol tests covering:
  - terminal room releases `activeVoicePairs`.
  - stale active pair can be reclaimed without creating a reverse incoming call.
  - failed local media setup releases the pair lock.
  - duplicate invite while an active non-terminal room exists returns busy.
- [x] Add emulator or fake adapter tests for PC to phone first-attempt invite success after a stale previous failed call.
- [x] Acceptance:
  - First call attempt after a failed or closed prior call does not show false `peer busy`.
  - Retry never flips direction by making the original caller receive the call request.
- [x] Commit with message: `fix: clean stale Firebase call leases`.

## Phase 03: Call Direction And Retry Semantics

**Purpose:** Make retry mean "retry my outgoing call" instead of accidentally accepting or reflecting a stale incoming request.

- [x] Confirm the existing `VoiceCallState.isOutgoing` direction model is unambiguous and lock retry semantics around it:
  - `outgoing`
  - `incoming`
  - `remoteInitiatedRetry` only if explicitly needed and tested.
- [x] Ensure outgoing retry creates a new call id or a clearly versioned retry attempt for the same owner.
- [x] Ignore or clear stale invite frames whose call id, owner, session epoch, or room status no longer matches the active local attempt.
- [x] Ensure failed outgoing voice/video attempts cannot remain visible as incoming requests on the original caller.
- [x] Add tests in runtime/fake signaling:
  - PC outgoing voice retry stays PC outgoing.
  - Android receiving side does not send a new reverse invite during retry.
  - stale invite is ignored after terminal room state.
- [x] Acceptance:
  - PC to phone voice call either rings the phone or fails with a true actionable reason.
  - Pressing retry does not swap caller/callee roles.
- [x] Commit with message: `fix: preserve call direction during retry`.

## Phase 04: Terminal State Reconciliation And Remote App Close

**Purpose:** Make both peers converge to the same terminal state when either side closes the app, loses runtime, hangs up, fails media, or disconnects.

- [x] Audit shutdown and logout paths in `apps/rain/lib/application/runtime/rain_runtime_controller.dart`.
- [x] Audit `_disposeCurrentVoiceCallSession`, `_failVoiceCall`, `_endVoiceCallForPeer`, and Firebase room watchers in `voice_call_runtime.dart`.
- [x] Add a terminal reconciliation rule:
  - Remote `ended`, `failed`, `rejected`, `busy`, `expired`, or presence-offline event ends local call media and returns UI to idle or failed.
  - Local app shutdown writes terminal state when possible.
  - If the app cannot notify the peer, the peer reclaims by lease timeout and presence.
- [x] Ensure peer data connection disposal cancels call media and video renderers before clearing listeners.
- [x] Add tests:
  - remote app close disposes local call session.
  - remote hangup clears local active video state.
  - local shutdown clears or expires Firebase active pair.
  - terminal state is idempotent when received twice.
- [x] Acceptance:
  - If the other peer closes Rain, the remaining app stops showing an active call.
  - Phone no longer thinks a video call is running after computer failure or close.
- [x] Commit with message: `fix: reconcile terminal call state`.

## Phase 05: Video Media And Renderer Crash Hardening

**Purpose:** Turn PC to phone video setup failures into controlled call failures instead of Windows app crashes or stuck Android states.

- [x] Audit video setup in `apps/rain/lib/application/runtime/voice_call_runtime.dart`.
- [x] Audit renderer lifecycle in call overlay widgets and `peer_core` media connection disposal.
- [x] Wrap video media creation, local renderer attach, remote renderer attach, first-frame timeout, and dispose in guarded paths.
- [x] Convert thrown media/renderer failures into typed runtime failures:
  - `cameraDenied`
  - `cameraUnavailable`
  - `mediaConnectionFailed`
  - `videoRendererFailed`
  - `videoFirstFrameTimeout`
- [x] On any video setup failure:
  - stop local camera and microphone tracks opened for that attempt.
  - send terminal failed state through Firebase.
  - release active pair lock.
  - keep the app process alive.
  - keep chat usable.
- [x] Add tests with fakes:
  - local renderer creation throws.
  - remote renderer attach throws.
  - media connection fails after room creation.
  - first-frame timeout ends only the call, not the chat session.
- [x] Acceptance:
  - PC app does not close when Android video setup fails.
  - Android does not stay in a false active video state after Windows media failure.
- [x] Commit with message: `fix: harden video media failures`.

## Phase 06: Call Clock And Mute State Truth Source

**Purpose:** Fix call duration stuck at `0` and remove remote mute flicker.

- [x] Audit `VoiceCallState.startedAt` ownership in `apps/rain/lib/application/runtime/voice_call_state.dart`.
- [x] Audit runtime mapping in `_applyVoiceSessionState`.
- [x] Audit timer displays in:
  - `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
  - `apps/rain/lib/presentation/widgets/calls/rain_call_manager_bar.dart`
  - `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- [x] Define call clock rule:
  - The first transition to active sets `startedAt`.
  - No later state mapping can reset it to null or now unless a new call id starts.
  - UI duration is derived from a monotonic ticker and stable `startedAt`.
- [x] Define mute truth source:
  - Local mute controls only local `isMuted`.
  - Remote mute text uses remote peer mute updates only.
  - Session state cannot overwrite newer Firebase room mute values with stale defaults.
- [x] Add tests:
  - active call duration increments past `0`.
  - local mute does not show `Peer muted`.
  - remote mute update appears once and does not flicker when session emits another state update.
  - terminal call stops ticking.
- [x] Acceptance:
  - Active voice/video calls show increasing duration.
  - Mute state labels are stable and do not twitch.
- [x] Commit with message: `fix: stabilize call clock and mute state`.

## Phase 07: Disconnect And Reconnect Intent Reset

**Purpose:** Make manual disconnect a reversible user action, not a state that blocks future connection attempts.

- [x] Audit `ConnectionsController.disconnect` and `syncPeer` in `apps/rain/lib/application/state/runtime_providers.dart`.
- [x] Audit runtime manual disconnect tracking in `RainRuntimeController`.
- [x] Define manual disconnect rule:
  - Disconnect can intentionally stop auto-reconnect.
  - The explicit Connect button must still be enabled after disconnect completes.
  - Pressing Connect clears manual disconnect intent for that peer before starting connection.
- [x] Ensure failed disconnect cleanup does not leave `actionBusy` or `disconnecting` stuck.
- [x] Add tests:
  - phone disconnect returns UI to disconnected and connect-enabled.
  - pressing connect after manual disconnect clears manual intent.
  - remote offline disconnect and manual disconnect have separate display text.
- [x] Acceptance:
  - On Android, after pressing disconnect, the connect button can be pressed again.
- [x] Commit with message: `fix: allow reconnect after manual disconnect`.

## Phase 08: Call Surface Rendering Contract

**Purpose:** Remove duplicated call controls and make expanded/minimized behavior simple and predictable.

- [x] Audit call surface state in `apps/rain/lib/application/state/call_surface_providers.dart`.
- [x] Audit rendering in `apps/rain/lib/presentation/screens/home_screen.dart`.
- [x] Define one rendering contract:
  - Expanded popup visible: hide top call manager bar.
  - Fullscreen video visible: hide top call manager bar.
  - Picture-in-picture video visible: show compact top call manager bar.
  - Manager-only minimized state: show top call manager bar.
  - No active call: show no call surface.
- [x] Use one shared icon/capability mapping for manager bar and popup controls.
- [x] Add tests:
  - expanded popup suppresses manager bar.
  - minimized audio shows manager bar.
  - video PiP shows manager bar and PiP window.
  - fullscreen hides manager bar.
  - icons match for the same action across surfaces.
- [x] Acceptance:
  - No duplicated top bar plus popup controls.
  - Minimized call remains manageable from the top, not buried at the bottom of chat.
- [x] Commit with message: `fix: simplify call surface rendering`.

## Phase 09: Media Device Capability Inventory

**Purpose:** Stop showing invalid camera controls by reading actual device capabilities.

- [x] Extend `apps/rain/lib/application/runtime/media_device_settings.dart` to model video inputs, not only microphones.
- [x] Add a capability result that includes:
  - available video input count.
  - selected video input id.
  - labels when permission allows.
  - whether camera switching is supported.
  - whether a rear-facing camera is likely available.
- [x] Keep behavior permission-safe:
  - If labels are unavailable before permission, do not assume rear camera exists.
  - If only one video input exists, disable or hide flip-camera.
  - On Windows laptop, default to no flip-camera unless multiple cameras are detected.
- [x] Add tests for:
  - no camera.
  - one Windows laptop camera.
  - two Android cameras with front/rear labels.
  - labels hidden before permission.
- [x] Acceptance:
  - Laptop without rear camera does not show a flip-camera button.
- [x] Commit with message: `feat: model video device capabilities`.

## Phase 10: Dynamic Video Controls And Camera Selection

**Purpose:** Wire camera capability data into the call runtime and video UI.

- [x] Update video call start to use selected video input when available.
- [x] Avoid hardcoded front-camera assumptions in `packages/peer_core/lib/src/call/call_media_connection.dart` where platform support allows device id selection.
- [x] Update `VoiceCallState` or a companion provider so UI capabilities are dynamic.
- [x] Hide or disable switch-camera control based on capability.
- [x] If switch-camera is tapped after a capability change, fail gracefully with a user-facing message instead of throwing.
- [x] Add tests:
  - switch-camera capability absent on single camera.
  - switch-camera visible on multi-camera Android inventory.
  - selected camera device id is passed into media constraints.
  - switching failure does not end the call unless media is actually lost.
- [x] Acceptance:
  - Windows laptop shows only supported video controls.
  - Android multi-camera device keeps flip-camera available.
- [x] Commit with message: `feat: use dynamic video camera controls`.

## Phase 11: Integrated Voice And Video Runtime Gate

**Purpose:** Verify the fixed state machine across the exact scenarios that failed.

- [x] Add or extend fake/emulator tests for:
  - PC to phone voice call first attempt.
  - PC to phone video call first attempt.
  - phone to computer video call first attempt.
  - failed video setup releases call state on both peers.
  - app close from either peer ends the other peer's call state.
  - disconnect then reconnect on Android.
  - retry does not reverse caller/callee direction.
- [x] Ensure tests assert Firebase room status, active pair lock state, local runtime phase, and UI-visible phase.
- [x] Keep tests deterministic by using fake clocks and fake device inventories.
- [x] Commit with message: `test: cover call runtime failure recovery`.

## Phase 12: Automated Validation Gate

**Purpose:** Run the normal repo gate after all runtime and UI changes are committed.

- [x] Run:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

- [x] Fix any failures in the owning phase area only.
  - No validation failures were found.
- [x] Re-run failing commands until green.
  - No targeted re-run was needed because the first full gate was green.
- [x] Commit validation gate result with message: `docs: complete automated validation gate`.

## Phase 13: Manual Device Gate

**Purpose:** Prove this works on the devices that exposed the failures.

- [ ] Build only after Phase 12 passes or the user explicitly requests an earlier build.
- [ ] Test Android phone A to Android phone B:
  - voice call.
  - video call.
  - hangup both directions.
  - app close both directions.
  - disconnect then reconnect.
- [ ] Test Windows to Android:
  - Windows starts voice.
  - Android starts voice.
  - Windows starts video.
  - Android starts video.
  - Windows app survives Android media failure.
  - Android clears state after Windows close.
- [ ] Test laptop camera controls:
  - no rear-camera flip icon on single-camera laptop.
  - multi-camera Android still shows flip control.
- [ ] Test startup:
  - cold start never shows bottom navigation during splash loading.
- [ ] Record results in the QA audit doc.
- [ ] Commit with message: `docs: record call stability device gate`.

## Phase 14: Final Release Gate

**Purpose:** Ship only after the runtime, UI, and manual paths agree.

- [ ] Confirm `git status` contains only expected changes.
- [ ] Confirm every phase has a commit.
- [ ] Push the branch.
- [ ] Open PR with:
  - root causes fixed.
  - tests added.
  - manual device matrix.
  - known residual risks, if any.
- [ ] Trigger cloud build workflow only after PR branch is pushed and validation is green.
- [ ] Do not merge until the user approves the tested artifacts.
