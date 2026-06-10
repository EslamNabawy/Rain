# Privacy Review

Last updated: 2026-06-05

## Current Privacy Position

Rain has local diagnostics export and no remote telemetry by default.

As of 2026-06-05, diagnostics export uses a central recursive sanitizer before storage/export. It pseudonymizes identifiers, usernames, Firebase paths, local paths, and file names; redacts message-like content, secrets, SDP, ICE candidates, ciphertext, nonces, MACs, and file bytes; and keeps support-safe metadata such as category, severity, status, operation, provider type, counters, and failure taxonomy.

Rain does not currently provide app-layer encryption for the local Drift/SQLite database. Local messages, queued outgoing messages, file-transfer names, and local file paths are stored as normal local database fields. A compromised device, unlocked OS account, malware process with filesystem access, or forensic copy of the app data directory is outside the protection currently implemented by Rain.

## Sensitive Data

Do not store in diagnostics:

- password
- tokens
- raw SDP
- raw ICE candidates
- ciphertext payloads
- message text
- file bytes

## Local Data At Rest

Decision: [[ADR-010]] selected Option A on 2026-06-05.

Current implementation:

- `messages.content` stores chat and file-message content in Drift/SQLite.
- `queued_messages.content` stores outgoing queued message content in Drift/SQLite.
- `file_transfers.fileName` and `file_transfers.localPath` store file metadata and local paths in Drift/SQLite.
- The database open path uses normal Drift native SQLite setup with WAL, busy timeout, synchronous mode, and foreign keys; it does not configure a database encryption key.

Threat model statement:

- Rain protects private communication through accepted-friend rules, Firebase Auth/RTDB authorization, WebRTC transport behavior, encrypted signaling envelopes where implemented, and sanitized local diagnostics.
- Rain does not currently protect local database contents from a compromised device or an attacker with direct access to the app data directory.
- Product, security, support, and release notes must not claim local message encryption, encrypted local history, or encrypted file metadata unless a future encryption implementation lands with migration proof.
- If local device compromise becomes in scope, implement Option B as a separate phase with database encryption, key storage and rotation policy, plaintext migration, failed-migration recovery, and tests proving old plaintext stores migrate safely.

## Risk

Raw error strings and stack traces are now sanitized before diagnostics storage/export, but new diagnostic fields can still create privacy risk if they introduce private content under unrecognized keys. Any new diagnostics payload carrying identifiers, paths, message content, signaling frames, files, or secrets needs a sanitizer regression test.

Local data at rest remains plaintext by explicit acceptance until a future encryption phase is approved.

Related: [[Diagnostics Sanitization]], [[Security Roadmap]].
