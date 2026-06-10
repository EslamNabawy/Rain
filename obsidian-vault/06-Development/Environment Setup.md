# Environment Setup

## Required Tools

- Flutter 3.44.0 target used by workflows.
- Dart SDK compatible with `^3.10.4`.
- JDK 21 for Android builds.
- Android SDK for APK builds.
- Windows desktop toolchain for Windows builds.
- Firebase CLI for backend rules/config.

## Workspace Setup

```powershell
dart pub get
dart run melos bootstrap
```

## Run Windows App

```powershell
cd apps/rain
flutter run -d windows --dart-define-from-file=tool/dart_defines.example.json
```

## Local Defines

Copy `apps/rain/tool/dart_defines.example.json` to `dart_defines.local.json` for local overrides. Do not commit local defines.

Related: [[Build Process]], [[Deployment]].
