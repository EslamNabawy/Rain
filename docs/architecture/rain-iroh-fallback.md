# Rain Iroh Fallback Architecture

## Summary
Rain uses WebRTC first. Iroh is a feature-flagged QUIC fallback when WebRTC fails on mobile data, VPN, or difficult NAT.

## Data Boundaries
Firebase carries auth, presence, friendships, encrypted WebRTC signaling, and encrypted Iroh address payloads only. Firebase never carries chat bodies, ACKs, or file bytes.

## Transport Order
1. WebRTC staged ICE.
2. Iroh QUIC fallback.
3. Local queued/failed state.

## Truth Rules
Delivered means peer ACK arrived. File completed means receiver byte count and hash matched and receiver ACK arrived.

## Manual Smoke
1. Android and Windows same Wi-Fi: connect should show Direct.
2. Android mobile data to Windows Wi-Fi: WebRTC may fail, Iroh should connect or show precise Iroh failure.
3. Android mobile data plus VPN: Iroh should connect through relay or show precise relay/path failure.
4. Send messages both directions; no fake Delivered.
5. Send file both directions; no missing received file after completed state.
