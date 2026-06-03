# QA Findings

## Repeated User-Reported Failures

- PC cannot reliably start voice/video call to phone.
- Mobile-to-PC video sometimes works while voice crashes or fails.
- Calls can fail and remain on a failed/stuck screen.
- Peers can appear online after app close until restart.
- Update prompt does not reliably warn old builds.
- Firebase permission denied has appeared in diagnostics.
- ARMv7 builds have shown lag.

## QA Interpretation

The failures point to distributed state and lifecycle problems, not a single syntax error. Main suspects:

- Firebase call lock ordering.
- RTDB rule/app payload mismatch.
- Media permission/device capture differences between PC and Android.
- ICE candidate write/read failures hidden as media failure.
- Presence freshness not reflected quickly enough in UI.

Related: [[Risk Register]], [[Open Bugs]], [[Test Strategy]].
