# Backpressure Strategy

## Current Model

Uses RTCDataChannel buffered amount with high/low watermarks and polling.

As of 2026-06-05 Phase 7, the app-level file sender checks `SessionManager.bufferedAmount(peerId, SessionChannel.file)` before every file chunk.

The shared contract lives in `packages/rain_core/lib/file_transfer/file_transfer_protocol.dart`:

- Chunk size: `fileTransferChunkBytes` = 32 KiB.
- High watermark: `fileTransferHighWatermarkBytes` = 4 MiB.
- Low watermark: `fileTransferLowWatermarkBytes` = 1 MiB.
- Poll interval: `fileTransferBackpressurePollInterval` = 25 ms.
- Timeout: `fileTransferBackpressureTimeout` = 30 seconds.

If the buffered amount is above the high watermark, sending pauses until the amount drains to the low watermark or the timeout expires. Runtime diagnostics record `send_backpressure_wait_started`, `send_backpressure_wait_completed`, and `send_backpressure_timeout` without file names, paths, or bytes.

`RainRuntimeController` exposes `fileTransferBufferPollInterval` and `fileTransferBufferTimeout` constructor parameters. Production defaults come from the shared protocol constants; tests can shorten them to prove timeout behavior deterministically without waiting 30 seconds.

## Target

- Keep high/low watermarks.
- Reduce polling pressure.
- Fail with clear congestion message after deadline.
- Record congestion diagnostics.

## Validation

Focused local proof added 2026-06-05:

- `friend_flow_test.dart` scripts buffered amounts above high watermark and then at low watermark, proving the sender waits before sending the binary file packet.
- `friend_flow_test.dart` scripts a permanently congested file channel with shortened runtime timing and proves the transfer fails with the congestion message before any binary packet is sent.
- `file_transfer_protocol_test.dart` locks high/low watermarks, poll interval, and timeout as a single protocol contract.

Related: [[Streaming Architecture]], [[File Transfer Optimization Epic]].
