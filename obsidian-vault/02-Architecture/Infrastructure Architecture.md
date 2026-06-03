# Infrastructure Architecture

## Build And Release

GitHub Actions workflows exist for:

- CI
- main merge gate
- artifact builds
- fast release
- validated release

Build targets:

- Android ARM v7a APK
- Android ARM v8/v9 APK
- Windows portable build

## Tooling

- Flutter and Dart workspace.
- Melos workspace scripts.
- Firebase CLI for RTDB rules and Remote Config work.
- Optional local Android QA harness outside this repository.

## Risks

- Workflows duplicate logic and can drift.
- Some workflows still install or test Firebase Functions even when Spark/free-tier mode is preferred.
- Release metadata and Remote Config updates are not fully automated.

Related: [[Deployment]], [[Build Process]], [[Monitoring]].
