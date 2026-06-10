# State Graph

Last updated: 2026-06-04

## Purpose

Track Rain's critical state machines so scenario generation can cover transitions, invalid transitions, terminal states, and recovery paths.

This note is a scenario-intelligence map. Detailed implementation remains in repository code and linked feature notes.

## Auth And Account Lifecycle

```text
Unauthenticated
-> Registering
-> Authenticated
-> DeletingAccount
-> LoggedOut
```

Critical transition rules:

- Registering becomes Authenticated only after backend identity, presence, and local Drift identity are synchronized.
- Authenticated restoration requires Firebase Auth and RTDB user ownership proof.
- DeletingAccount starts only after password reauthentication.
- Bad-password reauthentication returns to Authenticated without clearing local session.
- Destructive deletion outcomes clear local Drift identity and authenticated session generation.
- Missing or tombstoned backend identity after Firebase Auth succeeds must not recreate account data.

Related: [[Authentication]], [[Assumption Register]], [[Failure Graph]].

## Friendship

```text
None
-> RequestedOutgoing
-> Accepted
-> Removed

None
-> RequestedIncoming
-> Accepted
-> Removed

None
-> Blocked
-> Removed
```

Critical transition rules:

- Self requests are invalid.
- Incoming request acceptance must update both local state and backend friendship mirrors.
- Blocking removes pending requests and active sessions.
- Unblock returns to no relationship unless a new request is created.

Related: [[Friendship And Blocking]], [[Permissions Matrix]].

## Presence

```text
Offline
-> Connecting
-> Online
-> Stale
-> Offline
```

Critical transition rules:

- Raw `online: true` is not enough; heartbeat age and `presence.state` must be evaluated.
- Closed app currently means offline unless a future push/foreground-service architecture changes that.
- Stale presence must block direct connect, call start, auto-recovery, and online-only decisions.

Related: [[Presence And Direct Connect]], [[Presence Management]].

## Peer Data Session

```text
Idle
-> Signaling
-> Negotiating
-> Connected
-> Recovering
-> Disconnected
-> Idle
```

Critical transition rules:

- Chat/control channel readiness defines connected data-session behavior.
- Manual disconnect blocks automatic recovery until explicit reconnect.
- Failed direct transport can retry relay-only only through the configured retry policy.

Related: [[Signaling Architecture]], [[Peer Chat]].

## File Transfer

```text
Offered
-> Accepted
-> Transferring
-> Completed

Offered
-> Rejected

Transferring
-> Canceled
Transferring
-> Failed
```

Critical transition rules:

- Active file transfer can block call start when conflict policy requires it.
- Transfer progress must not imply completion until final byte count and hash state are valid.
- Peer lane disconnect resets speed samples and keeps terminal transfer state stable.

Related: [[File Transfer]], [[Backpressure Strategy]].

## Voice And Video Call

```text
Idle
-> CheckingPresence
-> CheckingConflicts
-> ClaimingLease
-> Ringing
-> Accepting
-> Negotiating
-> Connected
-> Reconnecting
-> Ending
-> Ended

Any non-terminal state
-> Failed
```

Critical transition rules:

- Firebase terminal room state is authoritative for both peers.
- Terminal-sensitive media writes must preflight room state before writing SDP, accept, answer, or mute.
- Signaling failure must not be reported as media failure.
- Active locks must be released only when the lock belongs to the matching call id or is proven stale/terminal.

Related: [[Call State Machine]], [[Voice Calls]], [[Video Calls]], [[Lease Management]].

## Update Gate

```text
Unknown
-> LoadingPolicy
-> Current
-> OptionalUpdate
-> RequiredUpdate
-> RemotePolicyOutdated
-> Unavailable
-> InvalidConfig
```

Critical transition rules:

- Required update blocks routed app content.
- Stale Remote Config policy must not be reported as current.
- Same semantic version can still require update when minimum build increases.

Related: [[Version And Updates]], [[Release Gates]].

## Scenario Generation Rule

For each state machine:

1. Generate one valid happy path.
2. Generate one invalid transition attempt.
3. Generate one interrupted transition.
4. Generate one stale/late event after terminal state.
5. Generate one recovery path.

Related: [[Scenario Intelligence Agent]], [[Failure Graph]], [[Test Strategy]].
