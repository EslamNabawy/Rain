# Launch Readiness

Last updated: 2026-06-03

## Decision

Rain is not ready for public production launch.

## Reasons

- Call reliability is not stable enough.
- Presence and connection recovery still have stale-state failure modes.
- Update validation is not trusted yet.
- Firebase rules are strict but complex, increasing permission-denied risk.
- Local database needs indexes and pagination before large user data.
- File transfers need stronger streaming/backpressure implementation.
- Real device matrix testing is incomplete.

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
- [ ] Release workflow publishes Android v7a, Android v8/v9, and Windows artifacts.

Related notes: [[Risk Register]], [[QA Findings]], [[Technical Debt]], [[Deployment]].
