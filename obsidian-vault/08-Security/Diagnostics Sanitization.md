# Diagnostics Sanitization

## Required Work

- Sanitize `error.toString()` before diagnostics export.
- Sanitize stack strings where possible without destroying debugging value.
- Keep denylist recursive for context.
- Add tests with SDP, ICE candidate, token, password, and message text samples.

## Definition Of Done

- No sensitive sample appears in exported diagnostics.
- Fatal crash records still preserve useful source and taxonomy.

Related: [[Diagnostics And Logging]], [[Privacy Review]], [[CallDiagnosticsRecorder]].
