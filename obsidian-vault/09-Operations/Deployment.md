# Deployment

## Backend

Deploy Firebase Realtime Database rules from `backend/firebase`.

```powershell
cd backend/firebase
firebase deploy --only database
```

Remote Config manifest must be updated manually unless a safe automated workflow is added later.

## App Release

Cloud workflows build:

- Android ARM v7a
- Android ARM v8/v9
- Windows

## Release Rule

Do not promote a build until:

- tests pass
- rules are deployed if changed
- update manifest is correct
- artifacts are from latest `dev`
- call smoke tests are acceptable

Related: [[Build Process]], [[Version And Updates]], [[Launch Readiness]].
