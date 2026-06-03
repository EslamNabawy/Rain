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

## UI Risks

- Large screens such as `home_screen.dart`, `settings_screen.dart`, and `chat_panel.dart` carry too much behavior.
- Call UI has gone through multiple iterations and must keep one source of truth for surface mode and controls.
- Safe-area behavior is critical on Android call overlays.

Related: [[Branding And UI]], [[Voice Calls]], [[Video Calls]], [[UI State Map]].
