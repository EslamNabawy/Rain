# Security Review

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
- Demo keystore/config artifacts must never be confused with production.
- Firebase project config is checked in, which is normal for Firebase clients but still should be treated as public.

## Required Security Work

- Emulator tests for every allowed/denied rule branch.
- Error string redaction.
- Separate demo/stable channels and clear release labels.
- Confirm production builds reject demo signaling keys.

Related: [[Permissions Matrix]], [[Risk Register]], [[Diagnostics And Logging]].
