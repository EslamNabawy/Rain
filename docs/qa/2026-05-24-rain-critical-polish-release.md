# Rain Critical Polish Release Gate - 2026-05-24

Branch: `codex/rain-rebrand-implementation`

Purpose: Phase 13 final build and release gate for the Rain critical rebrand, sound, call manager, and video layout polish work.

## Local Build

Command:

```powershell
pwsh -NoProfile -File scripts\build_release.ps1 -Platform all -OutputDir artifacts\phase13-local -DartDefinesFile apps\rain\tool\dart_defines.example.json -AndroidArtifactSet mobile -AllowPublicTurnForDemo -UseDemoAndroidSigningKey -Clean
```

Result: Passed.

Notes:

- This was a demo test build. It intentionally used the demo dart defines, demo signing key, and OpenRelay/public TURN allowance.
- Windows release build completed and packaged a portable zip.
- Android release build completed with split APKs for `armeabi-v7a` and `arm64-v8a`.
- Script verified required native runtime entries in each APK.
- The Android build emitted Kotlin Gradle plugin migration warnings and Java 8 source/target warnings; these did not block the release artifacts.

Local artifacts:

| Artifact | Size | SHA256 |
| --- | ---: | --- |
| `artifacts/phase13-local/Rain-Demo-Android-ARM-v7a-Build.apk` | 31,383,805 bytes | `0E1AADC8798DC9013FFC00608E01567ACC306751FBF044514AB102CA33CBA025` |
| `artifacts/phase13-local/Rain-Demo-Android-ARM-v8-v9-Build.apk` | 38,959,001 bytes | `69C4A67041256B7AC1E5DBA1CBBB504F8442D2DCA0B46C3F57195F82AC79014D` |
| `artifacts/phase13-local/Rain-Demo-Windows-x64-Build.zip` | 28,253,756 bytes | `19AF9E556F8800D1849731A01127ABAA1CAFF65F539122972B8D20EB5B4973CF` |

## Cloud Build

Workflow: `Build Rain Apps`

Inputs:

- `platform`: `all`
- `build_profile`: `demo`
- `publish_test_release`: `true`

Status: Pending final updated-commit run.

The first workflow dispatch was canceled because local Phase 13 icon sync produced tracked platform icon updates that need to be committed and pushed before the final cloud artifact run.

## Release Notes

- Completed Rain rebrand polish.
- New animated Peer Core splash and rebranded platform icons.
- Replaced Rain sound effects and tightened sound playback policy.
- Added top call manager bar.
- Redesigned expanded call popup surface.
- Added video fullscreen, PiP, and hidden/manager-only modes.
- Polished Android back behavior and Windows Escape fullscreen handling.

## Remaining Manual Gate

After cloud artifacts are published, run physical-device checks with the downloadable APKs and Windows package:

- Install v7 APK on a v7 device if available.
- Install v8/v9 APK on an ARM64 Android phone.
- Launch Windows portable build.
- Verify voice/video call UI states, top manager, PiP, fullscreen, sound effects, mute/deafen, and hangup.
