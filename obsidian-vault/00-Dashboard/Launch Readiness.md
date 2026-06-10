# Launch Readiness

Last updated: 2026-06-05

## Decision

Rain is not ready for public production launch.

## Reasons

- Call reliability is not stable enough.
- Presence and connection recovery still have stale-state failure modes.
- Update validation is not trusted yet.
- Firebase rules are strict but complex, increasing permission-denied risk.
- Local database needs indexes and pagination before large user data.
- Local database content is plaintext by accepted current scope; launch/privacy material must not imply local database encryption.
- File transfers need stronger streaming/backpressure implementation.
- Real device matrix testing is incomplete.
- Release workflow structure is locally unified, but a fresh cloud release run is still required before any specific artifact is release-proven.

## Launch Gate Checklist

- [ ] PC-to-mobile voice call succeeds repeatedly.
- [ ] PC-to-mobile video call succeeds repeatedly.
- [ ] Mobile-to-PC voice/video succeeds repeatedly.
- [ ] Failed calls release every call lock and room artifact.
- [ ] App update prompt works for old stable and old demo builds.
- [ ] Firebase rules emulator tests cover all legal and illegal call transitions.
- [ ] Drift indexes and migration are added.
- [ ] File transfer performance is acceptable for 100 MB.
- [ ] Diagnostics export works after fatal errors.
- [ ] Release, support, and privacy copy avoid local message encryption claims unless [[ADR-010]] is superseded by implemented encryption.
- [ ] Release workflow publishes Android v7a, Android v8/v9, Windows artifacts, and `rain-release-metadata.json` from a passing cloud gate.

## Accepted Security Scope

Rain may continue internal/test release work with plaintext local Drift/SQLite storage only if the release copy is honest about the limitation. Local device compromise is not protected by current app-layer encryption. Future public claims of encrypted local history require a separate encrypted-storage implementation with key management and migration evidence.

Related notes: [[Risk Register]], [[Risk Matrix]], [[BLOCKERS]], [[Blocker Resolution Plan]], [[QA Findings]], [[Technical Debt]], [[Deployment]].
