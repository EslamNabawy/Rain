# CallDiagnosticsRecorder

## Purpose

Provide consistent, sanitized call diagnostics.

## Responsibilities

- Standard event names.
- Failure taxonomy.
- Sanitized context.
- Operation durations.
- Call summaries.
- Firebase room status timeline for setup and terminal paths.
- No raw SDP, ICE, message text, or secrets.

## Current Implementation Notes

- Runtime keeps a bounded per-call room status timeline and copies it into `VoiceCallDiagnostics`.
- Terminal Firebase room reconciliation records diagnostics for failed remote setup paths, even when the local side did not own the low-level media error.
- Diagnostics must remain metadata-only; room timelines use status names only.

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
