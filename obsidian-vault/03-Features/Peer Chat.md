# Peer Chat

## Purpose

Send text messages between accepted friends over WebRTC data channels.

## Business Value

Core private messaging feature.

## Technical Flow

- Messages are composed in `rain_core`.
- Message envelopes include sequence and status.
- WebRTC data channel `rain.chat` carries messages.
- Control and ACK frames use `rain.ctrl`.
- Drift stores messages and sequence tracking.

## Database Impact

- `messages`
- `queued_messages`
- `message_seq_tracker`

## Edge Cases

- Duplicate message IDs.
- Sequence gaps.
- Offline queue retry.
- Peer disconnect during send.

## Known Issues

- Conversation watch is full-list, not paginated.
- Database indexes are missing for conversation ordering.

Related: [[Database Architecture]], [[File Transfer]].
