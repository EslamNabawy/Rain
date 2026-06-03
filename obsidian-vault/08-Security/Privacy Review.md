# Privacy Review

## Current Privacy Position

Rain has local diagnostics export and no remote telemetry by default.

## Sensitive Data

Do not store in diagnostics:

- password
- tokens
- raw SDP
- raw ICE candidates
- ciphertext payloads
- message text
- file bytes

## Risk

Raw error strings and stack traces can still include unintended details.

Related: [[Diagnostics Sanitization]], [[Security Roadmap]].
