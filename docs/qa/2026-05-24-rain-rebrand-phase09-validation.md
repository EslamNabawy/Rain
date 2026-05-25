# Rain Rebrand Phase 09 Validation

Date: 2026-05-24
Branch: codex/rain-rebrand-implementation

## Automated Gate

- `dart pub get`: passed.
- `dart run melos run analyze`: passed.
- `dart run melos run test`: passed.

The Firebase emulator integration tests remained skipped by the existing test guards when no emulator was running.

## Windows Noop Gate

Command:

```powershell
cd apps/rain
flutter run -d windows --dart-define=RAIN_BACKEND=noop
```

Result: the app built and launched on Windows with the noop backend. The VM service was available and no new startup exception was printed after the fix.

Phase 09 initially exposed a Flutter zone mismatch during `runApp`. The startup path now initializes Flutter bindings, crash diagnostics, desktop shell setup, and `runApp` inside the same guarded zone.

The Windows desktop shell setup was also moved out of `AppBootstrapper` and into a pre-`runApp` `DesktopShellController`, matching the `window_manager` lifecycle pattern and keeping bootstrap focused on runtime services.

Visual evidence was captured with the Flutter inspector because the OS-level screen capture in this desktop session returned a white client area despite the live widget tree. The inspector screenshot verified the rendered noop app shell: local demo banner, rebranded navigation, Rain/Peer Core mark, Rain Streak active state, and Mist State Cards.

## Notes

- A clean Windows debug build may emit nonfatal Firebase/libcurl `LNK4099` missing PDB warnings.
- Real monitor/device visual confirmation still belongs in the final manual release gate.
