# UI/UX State

## Done

- T0.1 6f548b9 worktree D:\Rain-uiux on ui/level-up and state file

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
- Baseline (T0.2, 2026-10-11, base 02e02f2): apps/rain analyze no issues; format 0 changed of 295; apps/rain tests +764 passed, 20 skipped, 0 failed; line limit no file over 3200.
