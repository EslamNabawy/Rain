# CallDiagnosticsRecorder

## Purpose

Provide consistent, sanitized call diagnostics.

## Responsibilities

- Standard event names.
- Failure taxonomy.
- Sanitized context.
- Operation durations.
- Call summaries.
- No raw SDP, ICE, message text, or secrets.

## Required Taxonomy

- presence offline
- presence unknown
- lease claim failed
- stale lock repaired
- permission denied
- ICE candidate write failed
- media negotiation failed
- TURN unavailable
- renderer failed

Related: [[Diagnostics Sanitization]], [[VoiceCallRuntime Refactor]], [[Security Roadmap]].
