# Rain File Transfer Resume V2 Note

## Status
Deferred. V1 remains fail-clear only: if the peer link or internet route drops during transfer, Rain cancels the active transfer and shows `Connection lost. Transfer canceled.` or the more specific network-loss message.

## Goal
Make file transfer resumable after the reliability pass is stable, without weakening the manual-connect rule or moving file bytes into Firebase.

## Direction
- Keep files peer-to-peer over the `rain.file` RTC data channel.
- Split files into content-addressed chunks with deterministic indexes.
- Persist a transfer manifest locally: transfer id, file hash, chunk size, total chunks, accepted chunks, verified bytes, original metadata, and peer id.
- Receiver writes chunks to a temp file and tracks verified chunk ranges before atomic completion.
- Sender can resume only after a fresh manual Connect and a receiver `resume.request` frame.
- Receiver must validate file id, size, chunk count, and per-chunk hash before accepting resumed bytes.
- Completed files remain app-private until the user explicitly saves them to device storage.

## Non-Goals
- No background transfers.
- No automatic reconnect to resume.
- No Firebase/Supabase file bytes.
- No multi-file batch resume until one-file resume is reliable.

## Risks To Solve First
- Chunk manifests must not become unbounded local storage.
- Partially received files need cleanup on reject, block, unfriend, logout, and app close.
- Resume must never mark a file completed until the final byte count and hashes match.
- UI must be honest: `Paused`, `Resume available`, `Failed`, and `Completed` are different states.
