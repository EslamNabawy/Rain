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

Run: [Build Rain Apps #49.1](https://github.com/EslamNabawy/Rain/actions/runs/26368792103)

Commit: `f5387c5edfb16af4056a1482ffc0f5ece919f19d`

Status: Passed.

Release: [rain-test-49-1](https://github.com/EslamNabawy/Rain/releases/tag/rain-test-49-1)

Notes:

- The first workflow dispatch was canceled because local Phase 13 icon sync produced tracked platform icon updates that needed to be committed and pushed before the final cloud artifact run.
- The final cloud run built Windows, Android v7, and Android v8/v9 from the pushed Phase 13 commit.
- The publish job created a GitHub pre-release with individually downloadable phone-friendly APK assets.

Cloud release artifacts:

| Artifact | Size | SHA256 | Direct download |
| --- | ---: | --- | --- |
| `Rain-Demo-Android-v7a.apk` | 31,384,853 bytes | `c96483b74680e34f92ce0d3e4fbbe377418949adac3d5d5a2a1e95d65b38b414` | [Download](https://github.com/EslamNabawy/Rain/releases/download/rain-test-49-1/Rain-Demo-Android-v7a.apk) |
| `Rain-Demo-Android-v8-v9.apk` | 38,960,049 bytes | `83f1a53e2d4b68c3186417988a1d11d72068eb0834407534ec706c7a17fdc356` | [Download](https://github.com/EslamNabawy/Rain/releases/download/rain-test-49-1/Rain-Demo-Android-v8-v9.apk) |
| `Rain-Demo-Windows-x64.zip` | 27,663,363 bytes | `4b79cd8e66fe361a1e38d0fa6ca42cec25f2bc7fc1a8b4525dc84f7ce3ff4bfb` | [Download](https://github.com/EslamNabawy/Rain/releases/download/rain-test-49-1/Rain-Demo-Windows-x64.zip) |

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
