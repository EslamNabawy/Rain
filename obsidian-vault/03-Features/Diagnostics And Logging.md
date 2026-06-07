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
- Debug signaling write failures include sanitized operation context. ICE failures include a path template such as `rooms/{roomId}/callerICE/{candidateId}` or `rooms/{roomId}/calleeICE/{candidateId}`, not the real room id or candidate payload.
- `lastCrash.context` is exported after sanitizer processing so crash records keep useful non-secret failure metadata even when older debug events are trimmed.
- Diagnostics export includes summaries.
- Diagnostics export preserves the 200-record recent event window after sanitizer processing. The generic sanitizer still caps nested lists, but the top-level `events` array must not be reduced to 20 records because call failures often age behind heartbeat/UI events.
- Voice-call failure taxonomy separates a callee terminal busy response (`peer_busy_response`) from a real active Firebase voice lock conflict (`real_busy_lock`).
- Diagnostics export passes bytes to the platform picker. On Android, Rain bypasses the `file_picker 12.0.0-beta.3` Dart wrapper and sends bytes through the plugin method channel because that wrapper can return `/document/...` and then reopen it through `dart:io`. SAF handles such as `content://...`, `/document/...`, `/tree/...`, and newline-split picker handles such as `/\ndocument/...` are platform-managed documents, not filesystem paths.
- If a legacy picker wrapper still throws a `FileSystemException` for a platform-managed handle, Rain writes a real fallback JSON copy under the diagnostics export folder instead of surfacing `PathNotFoundException`.

## Privacy Rules

- No raw SDP.
- No raw ICE candidate strings.
- No raw Firebase room ids in path diagnostics; use templates or pseudonyms.
- No message text.
- No file bytes.
- No passwords, tokens, secrets, credentials.

## Known Risks

- Raw `error.toString()` and stack traces are still stored for fatal crash records.

## Testing Requirements

- Sanitization.
- Event caps and trimming.
- Top-level event export window preservation after recursive sanitizer processing.
- Busy-response versus busy-lock taxonomy.
- Export after fatal error.
- Export through Android scoped-storage picker handles, including the `file_picker 12.0.0-beta.3` `/document/...` double-write regression.
- No sensitive payload leaks.

Related: [[Security Review]], [[Monitoring]], [[Incident Response]].
