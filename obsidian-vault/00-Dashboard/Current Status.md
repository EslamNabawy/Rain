# Current Status

Last updated: 2026-06-03

## Repository State

- Active working repo: `C:\Users\eslam\OneDrive\Desktop\GoodStuff\Rain`
- Current branch observed during audit: `dev`
- Branch state observed: ahead of `origin/dev` by one commit
- The old project folder `D:\old project\Rain` must not be edited.

## Working Areas

- Flutter app structure exists for Android and Windows.
- Riverpod state management is used.
- Firebase Auth, Realtime Database, and Remote Config are integrated.
- Drift local database exists.
- WebRTC data and media layers exist through `peer_core`.
- Automated tests exist across app, `rain_core`, `protocol_brain`, and `peer_core`.
- GitHub workflows exist for CI, merge gates, release builds, and direct test downloads.

## Unstable Areas

- Voice/video calls still have reported PC-to-mobile failures.
- Call state can be misleading because signaling, lock, and media failures collapse into similar UI messages.
- Presence can be stale after app close or network loss.
- Update checks have been reported as not showing old-version prompts correctly.
- File transfer implementation can cause allocation and I/O pressure for large files.

## Documentation Status

This vault is now the main knowledge base. Older docs remain in `docs/`, but future source-of-truth updates should be mirrored here.
