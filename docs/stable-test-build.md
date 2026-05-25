# Stable Test Build

This is the reproducible local build path for the currently working Rain voice-call build.

Use it when validating Android + Windows together from the same commit.

## Rule

Windows and the APK pair must be built with the same non-demo `RAIN_SIGNALING_ENCRYPTION_KEY`.

If one side is rebuilt with a different key, signaling can fail even when the app code is correct.

## Local Test Pair

From repo root:

```powershell
pwsh -NoProfile -File scripts\build_stable_test_pair.ps1 -SmokeWindows
```

Outputs:

```text
apps\rain\build\windows\x64\runner\Release\rain.exe
apps\rain\build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk
```

The APK is release-mode but locally test-signed by default with the Android debug keystore. It is for device validation, not store distribution.

If Android reports a signature conflict, uninstall the previous app first.

## OS Permissions

Video calls require camera and microphone access on both devices.

- Android: allow the camera and microphone permission prompts before accepting or starting a call.
- Windows: Settings > Privacy & security must allow Rain to use the camera and microphone.

If either side denies camera or microphone access, the call should stay recoverable and show a typed permission failure instead of raw WebRTC/native errors.

## Production Release

Use `scripts\build_release.ps1` with real release signing secrets and production-safe release dart defines.

Do not use the local stable test script for public distribution.

## Current Manual Gate

Before calling a build stable:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

Then run real device checks:

- Android to Android video call
- Android to Windows video call
- Windows to Android video call
- Android to Android voice call
- Android to Windows voice call
- Windows to Android voice call
- Hangup from both sides
- Retry after failed call
- File send blocked during active call
