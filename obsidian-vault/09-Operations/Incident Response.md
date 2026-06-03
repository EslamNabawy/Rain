# Incident Response

## First Response

1. Ask for diagnostics export.
2. Identify app version, build, channel, platform.
3. Identify fatal error and latest network/call summaries.
4. Check whether Firebase rules changed after the build.
5. Reproduce with latest artifacts.

## Common Incident Classes

- Firebase permission denied.
- Call setup failed.
- Peer busy but no active call.
- Presence stale.
- Update prompt missing.
- Diagnostics export failed.

## Required Fix Discipline

- Do not guess.
- Capture logs.
- Classify failure by subsystem.
- Add regression test before release.

Related: [[QA Findings]], [[Risk Register]], [[Diagnostics And Logging]].
