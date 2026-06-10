# User Flows

## Sign In

1. User opens Rain.
2. Splash/bootstrap gate initializes Firebase, local database, settings, update check, and runtime.
3. User signs in by username/password.
4. App loads friends, presence, and connection state.

## Direct Chat

1. User selects accepted friend.
2. App checks fresh presence.
3. User presses Connect.
4. Firebase signaling creates or watches a data-peer room.
5. WebRTC data channels open.
6. Messages flow over `rain.chat`; ACK/control over `rain.ctrl`.

## Voice Or Video Call

1. User presses voice/video call.
2. Runtime checks accepted friend, presence, global call state, file-transfer conflicts, and call locks.
3. Firebase room/inbox/locks are created.
4. Callee rings.
5. Callee accepts or rejects.
6. WebRTC media SDP/ICE flows through Firebase.
7. Media becomes active or terminal cleanup runs.

## Offline Connection Request

1. User attempts Connect while peer is offline/stale.
2. App confirms backend presence.
3. User confirms sending request notification.
4. RTDB request is created if guardrails allow it.
5. Receiver sees inbound request when app is running.

Related: [[Feature Matrix]], [[Presence And Direct Connect]], [[Voice Calls]], [[Video Calls]].
