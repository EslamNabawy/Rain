# UI before and after

Opt-in snapshot harness: `apps/rain/test/ui_snapshots/ui_snapshots_test.dart` (10 cases x light/dark x phone 390x844 / desktop 1280x800, reduced motion on). Before shots were taken at T0.4 (base 02e02f2) with fallback fonts because Inter/Space Grotesk were still fetched at runtime; after shots were taken at T5.1 on ui/level-up with the bundled fonts. The file transfer bubble has no snapshot case (library-private widget at T0.4); its states are covered by `test/file_transfer_bubble_test.dart` and `test/ui_resilience_test.dart`.

| Snapshot | Before | After | Change |
|---|---|---|---|
| account_deletion_dark_desktop | [before](shots/before/account_deletion_dark_desktop.png) | [after](shots/after/account_deletion_dark_desktop.png) | Brand mark with wave motion replaces the bare spinner; title Deleting your account. |
| account_deletion_dark_phone | [before](shots/before/account_deletion_dark_phone.png) | [after](shots/after/account_deletion_dark_phone.png) | Brand mark with wave motion replaces the bare spinner; title Deleting your account. |
| account_deletion_light_desktop | [before](shots/before/account_deletion_light_desktop.png) | [after](shots/after/account_deletion_light_desktop.png) | Brand mark with wave motion replaces the bare spinner; title Deleting your account. |
| account_deletion_light_phone | [before](shots/before/account_deletion_light_phone.png) | [after](shots/after/account_deletion_light_phone.png) | Brand mark with wave motion replaces the bare spinner; title Deleting your account. |
| app_state_message_dark_desktop | [before](shots/before/app_state_message_dark_desktop.png) | [after](shots/after/app_state_message_dark_desktop.png) | Renders through RainMistStateCard (single empty/error visual). |
| app_state_message_dark_phone | [before](shots/before/app_state_message_dark_phone.png) | [after](shots/after/app_state_message_dark_phone.png) | Renders through RainMistStateCard (single empty/error visual). |
| app_state_message_light_desktop | [before](shots/before/app_state_message_light_desktop.png) | [after](shots/after/app_state_message_light_desktop.png) | Renders through RainMistStateCard (single empty/error visual). |
| app_state_message_light_phone | [before](shots/before/app_state_message_light_phone.png) | [after](shots/after/app_state_message_light_phone.png) | Renders through RainMistStateCard (single empty/error visual). |
| bubbles_dark_desktop | [before](shots/before/bubbles_dark_desktop.png) | [after](shots/after/bubbles_dark_desktop.png) | Bundled fonts; bubble chrome unchanged. |
| bubbles_dark_phone | [before](shots/before/bubbles_dark_phone.png) | [after](shots/after/bubbles_dark_phone.png) | Bundled fonts; bubble chrome unchanged. |
| bubbles_light_desktop | [before](shots/before/bubbles_light_desktop.png) | [after](shots/after/bubbles_light_desktop.png) | Bundled fonts; bubble chrome unchanged. |
| bubbles_light_phone | [before](shots/before/bubbles_light_phone.png) | [after](shots/after/bubbles_light_phone.png) | Bundled fonts; bubble chrome unchanged. |
| call_ended_dark_desktop | [before](shots/before/call_ended_dark_desktop.png) | [after](shots/after/call_ended_dark_desktop.png) | Bundled fonts; layout unchanged. |
| call_ended_dark_phone | [before](shots/before/call_ended_dark_phone.png) | [after](shots/after/call_ended_dark_phone.png) | Bundled fonts; layout unchanged. |
| call_ended_light_desktop | [before](shots/before/call_ended_light_desktop.png) | [after](shots/after/call_ended_light_desktop.png) | Bundled fonts; layout unchanged. |
| call_ended_light_phone | [before](shots/before/call_ended_light_phone.png) | [after](shots/after/call_ended_light_phone.png) | Bundled fonts; layout unchanged. |
| force_update_dark_desktop | [before](shots/before/force_update_dark_desktop.png) | [after](shots/after/force_update_dark_desktop.png) | Mist warning panel with Installed/Required chips and Get the update button instead of a plain Card. |
| force_update_dark_phone | [before](shots/before/force_update_dark_phone.png) | [after](shots/after/force_update_dark_phone.png) | Mist warning panel with Installed/Required chips and Get the update button instead of a plain Card. |
| force_update_light_desktop | [before](shots/before/force_update_light_desktop.png) | [after](shots/after/force_update_light_desktop.png) | Mist warning panel with Installed/Required chips and Get the update button instead of a plain Card. |
| force_update_light_phone | [before](shots/before/force_update_light_phone.png) | [after](shots/after/force_update_light_phone.png) | Mist warning panel with Installed/Required chips and Get the update button instead of a plain Card. |
| onboarding_dark_desktop | [before](shots/before/onboarding_dark_desktop.png) | [after](shots/after/onboarding_dark_desktop.png) | Bundled fonts; shared busy indicator in submit states. |
| onboarding_dark_phone | [before](shots/before/onboarding_dark_phone.png) | [after](shots/after/onboarding_dark_phone.png) | Bundled fonts; shared busy indicator in submit states. |
| onboarding_light_desktop | [before](shots/before/onboarding_light_desktop.png) | [after](shots/after/onboarding_light_desktop.png) | Bundled fonts; shared busy indicator in submit states. |
| onboarding_light_phone | [before](shots/before/onboarding_light_phone.png) | [after](shots/after/onboarding_light_phone.png) | Bundled fonts; shared busy indicator in submit states. |
| skeleton_dark_desktop | [before](shots/before/skeleton_dark_desktop.png) | [after](shots/after/skeleton_dark_desktop.png) | Default lines variant kept; pulse frozen under reduced motion. |
| skeleton_dark_phone | [before](shots/before/skeleton_dark_phone.png) | [after](shots/after/skeleton_dark_phone.png) | Default lines variant kept; pulse frozen under reduced motion. |
| skeleton_light_desktop | [before](shots/before/skeleton_light_desktop.png) | [after](shots/after/skeleton_light_desktop.png) | Default lines variant kept; pulse frozen under reduced motion. |
| skeleton_light_phone | [before](shots/before/skeleton_light_phone.png) | [after](shots/after/skeleton_light_phone.png) | Default lines variant kept; pulse frozen under reduced motion. |
| splash_dark_desktop | [before](shots/before/splash_dark_desktop.png) | [after](shots/after/splash_dark_desktop.png) | Bundled Inter/Space Grotesk; mark continues its loop phase across hand-offs; caption slot (empty here). |
| splash_dark_phone | [before](shots/before/splash_dark_phone.png) | [after](shots/after/splash_dark_phone.png) | Bundled Inter/Space Grotesk; mark continues its loop phase across hand-offs; caption slot (empty here). |
| splash_light_desktop | [before](shots/before/splash_light_desktop.png) | [after](shots/after/splash_light_desktop.png) | Bundled Inter/Space Grotesk; mark continues its loop phase across hand-offs; caption slot (empty here). |
| splash_light_phone | [before](shots/before/splash_light_phone.png) | [after](shots/after/splash_light_phone.png) | Bundled Inter/Space Grotesk; mark continues its loop phase across hand-offs; caption slot (empty here). |
| startup_failure_dark_desktop | [before](shots/before/startup_failure_dark_desktop.png) | [after](shots/after/startup_failure_dark_desktop.png) | Sanitized message (no raw StateError), static brand mark, Copy details; Try again only when a retry exists. |
| startup_failure_dark_phone | [before](shots/before/startup_failure_dark_phone.png) | [after](shots/after/startup_failure_dark_phone.png) | Sanitized message (no raw StateError), static brand mark, Copy details; Try again only when a retry exists. |
| startup_failure_light_desktop | [before](shots/before/startup_failure_light_desktop.png) | [after](shots/after/startup_failure_light_desktop.png) | Sanitized message (no raw StateError), static brand mark, Copy details; Try again only when a retry exists. |
| startup_failure_light_phone | [before](shots/before/startup_failure_light_phone.png) | [after](shots/after/startup_failure_light_phone.png) | Sanitized message (no raw StateError), static brand mark, Copy details; Try again only when a retry exists. |
| state_card_dark_desktop | [before](shots/before/state_card_dark_desktop.png) | [after](shots/after/state_card_dark_desktop.png) | Radius/space/shadow tokens; one-shot fade+scale (static under reduced motion). |
| state_card_dark_phone | [before](shots/before/state_card_dark_phone.png) | [after](shots/after/state_card_dark_phone.png) | Radius/space/shadow tokens; one-shot fade+scale (static under reduced motion). |
| state_card_light_desktop | [before](shots/before/state_card_light_desktop.png) | [after](shots/after/state_card_light_desktop.png) | Radius/space/shadow tokens; one-shot fade+scale (static under reduced motion). |
| state_card_light_phone | [before](shots/before/state_card_light_phone.png) | [after](shots/after/state_card_light_phone.png) | Radius/space/shadow tokens; one-shot fade+scale (static under reduced motion). |

## Observed while comparing (not regressions)

- Button labels render as test-font blocks in both before and after shots. `RainTheme` button `textStyle` uses the literal family `'Space Grotesk'`, but google_fonts registers its families under its own names, so button text probably falls back to the platform font on devices too. Fix candidate: build button text styles with `GoogleFonts.spaceGrotesk(...)`. Recorded under Remaining ideas.
- Material icons render as boxes in golden tests (icon font not loaded by the harness); expected test behaviour.
- The force-update and other backdrop surfaces look light in `*_dark_*` shots before and after: the backdrop follows platform brightness rather than the app theme mode.
