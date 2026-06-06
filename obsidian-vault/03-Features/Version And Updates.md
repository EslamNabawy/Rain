# Version And Updates

## Purpose

Warn users when their app is outdated and block unsupported versions.

## Business Value

Prevents old builds from using incompatible Firebase rules or broken protocols.

## Technical Flow

- App reads current version/build/channel/platform from package/environment.
- Firebase Remote Config provides `rain_release_manifest_v1`.
- Result can be current, optional update, required update, stale remote policy, unavailable, or invalid config.
- Update destination is GitHub Releases.
- Required updates block at the root gate before login/home.
- Optional updates render from the root app surface before login/home and use the existing per-channel/platform/build dismissal key.
- If the installed app is newer than the Remote Config release policy, Rain reports `remotePolicyOutdated` instead of saying "up to date."
- The checked-in template currently advertises `1.0.8+9`, because `rain-test-116-1` and `rain-test-117-1` were both `1.0.7+8`; same-version artifacts cannot trigger version-based update warnings.
- Live Remote Config was deployed/read back on 2026-06-06 as version 9 after `rain-test-118-1` published matching `1.0.8+9` Android/Windows artifacts. Stable/demo Android/Windows now advertise `1.0.8+9`; legacy `min_required_version` is `1.0.8`.

## Edge Cases

- Old app with new minimum version.
- Latest version newer but minimum satisfied.
- Invalid remote manifest.
- Demo vs stable channel.
- Android build number mismatch.
- Installed app ahead of live Remote Config policy.
- New GitHub release tag but unchanged app version/build metadata.

## Known Issues

- 2026-06-03: Old app optional prompts now render from the root app surface, not only the signed-in home screen.
- 2026-06-03: Manual check no longer reports "up to date" when the installed app is newer than the release policy; it reports stale policy.
- Version parser currently treats invalid version parts as zero.
- 2026-06-06 diagnostics showed `remotePolicyOutdated` because the running app was `1.0.7+8` while live Remote Config still advertised `1.0.6+7`; this live deployment gap was fixed by deploying `rain-8fb4b` Remote Config version 8 at `2026-06-06T04:43:11Z`.
- 2026-06-06 follow-up: update warning still did not appear for `1.0.7+8` installs after `rain-test-117-1` because the published artifact and Remote Config policy were both still `1.0.7+8`. The app and manifests were bumped to `1.0.8+9`, regression coverage proves `1.0.7+8` installs are `updateRequired`, `Build Rain Apps` run 27062729519 published `rain-test-118-1`, and live Remote Config version 9 now advertises `1.0.8+9`.

## Testing Requirements

- Strict semver comparison.
- Build number comparison.
- Remote Config manifest parser.
- Required update root gate.
- Optional update banner dismissal.

Related: [[Deployment]], [[Launch Readiness]].
