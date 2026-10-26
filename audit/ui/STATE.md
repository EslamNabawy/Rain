# UI/UX State

## Done

- T0.1 6f548b9 worktree D:\Rain-uiux on ui/level-up and state file
- T0.2 3eee2be baseline: analyze clean, 764 tests pass, 20 skipped
- T0.3 b6b3fd9 audit/ui/00-ui-inventory.md
- T0.4 ccfe777 opt-in snapshot harness and before shots
- T1.2 6be6cfe spacing/radius/shadow/motion tokens, dark snackbar theme
- T1.3 0a14c69 single RainMotionPolicy for presentation
- T1.1 eccc14a bundled Inter + Space Grotesk, runtime fetching off
- T1.4 fc14e34 rainUserFacingError replaces five helpers
- T1.5 a935f25 mist card uses tokens and fades in once
- T1.6 17f6cf5 RainBusyIndicator replaces 14 spinners; RainDelayedReveal
- T2.1 db3320a orbital loop resumes by wall clock; intro scale once per process
- T2.2 2c0971a captions after 600 ms; AnimatedSwitcher by surface kind; bootstrap splash themed
- T2.3 4fde30e failure screen sanitized, bootstrap retry, copy details; in-app retry handed off
- T2.4 a0c54dd force update panel with chips; deletion shows brand mark
- T2.5 1a15bf3 native splash bitmap + v31 styles (no build run)
- T2.6 22f5997 skeleton variants + pulse + delayed reveal at 4 sites
- T2.7 8e21284 transfer bubble progress tween/waiting/check; tests added; send button already fixed-size
- T2.8 6960842 RainConnectingPulse around the call status glyph; warning colour while media reconnects
- sync b6a5169 merged origin/dev (hardening already merged there); 1 header conflict in splash_screen.dart; 835 tests pass
- T3.1 86a4395 audit/ui/02-sound-map.md with measured peak/RMS
- T3.2 38f8c3e six new generated cues; 15 old WAVs byte-identical after SOUNDGEN (README line added in the next commit)
- T3.3 6353662 new effects + transfer events mapped, dedupe/throttle/in-call suppression; asset budget adjusted (U-D6)
- T3.4 75df9b7 open-chat transfer completed/failed cues via pure diff + ref.listen
- T3.5 049f602 RainSoundPlayer.preload + SoundEffectsService.warmUp(send/receive/action/error) from the router provider
- T3.6 7c99b01 loops fade to 0 in 4 steps over 120 ms; stopAll stays immediate

## Blocked

## Handoff to hardening

- App-wide file transfer sounds (T3.4): emit a runtime event when any transfer reaches completed/failed so the router can play a cue when that chat is not open. Today only the open conversation plays transfer cues.
- Expose a startup retry on appStartupStateProvider (T2.3): no retry/restart method exists, so the in-app AppStartupPhase.failed screen has no Try again button; only the bootstrap failure (main.dart) retries.

## Decisions

- U-D1 Work happens in worktree D:\Rain-uiux on ui/level-up, cut from origin/audit/rain-hardening; the hardening checkout D:\Rain is never touched.
- U-D2 Direction: keep Rain's existing dark "signal mist" identity (cyan/mint on deep ink, Space Grotesk + Inter). Level up consistency, motion, feedback and sound; no rebrand, no new palette.
- U-D3 Motion budget: UI transitions 110-240 ms, ease-out in and ease-in out; nothing loops forever except the splash mark, skeleton pulse and call-connecting pulse, all off under reduced motion or low-power tier.
- U-D4 Sound direction: stay in the existing "water droplet" family from the generator; every distinct meaning gets a distinct cue; nothing louder than the current incoming ringtone.
- U-D6 (T3.3) The existing asset contract caps non-call one-shots at 260 ms and all sounds at 500 KB. request_accepted.wav was shortened to 260 ms. request_inbound.wav stays 420 ms as an alert cue, exempt like call_* cues. The total budget is 620 KB (+~115 KB for the six new cues). route_change targetPeak went 8000 to 8200 to clear the 8000 peak floor.
- U-D7 (T3.4) Transfer sounds play for the open conversation only (chat_panel listens to fileTransfersProvider(peerId)). App-wide transfer sounds need a runtime event and are a hardening handoff.
- U-D5 chat_panel.dart and home_screen.dart get in-place edits only; their split stays with the hardening program.

## Notes

- T0.1: worktree cut from origin/audit/rain-hardening @ 02e02f2, which already tracks both orchestrator prompts (copies identical to D:\Rain, so the copy step was a no-op). Upstream tracking of ui/level-up was unset so a bare `git push` can never target audit/rain-hardening.
- T0.1: `flutter pub get` resolved packages and left pubspec.lock unchanged; it warns "Building with plugins requires symlink support" (Windows Developer Mode off). Only matters for platform builds, which this program does not run.
- T0.4: snapshot harness has 10 cases x 2 themes x 2 sizes = 40 PNGs in shots/before. The file_transfer case was skipped: `_FileTransferBubble` is library-private (part of chat_panel) with no public constructor helper. google_fonts fetch errors are dropped inside a guarded zone in the harness; text renders in the fallback font until T1.1. Before shots are therefore NOT in Inter/Space Grotesk.
- Baseline (T0.2, 2026-10-11, base 02e02f2): apps/rain analyze no issues; format 0 changed of 295; apps/rain tests +764 passed, 20 skipped, 0 failed; line limit no file over 3200.
- T1.1: google/fonts only ships variable Inter[opsz,wght] and SpaceGrotesk[wght]. Static weights were instanced from those official files with fontTools (Inter opsz=14; Inter 400/500/600/700, Space Grotesk 500/600/700), named per google_fonts 8.1.0 lookup (Family-Weight.ttf). OFL kept as Inter-OFL.txt / SpaceGrotesk-OFL.txt.
- T1.4: union of the five helpers = strip 'Exception: '/'Bad state: '/'StateError: ' prefixes; home_screen call/transfer/network phrase mappings; onboarding firebase_database permission-denied account message. All now live in presentation/feedback/rain_error_text.dart; settings now shows 'Microphone permission required.' for mic permission errors (was raw text).
- sound_event_router_test 'five sends in 200 ms' is wall-clock flaky under full-suite load (passes alone); not touched by this program.
- Owner action (T2.5): cold-start on Android 11 and Android 13: native splash shows the mark centred on #061017 and hands off to the Flutter splash without a flash. Android 12+ masks the animated icon to a circle, so check the 192 px mark is not clipped.
- T2.8: VoiceCallPhase has no reconnecting value; reconnecting = phase active + VoiceCallState.mediaReconnecting. Full suite +821 ~30 passed. FORMAT reports 3 pre-existing unformatted files outside this program's scope (integration_two_devices_handshake_full_test.dart, integration_two_users_end2end_test.dart, integration_voice_signaling_emulator_test.dart; last touched by 6ff832b); left as is.
- Phase 3 sync: local Flutter is now 3.47.8 (CI pins 3.44.0). `flutter pub get` bumps matcher 0.12.20, meta 1.19.0, test 1.31.1 and `--enforce-lockfile` fails. The committed pubspec.lock stays at dev's version; never stage the local drift.
- Phase 3: unstaged edits to apps/rain, peer_core, protocol_brain and rain_core analysis_options.yaml (analyzer excludes) appeared at 14:11 from outside this program. They are outside may_edit: not staged, not reverted.
- T3.6: fake_async is not a direct dev dependency and U5 forbids adding one, so the fade tests use real time (about 120 ms each). Public stopAllLoops() keeps its signature because three test fakes override it; stopAll uses a private no-fade path.
- T3.7: a full-width 'Play test sound' TextButton row pushed 'Call sounds' off the 800x1000 test view. The preview is now a compact IconButton (tooltip 'Play test sound', key qa.settings.sound_test) in the volume tile's trailing slot. The preview plays the action cue through SoundEffectsService directly (not the router), after the pending volume save, so it is audible during calls too. settings_screen.dart grew by 30 net lines.
- friend_flow_test 'remote video renderer attach failure' failed once under full-suite load, passed alone and on rerun (timing flake, untouched code).
