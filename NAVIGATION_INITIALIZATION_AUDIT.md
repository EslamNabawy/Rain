# Navigation Initialization Audit

Date: 2026-06-03

## Current Navigation Flow

`RainApp` creates `MaterialApp.router`, using `appRouterProvider`.

`appRouterProvider` defines one `ShellRoute` with these child routes:

- `/` -> `RootScreen`
- `/settings` -> `SettingsScreen`
- `/search` -> `SearchScreen`
- `/friend/:username` -> `FriendProfileScreen`

The shell always builds `RainNavigationShell`, then passes `showNavigation` based on `appShellReadinessProvider`.

## Root Cause

Navigation initialization is not blocked by app readiness. Only the visible navigation controls are conditionally hidden. The shell route and protected route children still exist.

## Symptom

Navigation or app-shell elements can appear before app initialization is complete. Protected route children can render before auth/runtime readiness.

## Affected Components

- `appRouterProvider`
- `_RouterRefreshNotifier`
- `appShellReadinessProvider`
- `RainNavigationShell`
- `RootScreen`
- `SettingsScreen`
- `SearchScreen`
- `FriendProfileScreen`

## Detailed Findings

### Finding 1: Redirect Only Watches Identity

`_RouterRefreshNotifier` listens only to `identityProvider`. It does not listen to force update state, runtime readiness, or startup session validation.

Impact: route redirects are not synchronized with full app readiness.

### Finding 2: Redirect Allows Routes While Identity Is Loading

If `identityProvider` has no value, redirect returns `null`.

Impact: `/settings`, `/search`, and `/friend/:username` can render while identity is loading.

### Finding 3: ShellRoute Exists Even When `showNavigation` Is False

`RainNavigationShell` still builds a scaffold/backdrop/body. `showNavigation` only hides bottom nav/rail controls.

Impact: loading/protected content is still inside the app shell instead of a true startup gate.

### Finding 4: RootScreen Is Not A Global Gate

Only `/` uses `RootScreen`. Other routes do not go through its force-update/auth/runtime loading logic.

Impact: protected screens must each handle invalid/loading identity, and currently they do not consistently do that.

### Finding 5: Settings/Search Collapse Auth Loading To Null

`SettingsScreen` and `SearchScreen` use `ref.watch(identityProvider).value`. In Riverpod, `.value` can be null for loading, error, or real signed-out states.

Impact: partial protected UI renders with `Unknown` profile or enabled flows before auth state is resolved.

## Severity

High.

## Risk

Users can see partial or stale UI before app readiness. Startup failures can leak into normal app screens. Protected actions may throw late runtime errors instead of being blocked by route guards.

## Recommended Fix

Replace the current route gating with a centralized route model:

- Startup route tree for bootstrap/validation/runtime start.
- Auth route tree for signed-out.
- Protected route tree only when session is authenticated and runtime is ready.
- Force update gate above all routes.

## Long-Term Architectural Fix

Use one `AppReadinessState`:

```dart
enum AppReadinessPhase {
  bootstrapping,
  validatingSession,
  signedOut,
  runtimeStarting,
  ready,
  requiredUpdate,
  failed,
}
```

Router redirects and shell rendering should consume this state, not raw `identityProvider`, `forceUpdateProvider`, and `runtimeControllerProvider` separately.

## Reproduction Matrix

| Route | Current Risk | Expected |
| --- | --- | --- |
| `/` while force update loading | Root splash under shell | Global splash |
| `/` while runtime loading | Root splash under shell, nav hidden by readiness | Global splash |
| `/settings` while identity loading | Settings may render with unknown identity | Global splash or redirect |
| `/search` while signed out/loading | Search UI may render until redirect settles | Auth flow or global splash |
| `/friend/:username` while runtime loading | Friend profile can render with stale extra data | Global splash or protected-route block |

## Remediation Roadmap

1. Add tests for each protected route during identity loading and runtime loading.
2. Add `AppReadinessState` provider.
3. Make router refresh listen to readiness, not only identity.
4. Split auth and protected route trees.
5. Make `RainNavigationShell` unreachable until readiness is `ready`.
6. Remove route-local startup splash from `RootScreen`.
7. Update settings/search/profile to require authenticated session instead of `.value`.
