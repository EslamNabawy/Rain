# Open Bugs

## Critical

- PC-to-mobile voice/video call setup fails or fails immediately on mobile.
- Voice call hangup has been reported not closing on the other peer.
- Update prompt/check has been reported incorrect for old versions. Code mitigation now bumps metadata to `1.0.8+9`, covers previous `1.0.7+8`, published `rain-test-118-1`, and deployed/read back live Remote Config version 9. Still needs installed old/current app proof before moving to fixed.

## High

- Peers can appear online after app close until restart.
- Firebase permission denied can occur in production-like app use.
- Delete account has been reported acting like logout, password accepted -> loading -> back to Settings with no result, wrong password producing the same splash/back behavior, delete progress showing as a Settings-local splash while bottom navigation stayed usable, post-delete login saying only "Wrong password," a visible "Could not delete account" tombstone failure modal, and then a login-screen transition with stale RTDB listener permission-denied errors after Auth sign-out. Code mitigation on 2026-06-07 preserves the active session when the required tombstone fails, does not publish global runtime loading during wrong-password/pre-tombstone preflight, shows a modal delete error, separates optional RTDB cleanup from the required tombstone write, switches verified destructive deletion to a full-screen `deletingAccount` overlay with navigation hidden, records a same-device deleted-username marker for clearer login copy, cancels account-scoped RTDB listeners plus active protocol/data-room sessions before Firebase Auth deletion, and only clears local session after successful or post-tombstone destructive deletion. Live RTDB rules were deployed/read back with the legacy missing-uid tombstone branch; still needs the reported Android account retry before removing from watch.
- Diagnostics export has been reported failing. Code mitigation on 2026-06-07 bypasses the Android `file_picker 12.0.0-beta.3` `/document/...` double-write failure and catches legacy wrapper `FileSystemException('/document/12')`; still needs Android smoke evidence before removing from reported-bugs watch.
- ARMv7 app can become laggy.

## Medium

- Call UI safe-area and minimized/fullscreen behavior needs final polish.
- Sound/ringtone behavior has needed repeated correction.

Related: [[QA Findings]], [[BLOCKERS]].
