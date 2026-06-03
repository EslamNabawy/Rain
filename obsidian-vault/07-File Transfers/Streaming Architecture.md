# Streaming Architecture

## Problem

Current outgoing file transfer performs repeated list copies. Current incoming path opens and closes a sink for each chunk.

Detailed implementation planning: [[File Transfer Runtime Refactor Plan]].

## Target

- Sender slices stream chunks without front-removal lists.
- Receiver keeps a per-transfer sink open.
- Hashing and progress batching happen without blocking UI.

Related: [[File Transfer Optimization Epic]], [[Backpressure Strategy]].
