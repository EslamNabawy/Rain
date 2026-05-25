# Rain Connection Algorithms And Function Map

Status: reference map

Last analyzed: 2026-05-25

This document maps how Rain handles peer connectivity, chat delivery, file
transfer, voice calls, video calls, network recovery, and cleanup. It is meant
to help future changes avoid breaking the working connection path.

## Scope

Rain has three related connection systems:

| System | Transport | Owner | Purpose |
| --- | --- | --- | --- |
| Chat/data peer session | WebRTC data channels | `packages/protocol_brain` and `packages/peer_core` | Chat, control frames, file frames |
| Voice/video media call | Fresh WebRTC media peer connection per call | `apps/rain` runtime plus `peer_core` media connections | Microphone and camera RTP media |
| Firebase signaling | Firebase Realtime Database plus Firebase Auth | `protocol_brain` adapters and `apps/rain` runtime | Login, presence, friendship, SDP, ICE, call lease state |

Important boundary:

```text
Application runtime decides when a connection should exist.
protocol_brain decides how data peer sessions are established.
peer_core performs raw WebRTC peer/media operations.
rain_core persists local messages, files, identity, and queues.
Firebase stores ephemeral signaling and relationship state.
```

## Package Ownership

| Package or folder | Connection responsibility |
| --- | --- |
| `apps/rain/lib/application/runtime` | Orchestrates app lifecycle, friends, calls, transfers, network changes, diagnostics, and user intent |
| `apps/rain/lib/application/state` | Riverpod state projections for UI and runtime services |
| `apps/rain/lib/infrastructure/signaling` | App-level Firebase/noop adapter wiring |
| `packages/protocol_brain` | Session manager, Firebase signaling adapter, session retry, room ids, ICE policy, voice call signaling contracts |
| `packages/peer_core` | WebRTC data channels, media tracks, route stats, platform bridge, mic/camera/output controls |
| `packages/rain_core` | Drift stores, message envelopes, offline queue, file transfer records, typed frame parsers |
| `backend/firebase` | Realtime Database rules and cleanup functions |

## Data Peer Channels

`peer_core` defines the data channels used by the app:

| Session channel | Peer channel | Role |
| --- | --- | --- |
| `SessionChannel.chat` | `rain.chat` | User message envelopes |
| `SessionChannel.control` | `rain.ctrl` | ACKs, delivery control, call/runtime control frames where needed |
| `SessionChannel.file` | `rain.file` | File transfer offers, chunks, accepts, rejects, cancel/complete frames |

The required connected state is driven by required data channels. Chat and
control channels are treated as core availability. File transfer is optional
and can be opened or used only when needed.

## Connection Lifecycle

### 1. App bootstrap

Primary files:

- `apps/rain/lib/main.dart`
- `apps/rain/lib/application/bootstrap/app_bootstrap.dart`
- `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- `apps/rain/lib/application/runtime/friend_runtime.dart`

Algorithm:

1. `RainStartupApp` creates the bootstrap scope.
2. Runtime services are constructed through Riverpod providers.
3. `RainRuntimeController.start()` initializes local stores, signaling, network
   watchers, settings, sound, and friend runtime.
4. Startup preflights media permissions when required by the current app policy.
5. Presence is set and heartbeat/watchers begin for the logged-in identity.
6. `FriendRuntime` tracks accepted friends and registers passive peer listeners
   within coordinator limits.

Failure behavior:

- Startup failure renders `RainStartupFailureScreen` or root error state.
- Session-expired errors route through the root reset flow.
- Runtime dispose/log out clears watchers, call state, sessions, and presence.

### 2. Accepted friend tracking

Primary file:

- `apps/rain/lib/application/runtime/friend_runtime.dart`

Algorithm:

1. Load accepted friends from local/remote stores.
2. Track accepted peers only.
3. For each peer, determine whether a passive offer listener should be active.
4. Register incoming offer listeners through `SessionManager.registerPeer`.
5. Unregister listeners for removed, blocked, or no longer accepted peers.
6. Synchronize relationship changes and clear stale friend requests.

Important functions:

| Function | Responsibility |
| --- | --- |
| `_trackAcceptedPeer` | Adds a peer to runtime tracking |
| `_refreshPassivePeerListeners` | Refreshes passive offer listener set |
| `_reconcilePassivePeerListeners` | Adds/removes listeners to match accepted peers and limits |
| `_registerPeerListener` | Subscribes to incoming offers for a peer |
| `_unregisterPeerListener` | Removes passive listener |
| `_authorizeIncomingOffer` | Allows only valid accepted, non-blocked peers |
| `_waitForPeerConnection` | Waits for a session to become connected |
| `_syncRelationships` | Keeps local relationship state aligned |
| `_stopTrackingPeer` | Tears down peer tracking |

### 3. Passive listener selection

Primary file:

- `apps/rain/lib/application/runtime/connection_attempt_coordinator.dart`

Purpose:

Passive listeners avoid every friend consuming an active peer listener forever.
The coordinator selects which accepted peers may have inbound offer listeners
and tracks retry/backoff state.

Important types:

| Type | Purpose |
| --- | --- |
| `PeerDisconnectIntent` | Distinguishes local manual, remote, network lost, and shutdown disconnects |
| `ConnectionRetryGate` | Retry/backoff decision data for a peer |
| `ConnectionCoordinatorSnapshot` | Diagnostic snapshot of listener, retry, and disconnect state |

Important functions:

| Function | Responsibility |
| --- | --- |
| `selectPassivePeerIds` | Chooses which peers should currently have passive listeners |
| `canRegisterPassivePeer` | Checks whether a peer may register a listener |
| `updatePassiveListenerCount` | Tracks current listener pressure |
| `recordAttemptFailure` | Increments failure/backoff state |
| `recordAttemptSuccess` | Clears failure/backoff state |
| `clearRetry` | Removes retry state for a peer |
| `recordDisconnectIntent` | Stores why a peer disconnected |
| `disconnectIntentFor` | Reads the stored disconnect reason |
| `clearDisconnectIntent` | Clears disconnect intent after it has been handled |
| `recordInboundOffer` | Notes inbound activity for priority decisions |
| `recordIncomingOfferRejected` | Captures rejected inbound offer diagnostics |
| `scheduleNetworkRecovery` | Schedules recovery after network transitions |
| `snapshot` | Emits diagnostics for UI/debug bundles |
| `dispose` | Cancels recovery timers and clears state |

### 4. Manual data connection

Primary files:

- `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
- `packages/peer_core/lib/src/default_peer_core.dart`

Algorithm:

1. UI requests `RainRuntimeController.connectPeer(peerId)`.
2. Runtime validates identity, accepted friendship, and network state.
3. Runtime clears stale disconnect/retry state where appropriate.
4. `ProtocolBrainImpl.connect(peerId)` registers the peer listener.
5. A deterministic offer owner is selected by `_isOfferOwner(peerId)`.
6. Offer owner starts `_startOffer`.
7. Non-owner waits in `_waitForOffer`.
8. SDP is written/read through Firebase room paths.
9. ICE candidates are exchanged by role.
10. `DefaultPeerCore` opens data channels and emits connection state.
11. Session is marked connected only after required data channels are open.
12. Runtime records success and flushes queued messages for the peer.

Session phases exposed for diagnostics:

```text
idle
checkingPresence
registeringPeer
waitingForOffer
creatingOffer
writingOffer
waitingForAnswer
writingAnswer
exchangingIce
openingDataChannels
negotiatingMedia
connected
reconnecting
disconnecting
disconnected
failed
```

### 5. Incoming data offer

Primary files:

- `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
- `apps/rain/lib/application/runtime/friend_runtime.dart`

Algorithm:

1. `registerPeer(peerId)` subscribes to `adapter.onOffer(roomId(self, peer))`.
2. Only the deterministic non-owner handles incoming offers.
3. `IncomingOfferGuard` checks friendship, blocking, and runtime state.
4. If denied, `IncomingOfferRejection` is emitted and diagnostics are updated.
5. If allowed, a peer is created/recreated and the remote offer is applied.
6. Local answer is created and written to Firebase.
7. ICE subscriptions attach and candidates are exchanged.
8. Required data channels open and session becomes connected.

### 6. Direct first, relay fallback

Primary files:

- `packages/protocol_brain/lib/src/ice_candidate_policy.dart`
- `packages/protocol_brain/lib/src/session_retry_policy.dart`
- `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
- `apps/rain/lib/infrastructure/services/turn_credential_service.dart`

Algorithm:

1. Initial manual connection uses `PeerIceTransportPolicy.all`.
2. ICE servers are loaded from static config and/or TURN credential provider.
3. If direct connection fails or times out and a relay server exists, the session
   can be recreated with `PeerIceTransportPolicy.relayOnly`.
4. Retry attempts are bounded by the session retry policy.
5. Connection memory stores failure/success observations for diagnostics and
   future policy decisions.

Current note:

- Cached ICE reconnect hooks exist, but cached ICE reconnect is disabled in the
  current policy. Treat it as reserved infrastructure, not an active feature.

### 7. Route classification

Primary file:

- `packages/peer_core/lib/src/models.dart`

Algorithm:

1. `PeerCore.currentRoute()` reads WebRTC stats.
2. `PeerConnectionRoute.fromStats` finds the selected candidate pair.
3. Candidate types are normalized.
4. Route kind is classified as `direct`, `relay`, or `unknown`.
5. Address family is classified as `ipv4`, `ipv6`, `mixed`, or `unknown`.
6. RTT and bitrate fields are surfaced when available.

UI uses this to show direct/relay/unknown link state. It is diagnostic and
status-oriented; it does not by itself prove call media quality.

### 8. Manual disconnect and reconnect intent

Primary files:

- `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- `apps/rain/lib/application/runtime/connection_attempt_coordinator.dart`
- `packages/protocol_brain/lib/src/protocol_brain_impl.dart`

Algorithm:

1. User presses disconnect.
2. Runtime records `PeerDisconnectIntent.localManual`.
3. `ProtocolBrainImpl.disconnect(peerId)` sets `shouldReconnect = false`.
4. The Firebase room is deleted silently where possible.
5. Peer resources and subscriptions are disposed.
6. The remote peer should treat the disconnection as remote/manual state rather
   than endless automatic recovery.
7. A later explicit connect action clears the manual intent and starts a fresh
   connection attempt.

Failure mode to protect:

- A manual disconnect must not leave the local peer stuck in "recovering".
- A remote disconnect must not trigger infinite reconnect churn if the other
  side intentionally closed the session.

### 9. Network loss and recovery

Primary files:

- `apps/rain/lib/infrastructure/services/network_status_service.dart`
- `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- `apps/rain/lib/application/runtime/connection_attempt_coordinator.dart`
- `packages/protocol_brain/lib/src/protocol_brain_impl.dart`

Algorithm:

1. Network service emits unavailable.
2. Runtime records `PeerDisconnectIntent.networkLost` for affected peers.
3. Active sessions are allowed to transition through reconnecting/failed.
4. Network available schedules recovery through `scheduleNetworkRecovery`.
5. `recoverConnections` restarts sessions that still have `shouldReconnect`.
6. Manual disconnect intents are respected and skipped.

Important constraint:

- Recovery is for accidental network changes, not a replacement for user intent.

## WebRTC Data Peer Core

Primary files:

- `packages/peer_core/lib/src/models.dart`
- `packages/peer_core/lib/src/default_peer_core.dart`
- `packages/peer_core/lib/src/state_machine.dart`
- `packages/peer_core/lib/src/platform_bridge.dart`

### Peer state model

```text
idle -> ready -> offering/answering -> connecting -> connected
                         \-> reconnecting
                         \-> failed
```

### Public `PeerCore` functions

| Function | Responsibility |
| --- | --- |
| `init` | Creates the underlying `RTCPeerConnection` using `PeerConfig` |
| `destroy` | Disposes peer connection, channels, streams, and timers |
| `createOffer` | Creates and sets local SDP offer for data session |
| `setOffer` | Applies remote offer and creates/sets local answer |
| `setAnswer` | Applies remote answer |
| `addIceCandidate` | Adds remote ICE candidate |
| `getLocalCandidates` | Returns gathered local candidates |
| `startLocalAudio` | Legacy data-peer media hook; not the primary call path |
| `stopLocalAudio` | Stops legacy local audio media on data peer |
| `setMicrophoneMuted` | Toggles mic mute through platform/WebRTC helpers |
| `createMediaOffer` | Legacy connected-session media renegotiation hook |
| `applyMediaOffer` | Legacy media-offer apply hook |
| `applyMediaAnswer` | Legacy media-answer apply hook |
| `send` | Sends data over a peer data channel |
| `openChannel` | Opens a data channel |
| `closeChannel` | Closes a data channel |
| `bufferedAmount` | Reads channel buffered amount |
| `isChannelOpen` | Checks channel readiness |
| `currentRoute` | Reads WebRTC selected route from stats |

### `DefaultPeerCore` safety rules

- Epoch checks ignore callbacks from stale peer connections.
- Required data channels gate the connected state.
- Large binary payloads can be chunked and reassembled.
- Transient ICE disconnects are delayed before being treated as final.
- Media hooks on this class are not the primary modern call implementation.

## Protocol Brain Session Manager

Primary files:

- `packages/protocol_brain/lib/src/session_manager.dart`
- `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
- `packages/protocol_brain/lib/src/active_session.dart`

### Public `SessionManager` functions

| Function | Responsibility |
| --- | --- |
| `getSessions` | Returns all active session snapshots |
| `getSession` | Returns one peer session snapshot |
| `registerPeer` | Starts listening for inbound offers |
| `unregisterPeer` | Stops listening for inbound offers |
| `connect` | Creates or reuses an active data session |
| `disconnect` | Disposes one data session and stops reconnect |
| `recoverConnection` | Restarts one reconnectable session after network change |
| `recoverConnections` | Restarts all reconnectable sessions |
| `sendControl` | Sends a control channel string |
| `send` | Sends data on chat/control/file channel |
| `openChannel` | Opens a channel |
| `bufferedAmount` | Reads a channel's buffered bytes |
| `isChannelOpen` | Checks channel readiness |
| `startLocalAudio` | Legacy session media hook |
| `stopLocalAudio` | Legacy session media cleanup |
| `setMicrophoneMuted` | Legacy session mic toggle |
| `createVoiceMediaConnection` | Creates a fresh audio media connection using current peer config |
| `createCallMediaConnection` | Creates a fresh audio/video media connection using current peer config |
| `createMediaOffer` | Legacy data-peer media renegotiation |
| `applyMediaOffer` | Legacy data-peer media renegotiation |
| `applyMediaAnswer` | Legacy data-peer media renegotiation |

### Room id algorithm

Firebase data-session rooms use a canonical pair id:

```text
roomId(a, b) = lower(sort(normalize(a), normalize(b))).join(":")
```

This prevents both peers from creating separate rooms for the same pair.

## Firebase Signaling

Primary files:

- `packages/protocol_brain/lib/adapters/signaling_adapter.dart`
- `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- `packages/protocol_brain/lib/adapters/signaling_cipher.dart`
- `backend/firebase/database.rules.json`

### Data-session paths

The signaling adapter abstracts:

- offer write/read
- answer write/read
- ICE write/read by `IceRole.caller` or `IceRole.callee`
- room deletion
- presence
- identity
- friend request and relationship changes

### Voice/video call paths

Current media calls use ephemeral Firebase call signaling:

```text
activeVoicePairs/{pairId}
voiceCallInboxes/{username}/{callId}
voiceCalls/{callId}
```

Important call properties:

- Call rooms are ephemeral.
- Pair locks prevent simultaneous call glare.
- SDP and ICE payloads are encrypted before storage.
- Stale locks and unreadable active locks have reclaim paths.
- Terminal states must clean inbox entries, pair locks, and call rooms.

## Voice And Video Call Runtime

Primary files:

- `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- `apps/rain/lib/application/runtime/voice_call_state.dart`
- `apps/rain/lib/application/runtime/video_call_renderers.dart`
- `apps/rain/lib/application/runtime/media_device_settings.dart`
- `packages/protocol_brain/lib/src/voice_signaling_contract.dart`
- `packages/protocol_brain/lib/src/voice_call_frame.dart`
- `packages/rain_core/lib/voice_call/voice_call_frame.dart`

### Call state model

The app runtime models call phases around:

```text
idle
connectingPeer
outgoingRinging
incomingRinging
connectingMedia
active
ending
failed
```

The UI must be driven from this runtime state, not from local widget timers or
one-off booleans.

### Outgoing call algorithm

1. User presses voice or video call.
2. Runtime validates:
   - network available
   - accepted friend
   - no active global call
   - no active file transfer
   - no stale active call lease for the pair unless reclaimable
3. Runtime preflights required microphone/camera permission.
4. Runtime creates Firebase outgoing call room and active pair lock.
5. Runtime shows outgoing ringing and starts timeout.
6. Callee watches inbox and accepts/rejects/busy/hangup.
7. On accept, caller starts media offer.
8. ICE candidates are written under the caller role.
9. Answer is applied and media phase waits for connected/remote track.
10. Runtime marks call active and records connected timestamp.

### Incoming call algorithm

1. Runtime watches `voiceCallInboxes/{self}`.
2. Incoming entry is normalized and checked for stale or wrong peer data.
3. Runtime rejects or busy-replies if another call is active.
4. Incoming ring UI is displayed only while the app runtime is active.
5. Accept preflights microphone/camera permission.
6. Runtime updates Firebase room to accepted.
7. Runtime accepts media offer and writes answer.
8. ICE candidates are written under callee role.
9. Runtime transitions to active only after media readiness is confirmed.

### Call termination algorithm

1. User hangup, remote hangup, timeout, app close, media failure, or lease expiry
   enters terminal handling.
2. Runtime sends/writes terminal reason where possible.
3. Media connection is disposed.
4. Renderers are detached/disposed.
5. Ringtone/ringback sounds stop.
6. Active pair lock is removed if it still belongs to the call.
7. Inbox entries are removed or marked terminal.
8. Runtime returns to idle or failed with a visible dismissible error.

### Busy lock algorithm

Busy state is not just a UI label. It comes from:

- local active call state
- remote active pair lock
- stale `activeVoicePairs` entries
- stale `voiceCalls/{callId}` status
- unreadable or orphaned lock data

Correct handling requires:

1. Treat current non-terminal call as busy.
2. Reclaim expired/stale locks.
3. Remove locks only if call id and pair data still match.
4. Never delete another newer call's lock.
5. Clear local call state after terminal remote/app-close events.

## Dedicated Media Core

Primary files:

- `packages/peer_core/lib/src/voice/voice_media_connection.dart`
- `packages/peer_core/lib/src/call/call_media_connection.dart`
- `packages/peer_core/lib/src/voice/voice_media_models.dart`
- `packages/peer_core/lib/src/call/call_media_models.dart`
- `packages/peer_core/lib/src/platform_bridge.dart`

### `VoiceMediaConnection`

Audio-only interface:

| Function | Responsibility |
| --- | --- |
| `startLocalAudio` | Captures local microphone and prepares voice audio |
| `createOffer` | Creates SDP offer for caller |
| `acceptOffer` | Applies offer and creates answer for callee |
| `applyAnswer` | Applies callee answer on caller |
| `addRemoteCandidate` | Adds or buffers remote ICE |
| `setMuted` | Mutes microphone |
| `setDeafened` | Disables local playback of remote audio |
| `setAudioOutputRoute` | Selects system/speaker/Bluetooth route |
| `dispose` | Cleans media, peer connection, controllers, timers |

Safety mechanisms:

- One serialized media operation at a time.
- Connection epoch guards against stale callbacks.
- Remote ICE candidates can buffer until remote description is set.
- Voice audio preparation is paired with cleanup.
- Audio level sampler emits local/remote activity diagnostics.
- Full media errors are retained for diagnostics.

### `CallMediaConnection`

Audio/video interface:

| Function | Responsibility |
| --- | --- |
| `startLocalMedia` | Captures mic and optionally camera |
| `createOffer` | Creates SDP offer for audio or video call |
| `acceptOffer` | Applies remote offer and creates answer |
| `applyAnswer` | Applies remote answer |
| `addRemoteCandidate` | Adds or buffers remote ICE |
| `setMicrophoneMuted` | Toggles local audio track |
| `setCameraMuted` | Toggles local video track |
| `switchCamera` | Switches camera when supported |
| `setDeafened` | Controls remote audio playback |
| `setAudioOutputRoute` | Selects output route |
| `dispose` | Cleans tracks, streams, peer, controllers |

Important media rules:

- Microphone and camera are sent as WebRTC media tracks, not data-channel
  packets.
- WebRTC handles Opus/RTP/RTCP/DTLS-SRTP/jitter buffering.
- Rain app code only handles permission, device selection, SDP/ICE signaling,
  state, UI, diagnostics, and cleanup.
- Video UI roles must treat remote video as primary by default and local video
  as preview unless the user explicitly swaps them.

### Platform bridge

Primary file:

- `packages/peer_core/lib/src/platform_bridge.dart`

Responsibilities:

- enumerate media devices
- capture user media through Flutter WebRTC
- select audio input
- select audio output where platform supports it
- toggle speakerphone
- prefer Bluetooth where possible
- prepare Android communication audio mode
- clear Android communication audio mode
- mute microphone through Flutter WebRTC helper
- switch camera track when supported

## Message Delivery

Primary files:

- `packages/rain_core/lib/messages/message_envelope.dart`
- `packages/rain_core/lib/messages/message_store.dart`
- `packages/rain_core/lib/messages/offline_queue.dart`
- `packages/rain_core/lib/messages/message_delivery_service.dart`
- `apps/rain/lib/application/runtime/rain_runtime_controller.dart`

Algorithm:

1. User sends text from chat composer.
2. `MessageStore.composeOutgoingEnvelope` assigns peer sequence and id.
3. Store persists outgoing message.
4. `MessageDeliveryService.sendEnvelope` sends over `SessionChannel.chat`.
5. Message enters `pendingAck` where appropriate.
6. Control ACKs arrive through `SessionChannel.control`.
7. Ack timer marks failed if delivery does not confirm.
8. Offline queue stores unsent/in-flight messages.
9. Runtime flushes queue when peer connection returns.

Incoming algorithm:

1. Chat channel receives a wire string.
2. Envelope is parsed and validated.
3. `MessageStore.storeIncomingEnvelope` checks duplicate/gap/late state.
4. Gaps are buffered by `MessageDeliveryService`.
5. ACK is sent for accepted envelopes.
6. Buffered messages flush when missing sequences arrive.

## File Transfer

Primary files:

- `packages/rain_core/lib/file_transfer/file_transfer_protocol.dart`
- `packages/rain_core/lib/file_transfer/file_transfer_store.dart`
- `apps/rain/lib/application/runtime/file_transfer_runtime.dart`
- `apps/rain/lib/application/runtime/file_transfer_progress_batcher.dart`

Algorithm:

1. Sender creates transfer record and file offer frame.
2. Offer is sent over `SessionChannel.file`.
3. Receiver accepts or rejects.
4. Accepted transfer sends chunks over the file channel.
5. Progress updates are batched to avoid UI/store churn.
6. Receiver verifies and writes received bytes.
7. Complete/cancel/reject/fail states are persisted.
8. Export service moves received files into a user-accessible location.

Call interaction:

- New file sends and accepts are blocked while a call is active.
- Active transfer blocks starting a call.
- Failure messages should be explicit: finish the call first or wait for the
  active transfer to finish.

## Sound And Call Audio Interaction

Primary files:

- `apps/rain/lib/application/audio/rain_sound_event.dart`
- `apps/rain/lib/application/audio/sound_event_router.dart`
- `apps/rain/lib/infrastructure/services/sound_effects_service.dart`
- `apps/rain/lib/application/state/sound_event_providers.dart`

Algorithm:

1. Runtime emits typed `RainSoundEvent` values.
2. `SoundEventRouter` centralizes debounce, burst handling, priority, and call
   state suppression.
3. `SoundEffectsService` loads and plays the selected app sound assets.
4. Ringtone/ringback lifecycle must be tied to call state, not widget lifetime.

Important rule:

- App sounds must not fight active media playback or become unbounded when many
  messages arrive quickly.

## Diagnostics

Primary files:

- `apps/rain/lib/application/state/connection_diagnostics.dart`
- `apps/rain/lib/application/runtime/voice_call_diagnostics.dart`
- `apps/rain/lib/infrastructure/services/crash_diagnostics_service.dart`
- `apps/rain/lib/application/runtime/connection_attempt_coordinator.dart`

Diagnostics should include:

- session state and phase
- data-channel readiness
- direct/relay route and stats
- retry/backoff state
- disconnect intent
- call id, pair id, and role
- call signaling status
- media phase and latest full media error
- selected mic/camera/output route
- app lifecycle state
- stale lock or stale room cleanup decisions

UI can show a short user-safe message, but diagnostics must retain the full
technical error.

## Critical Failure Modes

| Failure mode | Correct handling |
| --- | --- |
| Stale active call pair lock | Reclaim only after expiry/grace and only if call id still matches |
| Peer says busy after failed call | Clear local state and remote lock/inbox artifacts on terminal failure |
| Disposed transceiver callback | Epoch guard, ignore stale callbacks, dispose media only once |
| App closes mid-call | Remote watcher sees terminal/absence and local media disposes |
| Manual disconnect starts recovery loop | Store local manual intent and skip automatic recovery |
| Network flaps mid-call | Enter grace/weakness state before terminal failure when possible |
| Mic/camera permission missing | Preflight before ringing/accepting and surface retryable UI |
| Bluetooth route unavailable | Do not show Bluetooth option unless capability is detected |
| File transfer during call | Block start/accept with clear message |
| Many quick messages | Compress notification sounds without disabling delivery logic |

## Verification Expectations

Docs-only changes do not need Flutter builds. Connection changes normally need:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

Release-level connection changes also need manual device proof:

```text
Windows -> Android data connection
Android -> Windows data connection
Android -> Android data connection
Windows -> Android voice call
Android -> Windows voice call
Android -> Android voice call
video call both directions
disconnect and reconnect both sides
app close during active connection
repeat calls without app restart
file transfer block during active call
```
