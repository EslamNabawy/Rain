# Security Policy

## Reporting a Vulnerability

Rain is a public open-source project. **Do not open a public GitHub issue for security vulnerabilities.**

Use [GitHub private vulnerability reporting](https://github.com/EslamNabawy/Rain/security/advisories/new). If that is unavailable, contact the maintainer privately before disclosure.

Include:

- Affected commit/tag/branch
- Reproduction steps or proof of concept
- Impact (confidentiality, integrity, availability, privacy)
- Any suggested fix

You will get an acknowledgement when the maintainer is available. Please allow reasonable time for a fix before public disclosure.

## Supported Versions

Only the latest code on [`dev`](https://github.com/EslamNabawy/Rain/tree/dev) and the newest published release on the [Releases page](https://github.com/EslamNabawy/Rain/releases) are supported.

## Scope Notes

- Chat content and file bytes travel over WebRTC peer connections, not Firebase. Signaling payloads are encrypted (`v=2` per-pair when both peers published keys; `v=1` shared-key fallback remains decode-compatible). Firebase Realtime Database rules are the primary access control.
- Local Drift/SQLite storage is plaintext by accepted design (ADR-010). Do not report "no local database encryption" as a new finding; it is documented scope.
- Demo-channel builds use a committed demo keystore and public demo credentials (OpenRelay TURN, demo signaling key) by design. Production signing material lives only in GitHub Actions secrets.
- This repository is not a substitute for a formal third-party security audit.
