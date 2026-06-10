# CallStartCoordinator

## Purpose

Own call start eligibility and start-phase transitions.

## Responsibilities

- Accepted-friend validation.
- Fresh presence preflight.
- Active call/file conflict check.
- Manual disconnect and recovery intent check.
- Emit explicit phases: checking presence, checking conflicts, claiming lease, preflighting media.

## Interfaces

- Input: peer id, media mode, current runtime guard snapshot.
- Output: typed start decision and next action.

## Tests

- Offline peer blocks call.
- Presence unknown blocks call.
- Online but disconnected chat lane allows call.
- Active file blocks call.
- Active call blocks new call.

Related: [[VoiceCallRuntime Refactor]], [[CallLeaseManager]], [[CallDiagnosticsRecorder]].
