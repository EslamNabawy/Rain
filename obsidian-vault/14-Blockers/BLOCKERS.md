# BLOCKERS

Last updated: 2026-06-03

## Active Blockers

### WebRTC Call Reliability

- Type: technical
- Severity: critical
- Impact: blocks public launch
- Details: PC-to-mobile voice/video calls have repeatedly failed. Current implementation has many pieces, but state ordering and failure classification remain fragile.
- Workaround: use diagnostics and emulator tests to isolate permission, signaling, ICE, TURN, and media failures.

### Firebase Permission Denied

- Type: backend/security rules
- Severity: high
- Impact: users cannot complete actions if rules and app payload diverge.
- Workaround: deploy tested rules, add emulator contract tests, classify RTDB permission failures separately.

### Update Prompt Reliability

- Type: product/runtime
- Severity: high
- Impact: old apps may keep using incompatible backend rules.
- Workaround: strict Remote Config manifest tests and required-update root gate verification.

### Real Device Confidence

- Type: QA
- Severity: high
- Impact: unit/widget tests do not prove camera, microphone, NAT, Bluetooth, or Windows device behavior.
- Workaround: maintain direct artifacts and repeat Android/Windows smoke checks.
