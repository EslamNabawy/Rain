# Project Memory

Last updated: 2026-06-03

## Domain Summary

Rain is a private peer-to-peer chat app for Android and Windows. It supports accepted-friend chat, file transfer, voice calls, video calls, connection request notifications, local diagnostics, and version/update validation.

## Architecture Memory

- `apps/rain` owns Flutter app, UI, runtime orchestration, infrastructure wiring.
- `packages/rain_core` owns Drift persistence, identity, friends, messages, file metadata, core frames.
- `packages/protocol_brain` owns Firebase signaling, sessions, retry policy, connection requests, voice call contracts.
- `packages/peer_core` owns WebRTC peer primitives, media connections, platform bridge.
- `backend/firebase` owns RTDB rules, Remote Config template, optional functions.
- `/obsidian-vault` owns project memory, production-readiness execution, audit resolution, sprint tracking, risk tracking, and architecture decisions.

## Business Rules

- Only accepted friends can communicate.
- One active/ringing/connecting call globally.
- Calls block new file sends/accepts.
- Active files block calls.
- Offline/stale peers cannot be called.
- Online direct Connect must not consume offline request quota.
- Manual Disconnect blocks automatic recovery for that peer.
- Closed app means offline in current scope.

## Hard Lessons

- Firebase is signaling only; media is WebRTC.
- False busy usually means stale or partial call lock state.
- Generic "media could not connect" is not enough; failures must be classified.
- Unit tests are not enough for WebRTC real-device behavior.
- Update prompts are critical because backend rules can make old apps unusable.
- The audit must be executed through [[Master Roadmap]], [[Backlog]], [[Audit Resolution Tracker]], and [[Release Gates]], not scattered chat memory.

## Naming Conventions

- Use typed reason codes for blocked actions.
- Use `VoiceCall` naming for legacy shared call signaling even when video uses the same runtime.
- Use `CallMediaMode.audio` and `CallMediaMode.video` to distinguish voice/video.

Related: [[AI Context]], [[Design Decisions]], [[Feature Index]].

## Production Execution Memory

- Highest priority architecture work: [[VoiceCallRuntime Refactor]].
- Required call coordinators: [[CallStartCoordinator]], [[CallLeaseManager]], [[CallMediaCoordinator]], [[CallTerminalReconciler]], [[CallDiagnosticsRecorder]].
- Required roadmap phases: [[Architecture Stabilization Epic]], [[Signaling Reliability Epic]], [[Database Scalability Epic]], [[File Transfer Optimization Epic]], [[Security Hardening Epic]], [[CI-CD Modernization Epic]], [[Production Validation Epic]].
- Required trackers: [[Risk Register]], [[Technical Debt Register]], [[Audit Resolution Tracker]], [[Active Sprint]].
