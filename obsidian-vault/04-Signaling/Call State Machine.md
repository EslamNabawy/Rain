# Call State Machine

Last updated: 2026-06-06

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

As of 2026-06-06, local failed terminal call state is also protected from late local session cleanup callbacks. A live video renderer failure writes terminal failed state with reason code `videoRendererFailed`; subsequent `session.hangUp()` idle emissions are treated as late frames and cannot overwrite the failed UI state.

## Peer UI Projection

Peer link UI must consume the unified `ConnectionDiagnostics` projection, not recompute from raw presence, data session, and call providers independently.

Precedence:

1. failed or terminal call/session state
2. manual disconnect intent
3. recovering or reconnecting
4. superseded/out-of-sync session
5. connected with fresh presence
6. stale data lane (`Data lane only`)
7. ready/offline

`Data lane only` may allow messaging through `canSendData`, but it is not visually connected.

## Open Decomposition Work

`VoiceCallRuntime` still owns room reconciliation, command orchestration, lock coordination, and most terminal cleanup. Phase 3 is not complete until those paths are extracted behind tested coordinators and terminal paths are proven across device directions.

Related: [[Voice Calls]], [[Video Calls]], [[CallTerminalReconciler]].
