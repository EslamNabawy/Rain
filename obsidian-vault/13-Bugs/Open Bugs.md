# Open Bugs

## Critical

- PC-to-mobile voice/video call setup fails or fails immediately on mobile.
- Voice call hangup has been reported not closing on the other peer.
- Update prompt/check has been reported incorrect for old versions. Code mitigation now bumps metadata to `1.0.8+9`, covers previous `1.0.7+8`, published `rain-test-118-1`, and deployed/read back live Remote Config version 9. Still needs installed old/current app proof before moving to fixed.

## High

- Peers can appear online after app close until restart.
- Firebase permission denied can occur in production-like app use.
- Diagnostics export has been reported failing.
- ARMv7 app can become laggy.

## Medium

- Call UI safe-area and minimized/fullscreen behavior needs final polish.
- Sound/ringtone behavior has needed repeated correction.

Related: [[QA Findings]], [[BLOCKERS]].
