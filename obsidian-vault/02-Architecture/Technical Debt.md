# Technical Debt

Technical debt score: 72/100 risk.

## Critical Debt

- `VoiceCallRuntime` is a god object.
- `RainRuntimeController` owns many unrelated workflows.
- Firebase call lock lifecycle is too distributed.
- Call UI and runtime state names blur signaling and media phases.

## High Debt

- Missing Drift indexes.
- Conversation streams are not paginated.
- File transfer chunk handling causes allocation and I/O pressure.
- Firebase rules are too complex to reason about without exhaustive emulator tests.
- Update validation accepts malformed versions too easily.

## Medium Debt

- Weak analyzer settings.
- Duplicated CI workflow logic.
- Large presentation files make UI regressions likely.
- Diagnostics error strings need stronger sanitization.

Related: [[Prioritized Remediation Roadmap]], [[Open Bugs]], [[Launch Readiness]].
