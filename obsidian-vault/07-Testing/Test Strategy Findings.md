# Test Strategy Findings

This note captures audit-derived testing findings. The canonical production test strategy is [[Test Strategy]].

## Existing Test Areas

- Unit tests for core protocol frames.
- Peer media connection tests.
- Voice signaling contract tests.
- Runtime guard tests.
- Widget tests for call surfaces, chat, settings, splash, sounds, update banner.
- Firebase emulator integration tests.
- Appium smoke harness was attempted but not stabilized.

## Required High-Priority Tests

- PC-to-mobile voice call simulated signaling path.
- PC-to-mobile video call simulated signaling path.
- Stale lock repair before busy message.
- Firebase permission denied classification.
- Old app version update prompt.
- Presence expiry after app close.
- File transfer large-file performance.

## Manual Gates

Manual real-device gates are still required for WebRTC behavior. Unit tests cannot prove microphone, camera, Bluetooth, TURN, and NAT behavior fully.

Related: [[Coverage Report]], [[QA Findings]], [[Launch Readiness]].
