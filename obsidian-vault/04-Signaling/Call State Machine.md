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

## Terminal Truth

Firebase terminal room state must clear both peers through [[CallTerminalReconciler]].

Related: [[Voice Calls]], [[Video Calls]], [[CallTerminalReconciler]].
