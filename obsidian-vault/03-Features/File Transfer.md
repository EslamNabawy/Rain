# File Transfer

## Purpose

Transfer files between accepted friends over WebRTC data channel.

## Business Value

Private peer-to-peer file movement without a cloud file store.

## Technical Flow

- Sender creates file offer.
- Receiver accepts or rejects.
- File is chunked and sent over file data channel.
- Progress is stored in Drift.
- Receiver writes chunks to a per-transfer temporary file sink and exports/saves completed files only after byte count and SHA-256 verification.
- File transfer presentation watches the live peer connection lane. When the lane is no longer connected, transfer speed samples reset so stale progress/speed state does not survive route or connection churn.

## Runtime Contract

As of 2026-06-05 Phase 7:

- Incoming accepted transfers keep one open temp-file `IOSink` per transfer.
- Complete, cancel, failure, network loss, and runtime shutdown close active receive sinks.
- Hash mismatch, disk write failure, invalid chunks, and cancellation delete temp files when a temp file exists.
- Outgoing sends avoid the previous growable pending list and carry only one partial chunk between source stream events.
- Sender-side file-channel congestion uses the shared high/low watermark contract in [[Backpressure Strategy]].

## Dependencies

- WebRTC data channel
- `rain_core` file transfer protocol
- Drift `file_transfers`

## Edge Cases

- File too large.
- Peer disconnect.
- Data channel congestion.
- Receiver cancels.
- Transfer conflicts with active calls.

## Known Issues

- Local runtime proof now covers persistent receive sinks, bounded send chunk assembly, hash mismatch cleanup, cancel cleanup, disk write failure, and scripted sender backpressure.
- Remaining confidence gap is device-scale/real-network proof for very large files under slow receiver conditions.

## Testing Requirements

- Large file transfer.
- Congestion backpressure.
- Cancel and retry.
- Disconnect mid-transfer.
- Disconnect/reconnect while transfer views are visible.

Related: [[Peer Chat]], [[Technical Debt]].
