# UI/UX level-up: final report

Branch `ui/level-up` (worktree `D:\Rain-uiux`), cut from `audit/rain-hardening` @ 02e02f2 and synced with `dev` @ 0772b2a (hardening is already merged into `dev`). Program: `audit/prompts/rain-uiux-orchestrator.xml`. Detailed log, decisions and notes: `audit/ui/STATE.md`.

## Results

| Task | Commit | Result |
|---|---|---|
| T0.1 | 6f548b9 | Worktree and state file |
| T0.2 | 3eee2be | Baseline: analyze clean, 764 pass / 20 skipped |
| T0.3 | b6b3fd9 | `00-ui-inventory.md` |
| T0.4 | ccfe777 | Opt-in snapshot harness, 40 before shots |
| T1.1 | eccc14a | Inter + Space Grotesk bundled, runtime font fetching off |
| T1.2 | 6be6cfe | Spacing/radius/shadow/motion tokens, dark snackbar theme |
| T1.3 | 0a14c69 | Single `RainMotionPolicy` |
| T1.4 | fc14e34 | `rainUserFacingError` replaces five helpers |
| T1.5 | a935f25 | `AppStateMessage` renders the mist state card |
| T1.6 | 17f6cf5 | `RainBusyIndicator` (14 spinners) and `RainDelayedReveal` |
| T2.1 | db3320a | Splash mark continuous across hand-offs |
| T2.2 | 2c0971a | Phase captions and cross-fade into the app |
| T2.3 | 4fde30e | Startup failure: sanitized text, bootstrap retry, copy details |
| T2.4 | a0c54dd | Force update panel, deletion brand mark |
| T2.5 | 1a15bf3 | Native splash mark (pre-31 layer later removed, see T5.2) |
| T2.6 | 22f5997 | Shaped, pulsing skeletons at 4 sites |
| T2.7 | 8e21284 | Transfer progress tween, waiting state, completion check |
| T2.8 | 6960842 | Call connecting/reconnecting pulse |
| sync | b6a5169 | Merged `origin/dev`; one header conflict resolved |
| T3.1 | 86a4395 | `02-sound-map.md` with measured loudness |
| T3.2 | 38f8c3e | Six new generated cues (+ 82cd980 README) |
| T3.3 | 6353662 | New effects mapped; transfer events with dedupe/throttle/in-call suppression |
| T3.4 | 75df9b7 | Transfer cues for the open chat |
| T3.5 | 049f602 | Preload of frequent cues |
| T3.6 | 7c99b01 | Ringing loops fade out over 120 ms |
| T3.7 | 4cd5b12 | Volume preview in settings |
| T3.8 | 8c787b8 | Per-group loudness test (no spec changes needed) |
| T3.9 | 798cc17 | Android haptics behind a setting |
| T4.1 | 0070701 | New messages fade and slide in |
| T4.2 | ac578c1 | Press/hover/focus feedback; value-equal button overlays |
| T4.3 | debe917 | Stateful semantics for call toggles |
| T4.4 | 757c615 | Empty states with a next step |
| T4.5 | f5adb86 | `showRainSnack` replaces 22 snackbars |
| T4.6 | 394c191 | Resilience and contrast test (no fixes needed) |
| T5.1 | 11ed518 | 40 after shots, `03-before-after.md` |
| T5.2 | 3b0224f, 044abe7 | Pre-31 launch background made bitmap-free again; validation recorded |
| T5.3 | c384b2a | Vault note [UI UX Level-Up] and continuity entry |

## Blocked

None.

## Handoff to hardening

- Expose a startup retry on `appStartupStateProvider` so the in-app `AppStartupPhase.failed` screen can offer Try again (only the bootstrap failure retries today).
- Emit a runtime event when any file transfer completes or fails, so a cue can play when that chat is not open.
- `packages/protocol_brain/test/release_contract_test.dart` forbids any `<bitmap>` in the pre-31 launch backgrounds. The Rain mark therefore shows natively only on Android 12+ (values-v31). Relax the contract to allow `@drawable/rain_splash_mark` if the mark should also show on Android 8-11.

## Owner actions

- Run the app on Android and Windows and walk startup, onboarding, chat, call and settings.
- Check reduced motion: Android "Remove animations" and Windows "Show animations" off. Loops must stop and transitions must jump.
- Listen to every cue in `audit/ui/02-sound-map.md` on phone speaker, headphones and a Windows laptop. Flag any that is harsh, too quiet or confusable.
- Feel haptics on an Android phone (send, answer/decline/hang-up, mute/camera, settings switches) and confirm the Haptic feedback switch turns them off.
- Cold-start on Android 11 and 13. On 13 the native splash mark must sit centred on `#061017` and not be clipped by the circular mask; on 11 the screen is plain `#061017`. Either must hand off to the Flutter splash without a flash.
- Decide whether to merge `ui/level-up` into `dev` (draft PR below).

## Validation

| Check | Baseline (T0.2, 2026-10-11) | Final (T5.2, 2026-10-27) |
|---|---|---|
| Flutter SDK | 3.44.4 | 3.47.8 (local; CI pins 3.44.0) |
| Analyze apps/rain | No issues | No issues (also peer_core, protocol_brain, rain_core) |
| Tests apps/rain | +764, 20 skipped | +889, 30 skipped |
| Tests packages | not run | peer_core pass, protocol_brain +299 pass, rain_core pass |
| Format | 0 of 295 changed | 3 of 329 changed: dev integration tests, formatter-version drift (dev shows the same diff), outside this program's scope |
| Line limit (3200) | none over | none over |
| Vault check | n/a | passed, 202 files |

Known timing flakes under full-suite load (they pass alone): `friend_flow_test` (renderer attach failure, cancel incoming transfer) and `sound_event_router_test` (five sends in 200 ms).

## Remaining ideas

- Button text styles use the literal font family `'Space Grotesk'`, which google_fonts does not register; build them with `GoogleFonts.spaceGrotesk(...)` so buttons use the brand font.
- Backdrop surfaces follow platform brightness instead of the app theme mode (visible in `*_dark_*` snapshots).
- Add a snapshot case for the file transfer bubble via `buildFileTransferBubbleForTest`.
- Add settings to `ui_resilience_test.dart` with the settings provider harness.
- Haptics for overflow-menu call toggles.
- Sweep the remaining `BorderRadius.circular` and `Color(0x..)` literals onto tokens as files are touched.
