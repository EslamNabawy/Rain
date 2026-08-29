# Diagnostics And Logging

Last updated: 2026-08-29

Last updated: 2026-08-29

## Purpose

Capture local debugging context for user-reported bugs without remote telemetry.

## Business Value

Improves bug reproduction for WebRTC, Firebase, UI state, and runtime failures.

## Technical Flow

- `CrashDiagnosticsService` captures errors and local event logs.
- `RainDebugLogService` provides a debug facade.
- Riverpod observer logs provider transitions. The 2026-08-29 slice uses `ThrottledProviderObserver` for `RainStartupApp`, which deduplicates by `Object.hashCode` on the new value and debounces two known-noisy provider names by 200 ms. The throttle key is `ProviderObserver.provider.runtimeType.toString()`.
- Debug signaling adapter logs Firebase/API operation metadata.
- Debug signaling write failures include sanitized operation context. ICE failures include a path template such as `rooms/{roomId}/callerICE/{candidateId}` or `rooms/{roomId}/calleeICE/{candidateId}`, not the real room id or candidate payload.
- `lastCrash.context` is exported after sanitizer processing so crash records keep useful non-secret failure metadata even when older debug events are trimmed.
- Diagnostics export includes summaries.
- Diagnostics export preserves the 200-record recent event window after sanitizer processing. The generic sanitizer still caps nested lists, but the top-level `events` array must not be reduced to 20 records because call failures often age behind heartbeat/UI events.
- Voice-call failure taxonomy separates a callee terminal busy response (`peer_busy_response`) from a real active Firebase voice lock conflict (`real_busy_lock`).
- Diagnostics export passes bytes to the platform picker. On Android, Rain bypasses the `file_picker 12.0.0-beta.3` Dart wrapper and sends bytes through the plugin method channel because that wrapper can return `/document/...` and then reopen it through `dart:io`. SAF handles such as `content://...`, `/document/...`, `/tree/...`, and newline-split picker handles such as `/\ndocument/...` are platform-managed documents, not filesystem paths.
- If a legacy picker wrapper still throws a `FileSystemException` for a platform-managed handle, Rain writes a real fallback JSON copy under the diagnostics export folder instead of surfacing `PathNotFoundException`.

## Trace Context (2026-08-29 slice)

`apps/rain/lib/infrastructure/diagnostics/tracing/` carries the trace-context overlay ([[ADR-011]], Phase 11 of [[Master Roadmap]]).

- `TraceContext` is a Zone-based OTel-lite. `TraceContext.create()` returns a `traceId` of the form `tr_{8 chars}_{ms in base36}` plus a `spanId`. `TraceContext.runAsync(ctx, fn)` propagates the context through Dart `runZoned`, so any code that runs inside the zone can read `TraceContext.current` and emit `traceId`/`spanId` in `log.event` context.
- `IdentityController.register` wraps the registration body in `TraceContext.runAsync`, so `register_started`, `register_success`, `register_failed`, and the failure diagnostics share one `traceId` per registration attempt.
- `RainRuntimeController._startCall` (voice and video) wraps the entire start path in `TraceContext.runAsync`, so `start_requested`, `start_blocked`, `turn_unavailable_call_blocked`, `start_failed`, `fail_voice_call_failed`, and `created` all share one `traceId` per call.
- `AppNavigationObserver` is registered on the `GoRouter` `observers` list in `appRouterProvider`. It emits `interaction/navigation` with `action`, `from`, `to`, and (when active) the current `traceId`.
- `InteractionTrace.tap`, `InteractionTrace.input`, and `InteractionTrace.navigation` static helpers emit `interaction/*` events with the active `traceId`. `IdentityController.register` uses `InteractionTrace.tap('onboarding_submit_button', context: {username, displayNameLength})` before any backend write.
- `ThrottledProviderObserver` replaces `RainDebugProviderObserver` in `RainStartupApp` and gates `provider_updated` events on `Object.hashCode` change plus a 200 ms debounce for two known-noisy provider names.

The `voice_call_tracing_patch.dart` scaffold is intentionally not imported; its `VoiceFailureTaxonomy` enum competes with the 2026-06-08 `CallErrorClassifier`.

Scope cut for this slice: traceId is **not** added to heartbeat, presence watches, `createOutgoingCall`, `writeICE`, `writeVoiceOffer`, `writeVoiceAnswer`, or file transfer. Drift event persistence and the `/debug/traces` debug overlay are not implemented. See [[Risk Register|R-023]] and [[Technical Debt Register|TD-024]] for the residual gap and follow-up slices in [[Master Roadmap]] Phases 12-14.

## Privacy Rules

- No raw SDP.
- No raw ICE candidate strings.
- No raw Firebase room ids in path diagnostics; use templates or pseudonyms.
- No message text.
- No file bytes.
- No passwords, tokens, secrets, credentials.
- Tap targets are logical names, not raw pixels; the tap emitter must not include the pressed widget tree beyond the configured `target` key.

## Known Risks

- Raw `error.toString()` and stack traces are still stored for fatal crash records.
- `ThrottledProviderObserver` uses `Object.hashCode` and a hardcoded `runtimeType` key. Identity-equal updates can still emit, and `hashCode` collisions across distinct values can silently drop legitimate updates. Documented in R-023.

## Testing Requirements

- Sanitization.
- Event caps and trimming.
- Top-level event export window preservation after recursive sanitizer processing.
- Busy-response versus busy-lock taxonomy.
- Export after fatal error.
- Export through Android scoped-storage picker handles, including the `file_picker 12.0.0-beta.3` `/document/...` double-write regression.
- No sensitive payload leaks.
- New tracing tests (deferred): tap + `traceId` propagation through `register` and `_startCall`; provider throttle dedupe behavior.

Related: [[Security Review]], [[Monitoring]], [[Incident Response]], [[ADR-011]], [[Risk Register|R-023]], [[Technical Debt Register|TD-024]].
