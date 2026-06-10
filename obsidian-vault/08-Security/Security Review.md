# Security Review

Last updated: 2026-06-05

Security score: 66/100.

## Strengths

- Firebase rules default deny.
- SDP/ICE/call frames use encrypted envelopes.
- Context sanitization redacts known sensitive keys.
- Users are scoped through Firebase Auth and username ownership checks.
- Blocks are checked in many write paths.

## Risks

- RTDB rules are very complex and hard to audit manually.
- Client-side lock orchestration can produce stale or orphaned state.
- Fatal diagnostics store raw error strings and stack traces.
- Local Drift/SQLite data is plaintext by current design; message history, queued message content, file names, and local file paths are not protected from device compromise by app-layer encryption.
- Demo keystore/config artifacts must never be confused with production.
- Firebase project config is checked in, which is normal for Firebase clients but still should be treated as public.

## Required Security Work

- Emulator tests for every allowed/denied rule branch.
- Error string redaction.
- Separate demo/stable channels and clear release labels.
- Confirm production builds reject demo signaling keys.
- Keep release/support/privacy claims aligned with [[ADR-010]] until local database encryption is implemented and migration-tested.

Related: [[Permissions Matrix]], [[Risk Register]], [[Diagnostics And Logging]].
