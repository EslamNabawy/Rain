# Call State Machine

## Required State Phases

- idle
- checking presence
- checking conflicts
- claiming lease
- waiting for ring
- preflighting media
- negotiating media
- active
- reconnecting
- ending
- ended
- failed

## Rule

Do not show media failure for signaling failures. State names must reveal the failing subsystem.

## Classification Boundary

As of 2026-06-05, call failure classification lives in `CallErrorClassifier`. It keeps signaling, busy, offline, rejected, expired, network, native media, video renderer, local microphone, and local camera failures separated before `VoiceCallRuntime` publishes user-facing state.

## Terminal Truth

Firebase terminal room state must clear both peers through [[CallTerminalReconciler]].

## Open Decomposition Work

`VoiceCallRuntime` still owns room reconciliation, command orchestration, lock coordination, and terminal cleanup. Phase 3 is not complete until those paths are extracted behind tested coordinators and terminal paths still return to idle.

Related: [[Voice Calls]], [[Video Calls]], [[CallTerminalReconciler]].
