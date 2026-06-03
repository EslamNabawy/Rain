# Architecture Stabilization Epic

## Objective

Reduce runtime and UI fragility by separating call and app orchestration responsibilities.

## Features

- [[VoiceCallRuntime Refactor]]
- [[CallStartCoordinator]]
- [[CallMediaCoordinator]]
- [[CallTerminalReconciler]]
- [[CallDiagnosticsRecorder]]

## Tasks

- T001 in [[Backlog]]
- T003 in [[Backlog]]
- T019 in [[Backlog]]
- T020 in [[Backlog]]

## Success Criteria

- Call state phases are explicit.
- UI does not own runtime truth.
- Coordinators have contract tests.

Related: [[Master Roadmap]], [[Current Architecture]], [[Target Architecture]].
