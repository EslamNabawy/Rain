# App Exit And Floating Call UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Rain close cleanly on normal desktop/mobile close paths, make incoming call actions visible and tappable on every supported size, and turn the call popup into a movable floating surface.

**Architecture:** Add one app-exit coordinator that desktop window close and runtime providers can share, then make runtime shutdown idempotent, bounded, and observable. Extend the existing `CallSurfaceState` instead of creating a second call UI state system, and move call controls into a sticky safe-area dock so Answer/Decline never depend on scroll position.

**Tech Stack:** Flutter, Riverpod Notifier/AsyncNotifier, `window_manager`, existing WebRTC runtime, existing Rain call widgets, `flutter_test`.

---

## Acceptance Contract

- Normal Windows close via window X or Alt+F4 waits for Rain runtime cleanup before destroying the window.
- Android lifecycle detach invokes the same runtime shutdown path; force-kill cannot run Dart cleanup, so stale remote state must still be handled by existing heartbeat/expiry cleanup.
- Runtime shutdown is idempotent and bounded: a second close request returns the same shutdown future and no reconnect/recovery starts after shutdown begins.
- Active calls, ringing calls, media renderers, ringtone/sound loops, peer sessions, Firebase call locks, timers, and subscriptions are stopped or released during shutdown.
- Incoming voice/video Answer and Decline controls remain visible and tappable at 320x568, 360x640, 568x320, 768x1024, and desktop widths.
- The call popup is floating, draggable by its header, clamped inside visible safe bounds, and resets/clamps when the window size or orientation changes.
- Dragging the popup never blocks button taps, video preview taps, minimize, fullscreen, hangup, answer, or decline.

## File Map

- Create: `apps/rain/lib/application/runtime/app_exit_coordinator.dart`
  - Singleton coordinator for app-close handlers, idempotent close futures, timeout-bounded shutdown, and testable close results.
- Modify: `apps/rain/lib/application/state/runtime_providers.dart`
  - Register/unregister the active `RainRuntimeController` with the app-exit coordinator.
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
  - Expose a public bounded shutdown entrypoint for app close and make shutdown skip all recovery after `_shutDown` flips.
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
  - Ensure shutdown releases active Firebase call state and disposes media/renderers without leaving failed UI state behind.
- Modify: `apps/rain/lib/infrastructure/window/desktop_shell_controller.dart`
  - Intercept desktop close, run coordinator shutdown, then destroy the window.
- Modify: `apps/rain/lib/application/state/call_surface_providers.dart`
  - Add floating position state and pure movement/clamp methods.
- Create: `apps/rain/lib/application/state/call_surface_geometry.dart`
  - Pure helpers for safe-bounds calculation and offset clamping.
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
  - Render expanded calls as a floating `Positioned` panel with a drag handle/header.
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
  - Replace incoming `Wrap` controls with responsive full-width action controls and stable keys/semantics.
- Modify: `apps/rain/lib/presentation/screens/home_screen.dart`
  - Pass drag and viewport callbacks from UI to `CallSurfaceController`.
- Modify: `apps/rain/lib/application/audio/sound_event_router.dart`
  - Stop active ringtone/ringback/sound playback during app-exit cleanup if not already covered by provider disposal.
- Modify: `apps/rain/lib/application/state/sound_event_providers.dart`
  - Register sound cleanup with the app-exit coordinator.
- Test: `apps/rain/test/app_exit_coordinator_test.dart`
- Test: `apps/rain/test/runtime_startup_test.dart`
- Test: `apps/rain/test/call_surface_providers_test.dart`
- Test: `apps/rain/test/rain_chat_widgets_test.dart`

---

## Phase 00: Evidence Lock And Baseline

**Files:**
- Read: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Read: `apps/rain/lib/infrastructure/window/desktop_shell_controller.dart`
- Read: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- Read: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Read: `apps/rain/test/runtime_startup_test.dart`
- Read: `apps/rain/test/rain_chat_widgets_test.dart`

- [ ] Record the current shutdown chain:
  - `DesktopShellController.onWindowClose()` destroys the window directly.
  - `RainRuntimeController.didChangeAppLifecycleState(detached)` calls `_shutdown(...)`.
  - `RuntimeController.ref.onDispose` calls `controller.dispose()` without a desktop close barrier.
- [ ] Record the current call UI chain:
  - `CallSurfaceController` owns `managerOnly`, `expanded`, `fullscreen`, and `pip`.
  - `RainCallOverlay` centers `_RainExpandedCallPanel`.
  - Incoming call controls are a `Wrap` inside the same scrollable panel content.
- [ ] Commit no code in this phase unless a baseline note file is added.

## Phase 01: App Exit Coordinator

**Files:**
- Create: `apps/rain/lib/application/runtime/app_exit_coordinator.dart`
- Test: `apps/rain/test/app_exit_coordinator_test.dart`

- [ ] Write tests for idempotent shutdown:

```dart
test('app exit coordinator runs registered handlers once', () async {
  final coordinator = AppExitCoordinator(timeout: const Duration(seconds: 1));
  var calls = 0;
  final token = coordinator.register((reason) async {
    calls += 1;
    expect(reason, AppExitReason.windowClose);
  });

  final first = coordinator.shutdown(AppExitReason.windowClose);
  final second = coordinator.shutdown(AppExitReason.windowClose);

  await Future.wait(<Future<void>>[first, second]);
  expect(calls, 1);
  token.unregister();
});
```

- [ ] Write tests for unregister behavior:

```dart
test('unregistered handlers are not called during shutdown', () async {
  final coordinator = AppExitCoordinator(timeout: const Duration(seconds: 1));
  var calls = 0;
  final token = coordinator.register((_) async => calls += 1);
  token.unregister();

  await coordinator.shutdown(AppExitReason.windowClose);

  expect(calls, 0);
});
```

- [ ] Implement `AppExitReason`, `AppExitHandler`, `AppExitRegistration`, and `AppExitCoordinator`.

```dart
enum AppExitReason { windowClose, lifecycleDetached, providerDispose, logout }

typedef AppExitHandler = Future<void> Function(AppExitReason reason);

final class AppExitRegistration {
  AppExitRegistration(this._unregister);
  final void Function() _unregister;
  bool _active = true;

  void unregister() {
    if (!_active) return;
    _active = false;
    _unregister();
  }
}
```

- [ ] Add singleton access:

```dart
static final AppExitCoordinator instance = AppExitCoordinator();
```

- [ ] Make `shutdown()` snapshot handlers, run all of them, and apply the configured timeout.
- [ ] Run:

```powershell
dart test apps/rain/test/app_exit_coordinator_test.dart
```

- [ ] Commit:

```powershell
git add apps/rain/lib/application/runtime/app_exit_coordinator.dart apps/rain/test/app_exit_coordinator_test.dart
git commit -m "feat: add app exit coordinator"
```

## Phase 02: Runtime Shutdown Registration

**Files:**
- Modify: `apps/rain/lib/application/state/runtime_providers.dart`
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Test: `apps/rain/test/runtime_startup_test.dart`

- [ ] Add a public runtime close method that calls the existing shutdown path once:

```dart
Future<void> closeForAppExit(AppExitReason reason) async {
  await _shutdown(
    markOffline: true,
    signOut: false,
    clearLocalSession: false,
  );
}
```

- [ ] Ensure `_shutdown` stores and reuses an in-flight future, so repeated close/dispose calls do not race.
- [ ] Inside shutdown, keep `_shutDown = true` as the first state mutation before any awaited work.
- [ ] Ensure `_shutdown` calls the active call ending path with terminal signaling when possible, then disposes session/media/renderers even if signaling fails.
- [ ] In `runtime_providers.dart`, register the active runtime:

```dart
final exitRegistration = AppExitCoordinator.instance.register(
  controller.closeForAppExit,
);
ref.onDispose(() {
  exitRegistration.unregister();
  unawaited(controller.dispose());
});
```

- [ ] Add a runtime test that calls `closeForAppExit` twice and verifies presence is set offline once after startup online write.
- [ ] Add a runtime test that `handleNetworkAvailable` after `closeForAppExit` does not recover peer connections.
- [ ] Run:

```powershell
dart test apps/rain/test/runtime_startup_test.dart
```

- [ ] Commit:

```powershell
git add apps/rain/lib/application/state/runtime_providers.dart apps/rain/lib/application/runtime/rain_runtime_controller.dart apps/rain/lib/application/runtime/voice_call_runtime.dart apps/rain/test/runtime_startup_test.dart
git commit -m "fix: make runtime app exit shutdown idempotent"
```

## Phase 03: Desktop And Sound Close Binding

**Files:**
- Modify: `apps/rain/lib/infrastructure/window/desktop_shell_controller.dart`
- Modify: `apps/rain/lib/application/audio/sound_event_router.dart`
- Modify: `apps/rain/lib/application/state/sound_event_providers.dart`
- Test: `apps/rain/test/runtime_startup_test.dart`

- [ ] Change desktop close policy to prevent close while cleanup runs:

```dart
await windowManager.setPreventClose(true);
```

- [ ] In `onWindowClose`, call `AppExitCoordinator.instance.shutdown(AppExitReason.windowClose)` before `windowManager.destroy()`.
- [ ] Keep `_closing` so double close cannot run two shutdowns.
- [ ] After shutdown completes or times out, call:

```dart
await windowManager.setPreventClose(false);
await windowManager.destroy();
```

- [ ] Add `SoundEventRouter.stopAllForAppExit()` that stops ringtone, ringback, and currently playing one-shot players.
- [ ] Register the sound router with `AppExitCoordinator` in `sound_event_providers.dart`.
- [ ] Update the existing source-level desktop policy test to expect `setPreventClose(true)`, coordinator shutdown, and no tray/hide behavior.
- [ ] Run:

```powershell
dart test apps/rain/test/runtime_startup_test.dart
dart test apps/rain/test/sound_event_router_test.dart
```

- [ ] Commit:

```powershell
git add apps/rain/lib/infrastructure/window/desktop_shell_controller.dart apps/rain/lib/application/audio/sound_event_router.dart apps/rain/lib/application/state/sound_event_providers.dart apps/rain/test/runtime_startup_test.dart apps/rain/test/sound_event_router_test.dart
git commit -m "fix: await app cleanup before desktop close"
```

## Phase 04: Floating Surface Geometry Model

**Files:**
- Create: `apps/rain/lib/application/state/call_surface_geometry.dart`
- Modify: `apps/rain/lib/application/state/call_surface_providers.dart`
- Test: `apps/rain/test/call_surface_providers_test.dart`

- [ ] Add a pure `CallSurfaceBounds` helper:

```dart
final class CallSurfaceBounds {
  const CallSurfaceBounds({
    required this.viewportSize,
    required this.safePadding,
    required this.panelSize,
    this.margin = 12,
  });

  final Size viewportSize;
  final EdgeInsets safePadding;
  final Size panelSize;
  final double margin;
}
```

- [ ] Add `Offset clampCallSurfaceOffset(CallSurfaceBounds bounds, Offset offset)` and `Offset centeredCallSurfaceOffset(CallSurfaceBounds bounds)`.
- [ ] Extend `CallSurfaceState` with:

```dart
final Offset? floatingOffset;
final Size? lastViewportSize;
```

- [ ] Add controller methods:

```dart
void moveFloatingPanel({
  required Offset delta,
  required Size viewportSize,
  required EdgeInsets safePadding,
  required Size panelSize,
});

void recenterFloatingPanel({
  required Size viewportSize,
  required EdgeInsets safePadding,
  required Size panelSize,
});

void clampFloatingPanel({
  required Size viewportSize,
  required EdgeInsets safePadding,
  required Size panelSize,
});
```

- [ ] Reset `floatingOffset` when `callId` changes.
- [ ] Preserve `floatingOffset` when only `updatedAt`, mute, duration, or media flags change for the same call.
- [ ] Add tests for center, clamp, reset-on-new-call, preserve-on-same-call, and safe-area padding.
- [ ] Run:

```powershell
dart test apps/rain/test/call_surface_providers_test.dart
```

- [ ] Commit:

```powershell
git add apps/rain/lib/application/state/call_surface_geometry.dart apps/rain/lib/application/state/call_surface_providers.dart apps/rain/test/call_surface_providers_test.dart
git commit -m "feat: add floating call surface geometry"
```

## Phase 05: Movable Floating Call Popup

**Files:**
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- Modify: `apps/rain/lib/presentation/screens/home_screen.dart`
- Test: `apps/rain/test/rain_chat_widgets_test.dart`

- [ ] Add callback parameters to `RainCallOverlay`:

```dart
final void Function(Offset delta, Size viewportSize, EdgeInsets safePadding, Size panelSize)? onMoveFloating;
final void Function(Size viewportSize, EdgeInsets safePadding, Size panelSize)? onClampFloating;
```

- [ ] Render non-fullscreen, non-manager call panels inside `Stack` + `Positioned` using `surface.floatingOffset`.
- [ ] Use a `GlobalKey` on `_RainExpandedCallPanel` to measure panel size after layout.
- [ ] Drag only from `_RainPopupHeader`, using `GestureDetector.onPanUpdate`.
- [ ] Add header key:

```dart
key: const ValueKey<String>('rain-call-popup-drag-handle')
```

- [ ] On layout or metrics change, call `onClampFloating` so the panel stays visible after rotation/window resize.
- [ ] Wire callbacks in `home_screen.dart` to `callSurfaceProvider.notifier.moveFloatingPanel` and `clampFloatingPanel`.
- [ ] Add widget test: drag header by `Offset(90, 60)` and assert the panel top-left changes while Answer/Decline remain tappable.
- [ ] Run:

```powershell
dart test apps/rain/test/rain_chat_widgets_test.dart --name "floating"
```

- [ ] Commit:

```powershell
git add apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart apps/rain/lib/presentation/screens/home_screen.dart apps/rain/test/rain_chat_widgets_test.dart
git commit -m "feat: make call popup floating and draggable"
```

## Phase 06: Sticky Incoming Answer And Decline Controls

**Files:**
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Test: `apps/rain/test/rain_chat_widgets_test.dart`

- [ ] Move `_RainCallControlDock` outside the scrollable body in `_RainExpandedCallPanel`.
- [ ] Keep header and media/details scrollable when height is tight, but keep controls fixed at the panel bottom.
- [ ] Replace incoming `Wrap` with a responsive action row:
  - Width >= 340: Reject and Accept sit in one row with equal width.
  - Width < 340: buttons stack vertically, full width.
  - Minimum height: 52 logical pixels.
  - Minimum tap target: 48 logical pixels.
- [ ] Add stable keys:

```dart
const ValueKey<String>('rain-call-reject-button')
const ValueKey<String>('rain-call-accept-button')
```

- [ ] Add `Semantics(button: true, label: 'Accept call')` and `Semantics(button: true, label: 'Decline call')`.
- [ ] Add widget tests for incoming audio and video at:
  - 320x568
  - 360x640
  - 568x320
  - 768x1024
  - 1280x720
- [ ] Each test must assert the buttons are visible, have non-zero size, and can be tapped.
- [ ] Run:

```powershell
dart test apps/rain/test/rain_chat_widgets_test.dart --name "incoming"
```

- [ ] Commit:

```powershell
git add apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart apps/rain/test/rain_chat_widgets_test.dart
git commit -m "fix: keep incoming call actions visible on all sizes"
```

## Phase 07: Back, Minimize, And Fullscreen Interaction Contract

**Files:**
- Modify: `apps/rain/lib/application/state/call_surface_providers.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_manager_bar.dart`
- Test: `apps/rain/test/call_surface_providers_test.dart`
- Test: `apps/rain/test/rain_call_manager_bar_test.dart`
- Test: `apps/rain/test/rain_chat_widgets_test.dart`

- [ ] Keep existing mode order:
  - Voice expanded -> managerOnly.
  - Video expanded -> pip -> managerOnly.
  - Video fullscreen -> pip.
- [ ] Ensure expanded/floating popup hides top manager bar; manager bar appears only in `managerOnly` or `pip`.
- [ ] Ensure fullscreen video has no draggable popup chrome.
- [ ] Ensure tapping small video preview still toggles primary role and is not captured by drag gestures.
- [ ] Add tests proving:
  - Drag handle exists only in expanded/floating popup.
  - Manager bar is absent while popup is visible.
  - Manager bar appears when minimized.
  - Fullscreen ignores floating offset.
- [ ] Run:

```powershell
dart test apps/rain/test/call_surface_providers_test.dart
dart test apps/rain/test/rain_call_manager_bar_test.dart
dart test apps/rain/test/rain_chat_widgets_test.dart --name "call surface"
```

- [ ] Commit:

```powershell
git add apps/rain/lib/application/state/call_surface_providers.dart apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart apps/rain/lib/presentation/widgets/calls/rain_call_manager_bar.dart apps/rain/test/call_surface_providers_test.dart apps/rain/test/rain_call_manager_bar_test.dart apps/rain/test/rain_chat_widgets_test.dart
git commit -m "fix: harden call surface mode interactions"
```

## Phase 08: Automated Gate

**Files:**
- Validate repository only; no release build in this phase.

- [ ] Run:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

- [ ] Fix any failures in the smallest affected files.
- [ ] Commit only the files changed by those fixes, using a commit message that names the failing gate that was repaired.

## Phase 09: Manual Device Gate

**Files:**
- Manual validation notes may be added to `docs/superpowers/manual-checks/2026-05-25-app-exit-floating-call-ui.md` only if useful.

- [ ] Windows close checks:
  - Open app idle, close with X, confirm process exits.
  - Open app with connected peer, close with X, confirm peer sees connection ended.
  - Open active voice call, close with X, confirm local app closes and remote call ends.
  - Open active video call, close with Alt+F4, confirm camera light turns off and process exits.
- [ ] Android checks:
  - Open app idle, swipe away from recents, confirm no ringtone or media continues.
  - Open incoming ringing call, close app, confirm peer stops ringing after terminal/expiry path.
  - Open active video call, close app, confirm camera/mic stop.
- [ ] UI checks:
  - Incoming audio and video call on smallest test phone: Answer/Decline visible without scrolling.
  - Drag popup to every corner; it clamps and controls remain tappable.
  - Rotate phone or resize desktop window; popup remains in bounds.

## Phase 10: Final Release Gate

**Files:**
- Validate only after Phase 08 and Phase 09 pass.

- [ ] If release artifacts are requested, run the existing cloud build workflow after pushing the branch.
- [ ] Do not merge until PR review confirms:
  - No regressions to voice/video signaling.
  - No reconnect after close/shutdown.
  - No call controls hidden on supported sizes.
  - No floating popup trapping interaction.
