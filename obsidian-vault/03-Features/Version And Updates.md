# Version And Updates

## Purpose

Warn users when their app is outdated and block unsupported versions.

## Business Value

Prevents old builds from using incompatible Firebase rules or broken protocols.

## Technical Flow

- App reads current version/build/channel/platform from package/environment.
- Firebase Remote Config provides `rain_release_manifest_v1`.
- Result can be current, optional update, required update, unavailable, or invalid config.
- Update destination is GitHub Releases.

## Edge Cases

- Old app with new minimum version.
- Latest version newer but minimum satisfied.
- Invalid remote manifest.
- Demo vs stable channel.
- Android build number mismatch.

## Known Issues

- User reported old app did not show update prompt.
- User reported check update said current even when latest/current text differed.
- Version parser currently treats invalid version parts as zero.

## Testing Requirements

- Strict semver comparison.
- Build number comparison.
- Remote Config manifest parser.
- Required update root gate.
- Optional update banner dismissal.

Related: [[Deployment]], [[Launch Readiness]].
