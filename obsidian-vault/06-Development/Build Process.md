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

## Windows Release Artifact

Expected artifact:

- Windows portable package/build output

## Release Risk

Release workflows duplicate logic. Future work should consolidate into reusable workflow components.

Related: [[Deployment]], [[Launch Readiness]].
