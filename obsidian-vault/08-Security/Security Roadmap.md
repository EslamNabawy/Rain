# Security Roadmap

Last updated: 2026-06-05

## Priority Work

1. [[Diagnostics Sanitization]]
2. [[Rules Strategy]]
3. Demo/stable release separation.
4. Firebase emulator deny-case tests.
5. Update manifest validation.

## Local Data At Rest

Decision: [[ADR-010]].

Current phase decision: accept plaintext local Drift/SQLite storage as an explicit product/security limitation. This closes SAR-005 only as a documentation and threat-model acceptance, not as encryption work.

Future encryption work must be a separate implementation plan before code changes. Minimum scope:

- encrypted database open path and dependency decision,
- key generation, storage, rotation, and loss behavior,
- migration from existing plaintext databases,
- rollback/failure behavior if migration is interrupted,
- tests proving old plaintext schemas migrate and data remains readable only through the intended app path,
- user-facing copy that does not overpromise before implementation.

Related: [[Privacy Review]], [[Risk Register]], [[Security Hardening Epic]].
