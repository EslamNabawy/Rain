# Streaming Architecture

## Problem

Current outgoing file transfer performs repeated list copies. Current incoming path opens and closes a sink for each chunk.

Detailed implementation planning: [[File Transfer Runtime Refactor Plan]].

## Current Implementation

As of 2026-06-05 Phase 7, `apps/rain/lib/application/runtime/file_transfer_runtime.dart` keeps one `IOSink` per active incoming transfer and closes it on complete, cancel, failure, network loss, or shutdown.

Incoming chunks are written through the per-transfer sink and flushed so disk write failures surface at the chunk boundary. Hash mismatch, invalid chunks, cancellation, and write failures route through terminal transfer cleanup and delete the temp file when one exists.

Outgoing file sends now carry at most one partial chunk between `Stream<List<int>>` events. Full chunks are sent as `Uint8List` views over the source buffer where possible, avoiding the previous growable pending list plus front-removal copy loop.

## Target

- Sender slices stream chunks without front-removal lists.
- Receiver keeps a per-transfer sink open.
- Hashing and progress batching happen without blocking UI.

## Validation

Focused local proof added 2026-06-05:

- `friend_flow_test.dart` large incoming transfer verifies multiple chunks reuse one receive sink and complete with the expected file bytes.
- Hash mismatch, cancellation after a written chunk, and disk write failure tests verify terminal state plus temp cleanup.
- `file_transfer_protocol_test.dart` records the shared file-transfer chunk and backpressure contract constants.

Related: [[File Transfer Optimization Epic]], [[Backpressure Strategy]].
