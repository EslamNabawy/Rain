# Frontend Architecture

## App Structure

- `apps/rain/lib/presentation` - screens, widgets, theme, navigation, call surfaces.
- `apps/rain/lib/application/state` - Riverpod providers and view models.
- `apps/rain/lib/application/runtime` - side-effect controllers and runtime workflows.
- `apps/rain/lib/infrastructure` - Firebase adapter wiring, services, notifications, diagnostics.
- `apps/rain/lib/core` - environment and runtime configuration.

## State Management

Rain uses Riverpod. Runtime controllers own side effects and expose state through providers.

Important provider domains:

- identity
- selected friend/chat
- runtime connection state
- call surface state
- media device settings
- app settings
- sound events
- update status

## Startup And Navigation Readiness

- `AppStartupState` is the single UI-facing startup readiness contract for update checks, identity validation, runtime startup, session-expired reset, failures, and ready state.
- `RainApp` owns the global visual startup gate. Its `MaterialApp.router.builder` replaces routed content with `RainStartupSurface` whenever `AppStartupState.blocksRoutedSurface` is true.
- `RainApp` renders signed-out auth through a standalone Navigator/Overlay while `usesRoutedAppShell` is false, so sign-in widgets can use tooltips/overlays without inserting `RainNavigationShell`.
- `RootScreen` reuses the same `RainStartupSurface` for route-local consistency, but `/` no longer owns the only startup splash/update/error surfaces.
- `RainNavigationShell` must not be inserted while startup is loading, update-blocked, failed, or session-expired.
- Protected route readiness is now explicit through `AppStartupState.canRenderProtectedRoutes`. Settings/search/friend pages are wrapped in a route-local guard, and unresolved protected paths redirect to `/` before protected content can render.

## UI Risks

- Large screens such as `home_screen.dart`, `settings_screen.dart`, and `chat_panel.dart` carry too much behavior.
- Call UI has gone through multiple iterations and must keep one source of truth for surface mode and controls.
- Safe-area behavior is critical on Android call overlays.
- Session-scoped provider lifecycle still needs hardening after the global startup and protected-route gates.

Related: [[Branding And UI]], [[Voice Calls]], [[Video Calls]], [[UI State Map]].
