# Rain Critical Polish Validation - 2026-05-24

Branch: `codex/rain-rebrand-implementation`

Scope: automated test and visual harness gate for the critical rebrand, sound, call manager, and video call UI polish phases. No Android APK or Windows executable builds were produced in this gate; build output belongs to Phase 13.

## Result

Status: Passed.

## Formatting

- `dart format --set-exit-if-changed apps/rain/lib apps/rain/test packages/peer_core/lib packages/peer_core/test packages/protocol_brain/lib packages/protocol_brain/test packages/rain_core/lib packages/rain_core/test backend/firebase`
  - Passed.
  - Result: `175 files`, `0 changed`.

## Focused Tests

- `dart run melos exec --scope rain -- flutter test test/call_surface_providers_test.dart`
  - Passed.
  - Covers call surface visibility, fullscreen exit, video PiP, manager-only mode, and back-intent behavior.

- `dart run melos exec --scope rain -- flutter test test/rain_brand_mark_test.dart`
  - Passed.
  - Covers static Peer Core mark, reduced motion, and orbital mesh animation.

- `dart run melos exec --scope rain -- flutter test test/rain_chat_widgets_test.dart`
  - Passed.
  - Covers chat widgets, call controls, expanded call popup states, video fullscreen/PiP layouts, audio meter behavior, failure UI, and compact mobile layout.

- `dart run melos exec --scope rain -- flutter test test/rain_call_manager_bar_test.dart test/rain_sound_event_test.dart test/sound_event_router_test.dart test/sound_effects_service_test.dart test/sound_effects_assets_test.dart test/settings_screen_test.dart test/app_settings_store_test.dart`
  - Passed after replacing open-ended settings-screen `pumpAndSettle` waits with bounded frame pumps.
  - Covers top call manager safe-area/compact constraints, sound event routing, burst compression, ringtone/ringback loops, sound assets, settings persistence, and audio settings UI.

## Standard Validation

- `dart pub get`
  - Passed.

- `dart run melos run analyze`
  - Passed.
  - Packages analyzed: `peer_core`, `rain_core`, `protocol_brain`, `rain`.

- `dart run melos run test`
  - Passed.
  - Full workspace test suite passed.
  - Firebase emulator integration tests remained skipped because this local gate did not start Firebase emulators.

## Visual Harness Notes

Automated widget tests are the visual harness for this phase. They verify the rendered Flutter state for:

- Rebranded Peer Core mark animation and reduced-motion fallback.
- Splash compact-height fit.
- Mist state surfaces and Rain backdrop theme behavior.
- Expanded call popup voice/video/failure layouts.
- Top call manager safe-area and compact desktop constraints.
- Video fullscreen and PiP layout behavior.
- PiP and manager surfaces not blocking the chat composer.

Physical Android and Windows screenshots are still required at the final build/manual gate, because Phase 12 did not produce installable artifacts.

## Fix Applied During Gate

`settings_screen_test.dart` used `pumpAndSettle` after rendering settings. Continuous rebrand motion can keep frames scheduled indefinitely, causing false timeout failures. The test helper now pumps a bounded frame window, which keeps the settings tests deterministic while preserving coverage.
