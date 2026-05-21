# Rain App

Flutter desktop and Android shell for Rain.

## Source Layout

- `lib/application`: bootstrap, Riverpod providers, runtime orchestration.
- `lib/core`: compile-time and platform configuration.
- `lib/infrastructure`: Firebase adapters and device/app services.
- `lib/presentation`: routes, screens, widgets, and theme.

## Local Run

```powershell
flutter run -d windows --dart-define-from-file=tool/dart_defines.example.json
```

## Validation

```powershell
flutter analyze
flutter test
```
