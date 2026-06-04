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
- File transfer presentation watches the live peer connection lane. When the lane is no longer connected, transfer speed samples reset so stale progress/speed state does not survive route or connection churn.

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
- Disconnect/reconnect while transfer views are visible.

Related: [[Peer Chat]], [[Technical Debt]].
