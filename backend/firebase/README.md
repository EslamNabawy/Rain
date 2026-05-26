# Firebase Backend

This directory contains the Firebase assets needed by Rain's Realtime Database signaling flow.

## Services To Enable

- Anonymous Authentication
- Realtime Database
- Remote Config
- Cloud Functions

## Data Layout

- `users/<username>`: identity ownership, presence, and heartbeat timestamps
- `friendRequests/<to>/<from>`: username-based request inbox
- `rooms/<roomId>`: offer, answer, and ICE candidates only
- `activeVoicePairs/<pairId>`: ephemeral one-call lock for a caller/callee pair
- `activeVoiceUsers/<username>`: ephemeral one-call lock for a user across all peers
- `voiceCallInboxes/<username>/<callId>`: ephemeral incoming call pointer
- `voiceCalls/<callId>`: ephemeral voice call state, encrypted SDP, and encrypted ICE

Room nodes never store chat message content.
Voice call nodes are signaling state only and are removed by TTL cleanup; they are not call history.

## Deploy Realtime Database Rules

From this directory:

```powershell
firebase use --add
firebase deploy --only database
```

The rules file is [database.rules.json](database.rules.json).

## Deploy Functions

Install dependencies and deploy:

```powershell
cd functions
npm install
npm run lint
cd ..
firebase deploy --only functions
```

The Cloud Functions do two things:

- mark users offline when `lastHeartbeat` is older than 7 minutes
- remove abandoned signaling rooms after 15 minutes
- remove expired voice call rooms, inbox pointers, and active pair/user locks

## Remote Config

Create this key in Remote Config:

- `rain_release_manifest_v1`

Use [../../docs/releases/rain_release_manifest_v1.example.json](../../docs/releases/rain_release_manifest_v1.example.json) as the template. Update the matching `stable` or `demo` channel for each platform after publishing a release. The app uses this manifest to show optional updates and block versions older than the configured minimum.

Keep these legacy fallback keys until all installed builds support the manifest:

- `min_required_version`
- `update_url`

`update_url` is optional. When omitted, the app falls back to `RAIN_UPDATE_URL` from dart-defines.

## Suggested Validation

1. Register two desktop users and confirm `users/<username>/uid` is owned by the anonymous auth user.
2. Send a friend request and confirm it appears under `friendRequests/<recipient>/<sender>`.
3. Connect two peers and confirm `rooms/<roomId>` is deleted immediately after the session is established.
4. Stop sending heartbeats and confirm the cleanup job marks the user offline within the next scheduler run.
