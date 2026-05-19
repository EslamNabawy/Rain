# Rain Connection Command System v4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a truthful, cancel-safe connection command system that lets Rain choose or manually force WebRTC/Iroh routes after an explicit Connect press, with bounded retries, exact failures, and a strong mobile status UI.

**Architecture:** Add a dedicated `ConnectionCommandOrchestrator` above the existing `SessionManager` stack. Keep `ConnectionsController` as the Riverpod/UI adapter, keep `RainRuntimeController` as runtime/app policy owner, and keep WebRTC/Iroh managers as transport executors. All connection timelines, route policies, cancel tokens, retry budgets, and fallback prompts live in the orchestrator layer and are memory-only.

**Tech Stack:** Flutter, Riverpod Notifier, Freezed-style immutable state already used by the app, `protocol_brain` WebRTC staged ICE, current Rain Iroh fallback bridge, Firebase signaling/presence, existing test stack.

---

## Design Rules

- Auto mode means automatic route selection only after the user presses `Connect`.
- Never auto-connect from app startup, presence, chat open, refresh, send, resend, file transfer, or cached offline queue flush.
- `Delivered` and file completion remain ACK-driven only. Connection success never upgrades message/file status by itself.
- Cancellation must dispose the active transport before the UI says canceled.
- Manual mode may ask for fallback once per connect attempt. If that fallback also fails, no second modal.
- The 90 second global budget beats per-layer timeout math. If the budget expires mid-layer, abort that layer immediately.
- Iroh direct/relay forcing is not exposed until the Rust bridge supports it explicitly. UI can show Iroh route diagnostics after connection, read-only.
- Do not touch `main` during implementation. Work stays on `dev` until CI and manual smoke are clean.

---

## File Structure

Create focused command-system files:

- Create `apps/rain/lib/application/connection_command/connection_command_models.dart`
  - Owns public enums and immutable models: mode, layer, step state, failure code, policy, step, timeline, cancel reason.
- Create `apps/rain/lib/application/connection_command/connection_timeouts.dart`
  - Central timeout and retry jitter defaults.
- Create `apps/rain/lib/application/connection_command/connection_failure_messages.dart`
  - Maps failure codes/layers to stable user messages and advanced technical details.
- Create `apps/rain/lib/application/connection_command/connection_run_token.dart`
  - Per-attempt cancellation/generation guard.
- Create `apps/rain/lib/application/connection_command/connection_command_orchestrator.dart`
  - Owns policy memory, timeline stream, global budget, retries, fallback gating, cancellation, and delegation to runtime/session managers.
- Create `apps/rain/lib/application/connection_command/fake_connection_transport.dart`
  - Test-only fake transport surface for deterministic route/failure/cancel tests.

Modify existing app state/UI files:

- Modify `apps/rain/lib/application/state/app_providers.dart`
  - Keep `ConnectionsController` thin: calls orchestrator, subscribes to timelines, updates `PeerConnectionView`.
- Modify `apps/rain/lib/application/state/connection_diagnostics.dart`
  - Merge route diagnostics with command timeline/failure state.
- Modify `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
  - Expose only the runtime methods the orchestrator needs; preserve manual connection rules.
- Modify `apps/rain/lib/presentation/screens/home_screen.dart`
  - Replace old status dialog with Command Center UI.
- Modify `apps/rain/lib/application/transport/fallback_session_manager.dart`
  - Add generation/cancel-safe connect/disconnect hooks. Do not decide UI policy here.
- Modify `apps/rain/lib/infrastructure/iroh/iroh_session_manager.dart`
  - Add generation guard for native events and clean cancel/disconnect semantics.
- Modify `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
  - Ensure WebRTC stale attempt guards and `disconnect`/cancel disposal are strong enough for orchestration.

Test files:

- Create `apps/rain/test/connection_command_models_test.dart`
- Create `apps/rain/test/connection_command_orchestrator_test.dart`
- Create `apps/rain/test/connection_command_cancel_test.dart`
- Create `apps/rain/test/connection_command_ui_test.dart`
- Extend existing `apps/rain/test/fallback_session_manager_test.dart`
- Extend existing `apps/rain/test/iroh_session_manager_test.dart`
- Extend existing `packages/protocol_brain/test/session_manager_contract_test.dart`

---

## Task 1: Add Command Models

**Files:**
- Create: `apps/rain/lib/application/connection_command/connection_command_models.dart`
- Test: `apps/rain/test/connection_command_models_test.dart`

- [ ] **Step 1: Write model tests**

Test that:
- `ConnectionTimeline` caps visible steps at 24.
- Adding a step returns a new timeline object.
- Session policy defaults are Auto + ask-before-fallback + not remembered.
- `fallbackPromptAlreadyShown` prevents a second fallback prompt.
- `ConnectionMode.irohFallback` has no direct/relay subtype.

Run:

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/connection_command_models_test.dart
```

Expected before implementation: fail because command models do not exist.

- [ ] **Step 2: Implement command enums**

Define:
- `ConnectionMode { auto, webRtcAuto, webRtcDirectOnly, webRtcRelayOnly, irohFallback }`
- `ConnectionLayer { preflight, webRtcDirect, webRtcPrimaryRelay, webRtcBackupRelay, webRtcFullRestart, iroh }`
- `ConnectionStepState { pending, running, retrying, succeeded, failed, skipped, canceled }`
- `ConnectionFailureCode { peerOffline, notFriends, blocked, networkOffline, backendUnavailable, signalingPermissionDenied, staleRoomCleanupFailed, directPathBlocked, turnCredentialsUnavailable, turnProviderTimedOut, dataChannelTimeout, irohAddressTimeout, irohHandshakeRejected, irohConnectFailed, globalBudgetExceeded, userCanceled, unknown }`
- `ConnectionCancelReason { userCanceled, disconnect, logout, networkLost, appShutdown, supersededAttempt, globalBudgetExceeded }`

- [ ] **Step 3: Implement immutable model classes**

Implement plain immutable Dart classes first unless existing app generation patterns make Freezed cheaper. Required behavior:
- All fields are `final`.
- Every class has `copyWith`.
- `ConnectionTimeline.addStep(...)` returns a new timeline.
- Visible steps are capped at 24 by dropping the oldest visible step.
- Full diagnostic history can be kept in memory but must not render unbounded lists.

- [ ] **Step 4: Run model tests**

Run:

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/connection_command_models_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/connection_command/connection_command_models.dart apps/rain/test/connection_command_models_test.dart
git commit -m "feat: add connection command models"
```

---

## Task 2: Centralize Timeouts and Failure Messages

**Files:**
- Create: `apps/rain/lib/application/connection_command/connection_timeouts.dart`
- Create: `apps/rain/lib/application/connection_command/connection_failure_messages.dart`
- Test: `apps/rain/test/connection_command_models_test.dart`

- [ ] **Step 1: Add timeout tests**

Test that:
- WebRTC direct timeout is 12 seconds.
- Primary relay timeout is 30 seconds.
- Backup relay timeout is 20 seconds.
- Full restart timeout is 25 seconds.
- Iroh timeout is 25 seconds.
- Global budget is 90 seconds.
- Retry delay range is 1200-1800 ms.
- Step defaults sum above 90 seconds and the test documents that this is intentional.

- [ ] **Step 2: Implement `ConnectionTimeouts`**

Add a single class with:
- `webRtcDirect = 12s`
- `webRtcPrimaryRelay = 30s`
- `webRtcBackupRelay = 20s`
- `webRtcFullRestart = 25s`
- `iroh = 25s`
- `globalBudget = 90s`
- `retryBaseDelay = 1200ms`
- `retryMaxJitter = 600ms`

- [ ] **Step 3: Add failure-message tests**

Test exact user-facing messages:
- `directPathBlocked` -> `Direct path blocked.`
- `turnCredentialsUnavailable` -> `Relay credentials unavailable.`
- `turnProviderTimedOut` -> `Relay provider timed out.`
- `dataChannelTimeout` -> `Data channel did not open.`
- `irohAddressTimeout` -> `Iroh address exchange timed out.`
- `irohHandshakeRejected` -> `Iroh handshake rejected.`
- `globalBudgetExceeded` -> `All connection routes timed out.`
- `userCanceled` -> `Connection canceled.`

- [ ] **Step 4: Implement stable message mapping**

Messages must be short and non-technical. Technical details are a separate optional string used only in Advanced Diagnostics.

- [ ] **Step 5: Run tests**

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/connection_command_models_test.dart
```

Expected: pass.

- [ ] **Step 6: Commit**

```powershell
git add apps/rain/lib/application/connection_command/connection_timeouts.dart apps/rain/lib/application/connection_command/connection_failure_messages.dart apps/rain/test/connection_command_models_test.dart
git commit -m "feat: centralize connection command timeouts"
```

---

## Task 3: Add Run Tokens and Ghost-Event Guards

**Files:**
- Create: `apps/rain/lib/application/connection_command/connection_run_token.dart`
- Test: `apps/rain/test/connection_command_cancel_test.dart`

- [ ] **Step 1: Write cancel-token tests**

Test that:
- A fresh token is active.
- `cancel(reason)` marks it canceled and stores the reason.
- `matches(peerId, runId, generation)` rejects old generations.
- A callback using an old token drops events after cancellation.
- A new connect attempt gets a new token and generation.

- [ ] **Step 2: Implement `ConnectionRunToken`**

The token must include:
- `peerId`
- `runId`
- `generation`
- `startedAt`
- `isCanceled`
- `cancelReason`

Add methods:
- `cancel(ConnectionCancelReason reason)`
- `bool isActiveFor(String peerId, String runId, int generation)`
- `void throwIfCanceled()`

- [ ] **Step 3: Run cancel-token tests**

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/connection_command_cancel_test.dart
```

Expected: pass.

- [ ] **Step 4: Commit**

```powershell
git add apps/rain/lib/application/connection_command/connection_run_token.dart apps/rain/test/connection_command_cancel_test.dart
git commit -m "feat: add connection run cancellation tokens"
```

---

## Task 4: Build the Orchestrator Skeleton

**Files:**
- Create: `apps/rain/lib/application/connection_command/connection_command_orchestrator.dart`
- Create: `apps/rain/lib/application/connection_command/fake_connection_transport.dart`
- Test: `apps/rain/test/connection_command_orchestrator_test.dart`

- [ ] **Step 1: Write orchestrator skeleton tests**

Test that:
- `connect(peer)` emits preflight pending/running.
- Calling `connect(peer)` while the same peer is already connecting is ignored or returns the existing run.
- `timelineStream(peer)` emits new immutable timeline instances.
- `rememberPolicyForSession(peer, policy)` is memory-only.
- `clearSessionPolicy(peer)` resets the peer to default Auto policy.

- [ ] **Step 2: Define orchestrator interface**

Expose:
- `Future<void> connect(String peerId, {ConnectionPolicy? policy})`
- `Future<void> retry(String peerId, {ConnectionPolicy? overridePolicy})`
- `Future<void> cancel(String peerId, {ConnectionCancelReason reason = ConnectionCancelReason.userCanceled})`
- `Future<void> disconnect(String peerId)`
- `void rememberPolicyForSession(String peerId, ConnectionPolicy policy)`
- `void clearSessionPolicy(String peerId)`
- `Stream<ConnectionTimeline> timelineStream(String peerId)`
- `ConnectionTimeline? currentTimeline(String peerId)`

- [ ] **Step 3: Implement memory-only policy and timeline state**

Use in-memory maps keyed by peer id:
- `_sessionPolicies`
- `_timelines`
- `_timelineControllers`
- `_activeRuns`

Never write these maps to shared preferences, database, Drift, Firebase, or files.

- [ ] **Step 4: Run orchestrator skeleton tests**

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/connection_command_orchestrator_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/connection_command apps/rain/test/connection_command_orchestrator_test.dart
git commit -m "feat: add connection command orchestrator skeleton"
```

---

## Task 5: Implement Auto Layer Sequence and Global Budget

**Files:**
- Modify: `apps/rain/lib/application/connection_command/connection_command_orchestrator.dart`
- Modify: `apps/rain/lib/application/connection_command/fake_connection_transport.dart`
- Test: `apps/rain/test/connection_command_orchestrator_test.dart`

- [ ] **Step 1: Write sequence tests**

Test exact Auto order:
1. `preflight`
2. `webRtcDirect`
3. `webRtcPrimaryRelay`
4. `webRtcBackupRelay`
5. `webRtcFullRestart`
6. `iroh`

Test `webRtcAuto` excludes Iroh.
Test `webRtcDirectOnly` runs only preflight + direct.
Test `webRtcRelayOnly` runs preflight + relay layers only.
Test `irohFallback` runs preflight + Iroh only.

- [ ] **Step 2: Write global budget test**

Use fake timers or injected clock. Simulate slow failures where total per-step timeout would reach 112 seconds. Assert the orchestrator emits `globalBudgetExceeded` at 90 seconds and cancels the active layer.

- [ ] **Step 3: Implement layer plan generation**

Implement a pure function:
- `List<ConnectionLayer> layersForPolicy(ConnectionPolicy policy)`

This function must be unit tested and must not inspect network state.

- [ ] **Step 4: Implement budget timer**

The global timer starts immediately when `connect()` starts. On fire:
- cancel the active run with `ConnectionCancelReason.globalBudgetExceeded`
- mark active step failed with `globalBudgetExceeded`
- set `globalBudgetExceeded = true` on timeline
- prevent fallback prompt
- prevent further layer execution

- [ ] **Step 5: Run tests**

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/connection_command_orchestrator_test.dart
```

Expected: pass.

- [ ] **Step 6: Commit**

```powershell
git add apps/rain/lib/application/connection_command apps/rain/test/connection_command_orchestrator_test.dart
git commit -m "feat: add bounded connection command sequencing"
```

---

## Task 6: Implement Retry Rules with Jitter

**Files:**
- Modify: `apps/rain/lib/application/connection_command/connection_command_orchestrator.dart`
- Test: `apps/rain/test/connection_command_orchestrator_test.dart`

- [ ] **Step 1: Write retry tests**

Test that retryable failures retry the same layer once after 1200-1800 ms:
- `staleRoomCleanupFailed`
- glare/simultaneous connect represented as `staleRoomCleanupFailed` unless a more specific code already exists
- transient backend disconnect represented as `backendUnavailable`
- route detection timeout represented as `dataChannelTimeout`

Test non-retryable failures advance immediately:
- `peerOffline`
- `notFriends`
- `blocked`
- `turnCredentialsUnavailable`
- `signalingPermissionDenied`
- `irohHandshakeRejected`
- `userCanceled`
- `globalBudgetExceeded`

- [ ] **Step 2: Implement retry classification**

Implement:
- `bool isRetryable(ConnectionFailureCode code)`
- `Duration retryDelay(Random random)`

Delay must be `1200ms + random(0..600ms)`.

- [ ] **Step 3: Implement retry timeline states**

On retry:
- current step state becomes `retrying`
- `retryCount` increments
- after jitter, same layer becomes `running` again
- if retry fails, advance to next layer or final failure

- [ ] **Step 4: Run tests**

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/connection_command_orchestrator_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/connection_command/connection_command_orchestrator.dart apps/rain/test/connection_command_orchestrator_test.dart
git commit -m "feat: add connection retry policy"
```

---

## Task 7: Implement Manual Fallback Prompt Contract

**Files:**
- Modify: `apps/rain/lib/application/connection_command/connection_command_models.dart`
- Modify: `apps/rain/lib/application/connection_command/connection_command_orchestrator.dart`
- Modify: `apps/rain/lib/application/state/app_providers.dart`
- Test: `apps/rain/test/connection_command_orchestrator_test.dart`

- [ ] **Step 1: Write fallback prompt tests**

Test that:
- Manual direct failure emits one fallback request.
- Prompt choices are Auto, Relay, Iroh, Cancel.
- Choosing fallback sets `fallbackPromptAlreadyShown = true`.
- If selected fallback fails, no second fallback request is emitted.
- If `rememberForSession = true`, next connection for the same peer uses that policy.
- Logout/provider disposal clears remembered choices.

- [ ] **Step 2: Add fallback prompt state**

Add an orchestrator stream or callback for pending UI decisions. The orchestrator must pause the run while waiting for a choice and must keep the global budget active.

- [ ] **Step 3: Implement prompt result handling**

Rules:
- `Try Auto` restarts remaining run with Auto policy.
- `Try Relay` uses WebRTC relay-only policy.
- `Try Iroh` uses Iroh fallback policy.
- `Cancel` cancels current run.
- If the global budget expires while the prompt is open, close the prompt and fail with `globalBudgetExceeded`.

- [ ] **Step 4: Run tests**

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/connection_command_orchestrator_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/connection_command apps/rain/lib/application/state/app_providers.dart apps/rain/test/connection_command_orchestrator_test.dart
git commit -m "feat: add manual connection fallback policy"
```

---

## Task 8: Integrate WebRTC Transport Execution

**Files:**
- Modify: `apps/rain/lib/application/connection_command/connection_command_orchestrator.dart`
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Modify: `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
- Test: `packages/protocol_brain/test/session_manager_contract_test.dart`
- Test: `apps/rain/test/connection_command_orchestrator_test.dart`

- [ ] **Step 1: Write WebRTC integration tests**

Test that:
- WebRTC direct stage calls the existing direct/STUN-first path.
- Relay stages require relay credentials and fail with `turnCredentialsUnavailable` if unavailable.
- Fresh Connect deletes stale room data before creating a new offer.
- Stale offers/answers/ICE with older `connectAttemptId` are ignored.
- Disconnect/cancel sets `shouldReconnect = false`.

- [ ] **Step 2: Add a narrow transport interface**

The orchestrator should depend on a small interface, not directly on UI or full runtime internals:
- `Future<ConnectionLayerResult> runWebRtcLayer(peerId, layer, token, timeout)`
- `Future<void> cancelWebRtc(peerId, token)`
- `Future<void> disconnectPeer(peerId)`

Implement it using `RainRuntimeController` and existing `protocol_brain`.

- [ ] **Step 3: Strengthen stale event guards**

In WebRTC/protocol brain paths, ensure every late callback checks:
- active session still matches peer
- current attempt id matches
- current stage matches when applicable
- active run token is not canceled

- [ ] **Step 4: Run focused tests**

```powershell
cd "D:\old project\Rain"
flutter test packages/protocol_brain
cd "D:\old project\Rain\apps\rain"
flutter test test/connection_command_orchestrator_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/connection_command apps/rain/lib/application/runtime/rain_runtime_controller.dart packages/protocol_brain/lib/src/protocol_brain_impl.dart packages/protocol_brain/test/session_manager_contract_test.dart apps/rain/test/connection_command_orchestrator_test.dart
git commit -m "feat: wire web rtc into connection command system"
```

---

## Task 9: Integrate Iroh Fallback Safely

**Files:**
- Modify: `apps/rain/lib/application/connection_command/connection_command_orchestrator.dart`
- Modify: `apps/rain/lib/application/transport/fallback_session_manager.dart`
- Modify: `apps/rain/lib/infrastructure/iroh/iroh_session_manager.dart`
- Test: `apps/rain/test/fallback_session_manager_test.dart`
- Test: `apps/rain/test/iroh_session_manager_test.dart`
- Test: `apps/rain/test/connection_command_orchestrator_test.dart`

- [ ] **Step 1: Write Iroh command tests**

Test that:
- Auto reaches Iroh only after WebRTC layers fail.
- Manual Iroh does not silently run WebRTC.
- Iroh address timeout maps to `irohAddressTimeout`.
- Iroh rejected handshake maps to `irohHandshakeRejected`.
- Iroh connect failure maps to `irohConnectFailed`.
- Iroh events from old generations are ignored.

- [ ] **Step 2: Add generation guard to Iroh manager**

Every Iroh session/event must carry enough identity to reject stale events:
- peer id
- connect attempt id
- local generation/run id where available

If the Rust bridge does not expose all fields, guard in Dart before forwarding events to app state.

- [ ] **Step 3: Handle Iroh cancel/disconnect**

On cancel:
- call existing bridge disconnect for the peer
- remove open channels
- remove session entry
- emit no connected/disconnected event from stale native callbacks after cancel resolves

Only move Iroh to a background isolate if profiling or manual smoke shows UI jank. If not needed, keep the current bridge and generation guards.

- [ ] **Step 4: Run focused tests**

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/fallback_session_manager_test.dart test/iroh_session_manager_test.dart test/connection_command_orchestrator_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/connection_command apps/rain/lib/application/transport/fallback_session_manager.dart apps/rain/lib/infrastructure/iroh/iroh_session_manager.dart apps/rain/test/fallback_session_manager_test.dart apps/rain/test/iroh_session_manager_test.dart apps/rain/test/connection_command_orchestrator_test.dart
git commit -m "feat: wire iroh into connection command system"
```

---

## Task 10: Implement Full Cancellation Semantics

**Files:**
- Modify: `apps/rain/lib/application/connection_command/connection_command_orchestrator.dart`
- Modify: `apps/rain/lib/application/transport/fallback_session_manager.dart`
- Modify: `apps/rain/lib/infrastructure/iroh/iroh_session_manager.dart`
- Modify: `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
- Test: `apps/rain/test/connection_command_cancel_test.dart`

- [ ] **Step 1: Write cancellation tests**

Test that:
- `cancel()` disposes WebRTC before emitting canceled timeline.
- `cancel()` disconnects Iroh before emitting canceled timeline.
- ICE candidate after cancel is dropped.
- ICE state change after cancel is dropped.
- Iroh native event after cancel is dropped.
- New connect after cancel gets a fresh token/generation.
- Spam Connect/Cancel 10 times leaves no active runs.

- [ ] **Step 2: Implement cancel ordering**

Correct order:
1. mark run token canceled
2. cancel global budget timer
3. cancel retry timer
4. close fallback prompt if open
5. dispose active transport
6. delete/leave stale signaling room if WebRTC layer was active
7. mark timeline canceled or failed
8. emit final timeline

- [ ] **Step 3: Ensure disconnect is stronger than cancel**

`disconnect(peer)` must:
- cancel any active connect run
- set manual disconnected intent
- disable reconnect
- fail active file transfers with `Connection lost. Transfer canceled.`
- clear active timeline controls
- dispose both WebRTC and Iroh handles for that peer

- [ ] **Step 4: Run cancel tests**

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/connection_command_cancel_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/connection_command apps/rain/lib/application/transport/fallback_session_manager.dart apps/rain/lib/infrastructure/iroh/iroh_session_manager.dart packages/protocol_brain/lib/src/protocol_brain_impl.dart apps/rain/test/connection_command_cancel_test.dart
git commit -m "fix: make connection cancellation transport-safe"
```

---

## Task 11: Make `ConnectionsController` a Thin Adapter

**Files:**
- Modify: `apps/rain/lib/application/state/app_providers.dart`
- Modify: `apps/rain/lib/application/state/app_state.dart`
- Test: `apps/rain/test/app_providers_iroh_test.dart`
- Test: `apps/rain/test/connection_command_orchestrator_test.dart`

- [ ] **Step 1: Write adapter tests**

Test that:
- UI `connect(peer)` delegates to orchestrator.
- UI `cancel(peer)` delegates to orchestrator.
- UI `disconnect(peer)` delegates to orchestrator/runtime disconnect.
- Timeline updates update `PeerConnectionView.manualIntent`.
- No policy/timeline state is persisted by `ConnectionsController`.

- [ ] **Step 2: Move policy/timeline maps out of `ConnectionsController`**

`ConnectionsController` should keep only UI-facing state:
- current connection views
- action busy flags
- selected peer state already owned by app

It must not own retry decisions, fallback rules, timers, or route sequencing.

- [ ] **Step 3: Expose provider for orchestrator**

Add a Riverpod provider that constructs `ConnectionCommandOrchestrator` from existing runtime/session dependencies.

- [ ] **Step 4: Run adapter tests**

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/app_providers_iroh_test.dart test/connection_command_orchestrator_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/state/app_providers.dart apps/rain/lib/application/state/app_state.dart apps/rain/test/app_providers_iroh_test.dart apps/rain/test/connection_command_orchestrator_test.dart
git commit -m "refactor: make connections controller use command orchestrator"
```

---

## Task 12: Upgrade Diagnostics and Command Center UI

**Files:**
- Modify: `apps/rain/lib/application/state/connection_diagnostics.dart`
- Modify: `apps/rain/lib/presentation/screens/home_screen.dart`
- Test: `apps/rain/test/connection_command_ui_test.dart`

- [ ] **Step 1: Write widget tests**

Test that:
- Chat header has exactly one status pill.
- Chat header has exactly one action button.
- Status pill opens centered Command Center.
- Command Center has Overview, Mode Selector, Timeline, Controls, Advanced Diagnostics.
- Action buttons remain visible when content overflows.
- Advanced Diagnostics does not overflow on mobile.
- Iroh selector shows `Iroh Fallback`, not `Iroh Direct` or `Iroh Relay`.

- [ ] **Step 2: Build status pill states**

Labels:
- `Ready`
- `Connecting`
- `Direct`
- `Relay`
- `Iroh`
- `Recovering`
- `Failed`
- `Disconnected`

No duplicate second status bar.

- [ ] **Step 3: Build Command Center**

Sections:
- Overview: current mode, active transport, route, last failure.
- Mode Selector: Auto, WebRTC Auto, WebRTC Direct, WebRTC Relay, Iroh Fallback.
- Timeline: newest attempt visible first, max 24 visible rows.
- Controls: Connect, Retry, Cancel, Disconnect, Test Relay.
- Advanced Diagnostics: collapsed by default, renders `Unknown` for unavailable values.

- [ ] **Step 4: Implement fallback prompt UI**

Centered prompt with:
- failed route
- precise reason
- buttons: Try Auto, Try Relay, Try Iroh, Cancel
- checkbox: Remember this choice for this session

Prompt must not reappear if `fallbackPromptAlreadyShown` is true.

- [ ] **Step 5: Run widget tests**

```powershell
cd "D:\old project\Rain\apps\rain"
flutter test test/connection_command_ui_test.dart
```

Expected: pass.

- [ ] **Step 6: Commit**

```powershell
git add apps/rain/lib/application/state/connection_diagnostics.dart apps/rain/lib/presentation/screens/home_screen.dart apps/rain/test/connection_command_ui_test.dart
git commit -m "feat: add connection command center"
```

---

## Task 13: Preserve Message and File Truth

**Files:**
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Modify: `packages/rain_core/lib/messages/message_delivery_service.dart`
- Test: existing message/file transfer tests in `apps/rain/test` and `packages/rain_core/test`

- [ ] **Step 1: Write regression tests**

Test that:
- Connected session does not mark queued messages delivered.
- Delivered requires peer ACK.
- File complete requires receiver ACK.
- Disconnect/cancel during file transfer fails transfer with `Connection lost. Transfer canceled.`
- Manual reconnect does not auto-flush file transfer unless the user starts or resumes a supported action.

- [ ] **Step 2: Audit delivery state transitions**

Find every path that sets:
- message delivered
- file completed
- file received

Each path must prove it is responding to a real peer ACK or validated file received ACK.

- [ ] **Step 3: Run delivery tests**

```powershell
cd "D:\old project\Rain"
flutter test packages/rain_core
cd "D:\old project\Rain\apps\rain"
flutter test test/iroh_file_transfer_test.dart test/iroh_message_delivery_test.dart
```

Expected: pass.

- [ ] **Step 4: Commit**

```powershell
git add apps/rain/lib/application/runtime/rain_runtime_controller.dart packages/rain_core/lib/messages/message_delivery_service.dart apps/rain/test packages/rain_core/test
git commit -m "test: preserve delivery ack truth"
```

---

## Task 14: Full Verification and CI Prep

**Files:**
- No planned production edits unless verification exposes failures.

- [ ] **Step 1: Run package tests**

```powershell
cd "D:\old project\Rain"
flutter test packages/peer_core
flutter test packages/protocol_brain
flutter test packages/rain_core
cd "D:\old project\Rain\apps\rain"
flutter test
```

Expected: all pass.

- [ ] **Step 2: Run analysis**

```powershell
cd "D:\old project\Rain"
flutter analyze packages/peer_core
flutter analyze packages/protocol_brain
flutter analyze packages/rain_core
cd "D:\old project\Rain\apps\rain"
flutter analyze
```

Expected: no errors.

- [ ] **Step 3: Run native checks**

```powershell
cd "D:\old project\Rain"
cargo test --manifest-path apps/rain/rust/Cargo.toml
cd "D:\old project\Rain\apps\rain"
flutter build windows --release
flutter build apk --debug
```

Expected:
- Rust tests pass.
- Windows release builds.
- Android debug APK builds.

- [ ] **Step 4: Manual smoke**

Test on Android + Windows:
- Same Wi-Fi Auto: should show Direct or truthfully show Relay/Iroh if that is selected.
- Different Wi-Fi/mobile data: should progress through timeline instead of hanging silently.
- VPN blocked case: should show exact failed layer and reason.
- Manual Direct: must not silently fall back.
- Manual Relay: must not silently use direct.
- Manual Iroh: must not silently use WebRTC.
- Cancel during each layer: no ghost connection appears later.
- Spam Connect/Cancel 10 times: no stuck `Connecting`.
- Message delivery: no fake Delivered.
- File transfer: no fake Completed or missing received file after ACK.

- [ ] **Step 5: Commit final fixes if needed**

Only commit targeted verification fixes. Do not commit `.idea`, local dart defines, generated build artifacts, or unrelated files.

---

## Task 15: CI/CD Run on Dev

**Files:**
- No planned edits unless CI exposes a real issue.

- [ ] **Step 1: Push dev**

```powershell
cd "D:\old project\Rain"
git push origin dev
```

- [ ] **Step 2: Run CI/CD workflow on dev**

Use the GitHub workflow already configured for Rain builds. Required outputs:
- app/package analyze and tests pass
- Android ARM v7 APK
- Android ARM v8/v9 APK
- Windows portable artifact
- no universal APK in normal release output unless explicitly enabled for emulator/test builds

- [ ] **Step 3: Inspect workflow artifacts**

Verify artifact names match current release convention and are not nested duplicate archives.

- [ ] **Step 4: Record result**

If CI passes, summarize:
- commit SHA
- workflow run URL
- artifact names
- any warnings that remain

If CI fails, fix on `dev`, rerun, and do not touch `main`.

---

## Acceptance Criteria

- Pressing Connect in Auto shows a timeline that visibly advances through layers or succeeds.
- Mobile data/VPN failures no longer look stuck; the app shows which layer failed and why.
- Manual selection can force WebRTC Direct, WebRTC Relay, or Iroh Fallback.
- Manual fallback prompt appears at most once per connect attempt.
- Cancel disposes active WebRTC/Iroh handles before UI says canceled.
- No stale ICE/Iroh events can resurrect a canceled connection.
- Connection success does not create fake message/file delivery.
- Command Center works on mobile without overflow and has sticky controls.
- All tests and analysis pass locally and in CI on `dev`.

---

## Implementation Notes

- Prefer plain immutable Dart classes if this avoids codegen churn. Use Freezed only if the existing app generation workflow is already stable for these new files.
- Keep orchestration above transports. Do not push UI policy into `protocol_brain`, `FallbackSessionManager`, or `IrohSessionManager`.
- Keep transport managers dumb: connect, disconnect, emit state, expose diagnostics.
- Keep `ConnectionsController` dumb: adapt orchestrator streams to UI state.
- Keep all remembered policy memory-only. It must disappear on logout, app restart, provider disposal, or runtime replacement.
- Do not create a new background service.
- Do not implement resumable file transfer in this plan.
- Do not force Iroh direct/relay modes until the Rust bridge exposes those controls safely.
- Do not merge to `main` until the hard CI gate and manual smoke pass.
