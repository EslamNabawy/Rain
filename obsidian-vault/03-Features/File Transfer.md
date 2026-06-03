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
- Receiver writes chunks to a temporary file and exports/saves completed files.

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

- Current runtime opens/closes file sink per chunk.
- Current sender path creates repeated list copies.

## Testing Requirements

- Large file transfer.
- Congestion backpressure.
- Cancel and retry.
- Disconnect mid-transfer.

Related: [[Peer Chat]], [[Technical Debt]].
