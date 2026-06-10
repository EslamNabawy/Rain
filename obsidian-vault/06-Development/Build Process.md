# Build Process

## Validation

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

## Android Release Artifacts

Expected direct device artifacts:

- ARM v7a APK
- ARM v8/v9 APK

## Android Build Warnings

Rain's app module must not apply the Kotlin Gradle Plugin directly. The Android
activity shim is Java so future Flutter/AGP built-in Kotlin migration warnings
do not come from Rain-owned app code. `settings.gradle.kts` still declares the
Kotlin plugin version with `apply false` so third-party plugin modules compile
against the expected Kotlin toolchain. Third-party Flutter plugins can still
emit Kotlin Gradle Plugin warnings until those packages publish compatible
Android builds; treat that as dependency-update debt, not a reason to re-add
`kotlin-android` to the app module.

## Windows Release Artifact

Expected artifact:

- Windows portable package/build output

## Release Risk

Release workflows duplicate logic. Future work should consolidate into reusable workflow components.

Related: [[Deployment]], [[Launch Readiness]].
