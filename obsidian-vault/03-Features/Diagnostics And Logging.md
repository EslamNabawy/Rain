# Diagnostics And Logging

## Purpose

Capture local debugging context for user-reported bugs without remote telemetry.

## Business Value

Improves bug reproduction for WebRTC, Firebase, UI state, and runtime failures.

## Technical Flow

- `CrashDiagnosticsService` captures errors and local event logs.
- `RainDebugLogService` provides a debug facade.
- Riverpod observer logs provider transitions.
- Debug signaling adapter logs Firebase/API operation metadata.
- Diagnostics export includes summaries.

## Privacy Rules

- No raw SDP.
- No raw ICE candidate strings.
- No message text.
- No file bytes.
- No passwords, tokens, secrets, credentials.

## Known Risks

- Raw `error.toString()` and stack traces are still stored for fatal crash records.

## Testing Requirements

- Sanitization.
- Event caps and trimming.
- Export after fatal error.
- No sensitive payload leaks.

Related: [[Security Review]], [[Monitoring]], [[Incident Response]].
