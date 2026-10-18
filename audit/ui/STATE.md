# UI/UX State

## Done

- T0.1 6f548b9 worktree D:\Rain-uiux on ui/level-up and state file
- T0.2 3eee2be baseline: analyze clean, 764 tests pass, 20 skipped
- T0.3 b6b3fd9 audit/ui/00-ui-inventory.md
- T0.4 ccfe777 opt-in snapshot harness and before shots
- T1.2 6be6cfe spacing/radius/shadow/motion tokens, dark snackbar theme
- T1.3 0a14c69 single RainMotionPolicy for presentation
- T1.1 eccc14a bundled Inter + Space Grotesk, runtime fetching off

## Blocked

## Handoff to hardening

## Decisions

- U-D1 Work happens in worktree D:\Rain-uiux on ui/level-up, cut from origin/audit/rain-hardening; the hardening checkout D:\Rain is never touched.
- U-D2 Direction: keep Rain's existing dark "signal mist" identity (cyan/mint on deep ink, Space Grotesk + Inter). Level up consistency, motion, feedback and sound; no rebrand, no new palette.
- U-D3 Motion budget: UI transitions 110-240 ms, ease-out in and ease-in out; nothing loops forever except the splash mark, skeleton pulse and call-connecting pulse, all off under reduced motion or low-power tier.
- U-D4 Sound direction: stay in the existing "water droplet" family from the generator; every distinct meaning gets a distinct cue; nothing louder than the current incoming ringtone.
- U-D5 chat_panel.dart and home_screen.dart get in-place edits only; their split stays with the hardening program.

## Notes

- T0.1: worktree cut from origin/audit/rain-hardening @ 02e02f2, which already tracks both orchestrator prompts (copies identical to D:\Rain, so the copy step was a no-op). Upstream tracking of ui/level-up was unset so a bare `git push` can never target audit/rain-hardening.
- T0.1: `flutter pub get` resolved packages and left pubspec.lock unchanged; it warns "Building with plugins requires symlink support" (Windows Developer Mode off). Only matters for platform builds, which this program does not run.
- T0.4: snapshot harness has 10 cases x 2 themes x 2 sizes = 40 PNGs in shots/before. The file_transfer case was skipped: `_FileTransferBubble` is library-private (part of chat_panel) with no public constructor helper. google_fonts fetch errors are dropped inside a guarded zone in the harness; text renders in the fallback font until T1.1. Before shots are therefore NOT in Inter/Space Grotesk.
- Baseline (T0.2, 2026-10-11, base 02e02f2): apps/rain analyze no issues; format 0 changed of 295; apps/rain tests +764 passed, 20 skipped, 0 failed; line limit no file over 3200.
- T1.1: google/fonts only ships variable Inter[opsz,wght] and SpaceGrotesk[wght]. Static weights were instanced from those official files with fontTools (Inter opsz=14; Inter 400/500/600/700, Space Grotesk 500/600/700), named per google_fonts 8.1.0 lookup (Family-Weight.ttf). OFL kept as Inter-OFL.txt / SpaceGrotesk-OFL.txt.
- T1.4: union of the five helpers = strip 'Exception: '/'Bad state: '/'StateError: ' prefixes; home_screen call/transfer/network phrase mappings; onboarding firebase_database permission-denied account message. All now live in presentation/feedback/rain_error_text.dart; settings now shows 'Microphone permission required.' for mic permission errors (was raw text).
