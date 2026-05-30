# Local Android QA Workflow

This project can use the shared Windows toolkit at `C:\android-flutter-qa-toolkit`.

## Daily Commands

```powershell
C:\android-flutter-qa-toolkit\scripts\test-env.ps1
C:\android-flutter-qa-toolkit\scripts\start-avd.ps1
C:\android-flutter-qa-toolkit\scripts\start-appium.ps1
C:\android-flutter-qa-toolkit\scripts\run-local-quality.ps1 -ProjectRoot "C:\path\to\project"
```

Run Flutter integration tests explicitly when you want the slower device build path:

```powershell
C:\android-flutter-qa-toolkit\scripts\run-local-quality.ps1 -ProjectRoot "C:\path\to\project" -IncludeIntegration -Udid emulator-5554
```

Run the Appium smoke path when the project has `qa.appium.json` selectors mapped to real widgets:

```powershell
C:\android-flutter-qa-toolkit\scripts\run-appium-smoke.ps1 -ProjectRoot "C:\path\to\project" -BuildFirst -StartAvd -StartAppium
```

Rain keeps the durable app flow in `integration_test/smoke_test.dart`. The Appium target at
`test_driver/appium.dart` is a small deterministic smoke shell that verifies APK build,
emulator launch, Flutter-driver attachment, key tapping, and assertion collection without
waiting on the full app's animated/runtime surfaces.

## Locator Rules

- Flutter Appium context uses `ValueKey`, for example `ValueKey('qa.login.submit')`.
- Native Android/Appium/Maestro-style automation cannot see Flutter keys; expose important controls with `Semantics`.
- Prefer stable automation identifiers over user-visible text for flows that may be localized.

## Artifacts

Run outputs are written under `D:\android-test-artifacts\<project>\<timestamp>-<kind>`.
Keep screenshots, logcat, Appium logs, and failed selector notes with the related issue.
