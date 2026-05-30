# Rain Signaling Security Model

Rain uses Firebase Realtime Database as a signaling mailbox. Firebase is not a
media relay. Chat data channels, voice, video, and file bytes are transported by
WebRTC after peers complete signaling.

## What Is Encrypted

Rain app-encrypts signaling payload bodies before writing them to Firebase:

- direct peer SDP offers
- direct peer SDP answers
- direct peer ICE candidates
- voice/video SDP control frames
- voice/video ICE candidates

The current envelope uses `A256GCM-HKDF-SHA256`. New envelopes authenticate the
following context with AES-GCM additional authenticated data:

- schema/envelope version
- room or call id
- signaling purpose
- sender username
- receiver username
- timestamp

This prevents a valid encrypted signaling payload from being replayed into a
different room, purpose, sender, or receiver context without failing decryption.
Legacy encrypted envelopes that were created before sender/receiver binding are
still readable so stale signaling data does not crash migration clients.

## What Firebase Can Still See

Firebase and authorized database readers can still see metadata required for
routing and rule enforcement:

- usernames participating in a room or call
- room ids, call ids, pair ids, and lock paths
- call status, timestamps, expiry fields, and presence state
- envelope size and write timing

Firebase should be treated as an untrusted signaling transport for payload
contents, but not as a metadata-private system.

## Media Encryption

WebRTC media uses DTLS-SRTP as provided by the platform WebRTC stack. Rain does
not add a custom media encryption layer or FrameCryptor in this model.

## What This Is Not

This is not full verified end-to-end encryption. Users do not currently compare
identity keys, fingerprints, or safety numbers. A malicious or compromised
client that has valid account access can still participate as that account.

Production builds must provide explicit non-demo signaling key material. Demo
builds may use the bundled demo key only when they are clearly labeled as the
`demo` update channel.

## Operational Rules

- Stable release builds must define `RAIN_SIGNALING_ENCRYPTION_KEY`.
- Stable release builds must not use the bundled demo signaling key.
- Demo builds using public TURN/demo settings must set `RAIN_UPDATE_CHANNEL=demo`.
- Firebase rules still matter: encryption protects payload contents, while rules
  protect who can create, read, mutate, or delete signaling records.
