# Voice Call Final Build And PR Gate - 2026-05-24

Gate status: COMPLETE WITH MANUAL DEVICE WAIVER

The requester explicitly waived the physical Android manual-device requirement
for this run after Phase 12 was recorded as blocked. This report does not claim
that the manual device matrix passed.

## Source

```text
Tester: Codex
Date: 2026-05-24
Git branch: dev
Git commit: fa34a02
Manual device gate: WAIVED BY REQUESTER
```

## Automated Validation

```text
dart pub get: PASS
dart run melos run analyze: PASS
dart run melos run test: PASS
```

Notes:

- Local Firebase emulator integration tests were skipped by their existing
  guards because Firebase emulators were not running.
- `runtime_startup_test.dart` intentionally prints a startup failure stack trace
  while asserting the visible error screen; the overall test command passed.

## Build Command

```powershell
pwsh -NoProfile -File scripts\build_stable_test_pair.ps1 -SmokeWindows
```

The helper generated one shared non-demo signaling encryption key for both
artifacts and did not expose the key in source control.

## Build Result

```text
Windows x64 release: PASS
Windows smoke check: PASS
Android armeabi-v7a release-mode APK: PASS
APK ABI check: PASS
```

Build warnings observed:

- Flutter warned that the project and several plugins still apply the Kotlin
  Gradle Plugin path that future Flutter versions will require migrating.
- Android icon tree shaking reduced Material Icons; no build failure.

## Artifacts

```text
final product\phase13-fa34a02\Rain-Stable-Android-ARM-v7a-Build.apk
  Size: 30,694,048 bytes
  SHA256: 0662116C08FD5708D1AC12D50DCE7114D1F19E3985D90BDA02BC01832B27C091
  Native ABI: armeabi-v7a only
  Required native runtimes: libjingle_peerconnection_so.so, libsqlite3.so

final product\phase13-fa34a02\Rain-Stable-Windows-x64-Build.zip
  Size: 29,131,630 bytes
  SHA256: 336FB616BB577A1444F686E117A6C768FF612AF0C743D8A04593AD5E94DA2308

final product\phase13-fa34a02\Rain-Stable-Windows-x64-Build\rain.exe
  SHA256: A3ECAB188254F06EA4DE522DAA1886C169F0CC491D5431BC10E485BE306B572A
```

## Manual Device Matrix

Manual device validation was not run in this gate. Phase 12 remains documented
in `docs/qa/voice-call-manual-device-gate-2026-05-24.md`.

```text
At least 3 successful Android-to-Android calls: WAIVED
At least 3 successful Android-to-Windows calls: WAIVED
At least 3 successful Windows-to-Android calls: WAIVED
No stuck "peer busy" after hangup/failure: WAIVED
No lost chat/file-transfer behavior outside active call blocking: WAIVED
External music keeps playing while Rain SFX plays: WAIVED
```

## PR Notes

The PR must state that automated validation and local artifact builds passed,
but real physical-device validation was waived for this run. Do not present this
as a fully real-device-certified release.
