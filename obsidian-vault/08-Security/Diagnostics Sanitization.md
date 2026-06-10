# Diagnostics Sanitization

## Required Work

- [x] Sanitize `error.toString()` before diagnostics export.
- [x] Sanitize stack strings where possible without destroying debugging value.
- [x] Keep denylist recursive for context.
- [x] Add tests with SDP, ICE candidate, token, password, and message text samples.

## Current Implementation

As of 2026-06-05, diagnostics sanitization is centralized in `DiagnosticsSanitizer`.

Coverage:

- Pseudonymizes peer ids, call ids, room ids, usernames, callers/callees, pair ids, file names, filesystem paths, and Firebase paths.
- Redacts password/token/credential/secret/API-key material, chat/message-like content, raw SDP, raw ICE candidates, ciphertext, nonces, MACs, and file bytes.
- Recurses through maps/lists with bounded depth and item count.
- Sanitizes crash records, debug events, event coalescing keys, write-failure debug output, and the final export payload.
- Keeps diagnostic metadata such as category, name, severity, provider type, status, operation, phase, taxonomy, and counters usable for support.

Known boundary:

- Sanitization is local best-effort string and schema sanitization. New diagnostic fields that carry private content must either use an existing sensitive key pattern or add a focused sanitizer regression before shipping.

## Failure Taxonomy

`CallErrorClassifier.failureTaxonomy` now separates:

- `firebase_permission_denied`
- `media_permission_denied`
- `ice_failed`
- `turn_unavailable`
- `room_terminal`
- `stale_lock_repaired`
- `malformed_remote_data`
- existing presence, busy, timeout, rules, and unknown buckets.

## Evidence 2026-06-05

Focused Phase 4 validation passed:

```powershell
flutter test test\crash_diagnostics_service_test.dart test\rain_debug_log_service_test.dart test\call_error_classifier_test.dart --reporter expanded
```

## Definition Of Done

- [x] No sensitive sample appears in exported diagnostics for the covered samples.
- [x] Fatal crash records still preserve useful source and taxonomy.

Related: [[Diagnostics And Logging]], [[Privacy Review]], [[CallDiagnosticsRecorder]].
