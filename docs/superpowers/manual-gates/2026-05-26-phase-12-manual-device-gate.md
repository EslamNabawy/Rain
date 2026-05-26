# Phase 12 Manual Device Gate

Status: pending real-device execution
Created: 2026-05-26 10:34 Africa/Cairo
Baseline branch: dev
Baseline validation: Phase 11 passed `dart pub get`, `dart run melos run analyze`, and `dart run melos run test`.

## Gate Rule

Do not mark Phase 12 complete and do not start the final release gate until the checks below pass on real devices or every failure is documented with an accepted release decision.

This gate cannot be proven by unit tests. It needs at least:

- Windows PC signed in as user A.
- Android ARM64 phone signed in as user B.
- Android ARMv7 phone signed in as user C, if available.

## Build Under Test

Fill before running:

```text
Git commit:
APK v7a file:
APK v8/v9 file:
Windows EXE/package:
Firebase project/environment:
TURN configuration:
Tester:
Start time:
End time:
```

## Device Inventory

| Role | Username | Device model | OS/version | Build installed | Network | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| User A |  | Windows PC |  |  |  |  |
| User B |  | Android ARM64 |  |  |  |  |
| User C |  | Android ARMv7 |  |  |  | Optional |

## Preflight

- [ ] All devices have the same build under test.
- [ ] All users are accepted friends with each other where tested.
- [ ] All apps are open and foregrounded unless a step explicitly closes one app.
- [ ] Microphone permission granted on Android devices.
- [ ] Camera permission granted for video steps.
- [ ] Firebase active call locks are clean before starting:
  - `activeVoiceUsers`
  - `activeVoicePairs`
- [ ] Diagnostics export path is known on every device.

## Step 1: PC To Phone Voice

Run 10 iterations.

Script:

```text
PC starts voice call to Android.
Android accepts.
Talk for 15 seconds.
Mute/unmute once.
Hang up from PC on odd runs.
Hang up from Android on even runs.
Immediately start a new call in the opposite direction.
```

Pass criteria:

- [ ] No false peer busy.
- [ ] No stuck ringing.
- [ ] No failed hangup.
- [ ] No call duration stuck at zero.
- [ ] Mute state does not flicker.
- [ ] Firebase `activeVoiceUsers` is clean after each terminal call.
- [ ] Firebase `activeVoicePairs` is clean after each terminal call.

Results:

| Iteration | Caller | Hangup side | Result | Notes |
| --- | --- | --- | --- | --- |
| 1 | PC | PC |  |  |
| 2 | PC | Android |  |  |
| 3 | PC | PC |  |  |
| 4 | PC | Android |  |  |
| 5 | PC | PC |  |  |
| 6 | PC | Android |  |  |
| 7 | PC | PC |  |  |
| 8 | PC | Android |  |  |
| 9 | PC | PC |  |  |
| 10 | PC | Android |  |  |

## Step 2: Phone To PC Voice

Run 10 iterations with caller/callee reversed.

Pass criteria:

- [ ] First attempt succeeds when both apps are open and online.
- [ ] Retry is not needed for the normal path.
- [ ] If a failure occurs, diagnostics state exact cause.
- [ ] Firebase call locks are clean after each terminal call.

Results:

| Iteration | Caller | Hangup side | Result | Notes |
| --- | --- | --- | --- | --- |
| 1 | Android | Android |  |  |
| 2 | Android | PC |  |  |
| 3 | Android | Android |  |  |
| 4 | Android | PC |  |  |
| 5 | Android | Android |  |  |
| 6 | Android | PC |  |  |
| 7 | Android | Android |  |  |
| 8 | Android | PC |  |  |
| 9 | Android | Android |  |  |
| 10 | Android | PC |  |  |

## Step 3: PC To Phone Video

Run 5 iterations.

Script:

```text
PC starts video call to Android.
Android accepts.
Remote video is primary.
Local preview is small.
Tap preview swaps.
Fullscreen shows status strip and controls.
Exit fullscreen restores popup/minimized correctly.
```

Pass criteria:

- [ ] No crash.
- [ ] Remote video is primary by default.
- [ ] Local preview is small.
- [ ] Preview tap swaps primary/preview.
- [ ] Fullscreen is a full call workspace, not raw stretched video.
- [ ] Controls stay visible in fullscreen.
- [ ] Popup/minimized state restores correctly.
- [ ] Firebase call locks are clean after hangup.

Results:

| Iteration | Result | Notes |
| --- | --- | --- |
| 1 |  |  |
| 2 |  |  |
| 3 |  |  |
| 4 |  |  |
| 5 |  |  |

## Step 4: Phone To PC Video

Run 5 iterations with caller/callee reversed.

Pass criteria:

- [ ] No crash.
- [ ] No duplicate manager bar.
- [ ] No raw stretched video-only fullscreen.
- [ ] No flip-camera control on a single-camera PC.
- [ ] Call can end from either side.
- [ ] Firebase call locks are clean after hangup.

Results:

| Iteration | Result | Notes |
| --- | --- | --- |
| 1 |  |  |
| 2 |  |  |
| 3 |  |  |
| 4 |  |  |
| 5 |  |  |

## Step 5: ARMv7 Smoke

Run on ARMv7 if available.

Script:

```text
Open app.
Scroll friends.
Open chat.
Pull refresh.
Connect peer.
Open voice call UI.
Open video call UI if hardware supports it.
Hang up.
```

Pass criteria:

- [ ] No visible freeze longer than 500 ms.
- [ ] No repeated dropped-frame bursts during simple scroll.
- [ ] No stuck call controls.
- [ ] Pull refresh does not freeze.
- [ ] Voice call UI remains responsive.
- [ ] Video UI is hidden or degraded cleanly if hardware cannot support it.

Results:

```text
ARMv7 device:
Build:
Result:
Notes:
```

## Failure Report Template

Create one block per failure and attach diagnostics from both peers.

```text
Failure ID:
Caller username:
Callee username:
Device model:
Platform:
Build name:
Call direction:
Media mode:
Error message:
Local time:
Expected behavior:
Actual behavior:
Firebase room id:
Firebase activeVoiceUsers state:
Firebase activeVoicePairs state:
Diagnostics files:
Decision: unresolved / accepted risk / fixed and retested
```

## Release Decision

Complete only after all required steps are filled.

```text
Manual gate result: pending / pass / fail
Accepted failures:
Release allowed: yes / no
Approver:
Date:
```
