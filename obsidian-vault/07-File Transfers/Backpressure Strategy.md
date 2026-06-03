# Backpressure Strategy

## Current Model

Uses RTCDataChannel buffered amount with high/low watermarks and polling.

## Target

- Keep high/low watermarks.
- Reduce polling pressure.
- Fail with clear congestion message after deadline.
- Record congestion diagnostics.

Related: [[Streaming Architecture]], [[File Transfer Optimization Epic]].
