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

Room nodes never store chat message content.

## Deploy Realtime Database Rules

From this directory:

```powershell
firebase use --add
firebase deploy --only database
```

The rules file is [database.rules.json](database.rules.json).

## Deploy Cleanup Functions

Install dependencies and deploy:

```powershell
cd functions
npm install
cd ..
firebase deploy --only functions
```

The scheduled jobs do two things:

- mark users offline when `lastHeartbeat` is older than 7 minutes
- remove abandoned signaling rooms after 15 minutes

## Remote Config

Create these keys in Remote Config:

- `min_required_version`
- `update_url`

`update_url` is optional. When omitted, the app falls back to `RAIN_UPDATE_URL` from dart-defines.

## Suggested Validation

1. Register two desktop users and confirm `users/<username>/uid` is owned by the anonymous auth user.
2. Send a friend request and confirm it appears under `friendRequests/<recipient>/<sender>`.
3. Connect two peers and confirm `rooms/<roomId>` is deleted immediately after the session is established.
4. Stop sending heartbeats and confirm the cleanup job marks the user offline within the next scheduler run.
