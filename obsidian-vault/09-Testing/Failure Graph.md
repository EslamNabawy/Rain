# Failure Graph

Last updated: 2026-06-06

## Purpose

Track recurring Rain failure chains so scenario-intelligence agents can generate interaction tests instead of isolated happy paths.

Related: [[Scenario Intelligence Agent]], [[Assumption Register]], [[System Model]], [[State Graph]], [[Business Rule Graph]], [[Risk Register]], [[Test Strategy]].

## Failure Chain Format

```text
Trigger
  -> Intermediate failure
  -> User-visible failure
  -> Secondary risk
  -> Required evidence or test
```

## Known Failure Chains

### FG-001: Stale Presence To False Busy

```text
Stale presence heartbeat
  -> Peer appears online
  -> User starts call or direct connect
  -> Call room or session setup starts for unavailable peer
  -> User retries
  -> Stale/partial call lock can create busy state
  -> Need presence freshness tests plus lock repair tests
```

Related assumptions: ASSUMP-003, ASSUMP-005, ASSUMP-006.
Related risks: R-001, R-002, R-003.

### FG-002: Terminal Room Race To Misleading Crash

```text
Remote peer ends call
  -> Firebase room becomes terminal
  -> Local media negotiation resumes after await
  -> Local write attempts SDP or mute into ended room
  -> Debug signaling records write failure
  -> Diagnostics point to write operation instead of terminal race
  -> Need terminal preflight before late media signaling writes
```

Related assumptions: ASSUMP-002, ASSUMP-009.
Related risks: R-001, R-009.

### FG-003: Optional Mirror Write Blocks Authoritative Cleanup

```text
Callee inbox mirror is removed early
  -> End-call multi-path update includes room terminal state plus missing inbox mirror
  -> RTDB rules deny whole update
  -> Authoritative room stays non-terminal or cleanup reports permission denied
  -> Locks can remain or user sees failed cleanup
  -> Need authoritative room write before best-effort mirror cleanup
```

Related assumptions: ASSUMP-002, ASSUMP-005.
Related risks: R-002, R-014.

### FG-004: Account Tombstone To Account Recreation

```text
Account deletion tombstones RTDB user
  -> Firebase Auth deletion fails
  -> User logs in with surviving Auth credential
  -> Login path treats missing backend identity as profile creation
  -> Deleted account is recreated
  -> Need login backend proof and tombstone upsert/search guards
```

Related assumptions: ASSUMP-002, ASSUMP-007.
Related risks: R-021.

### FG-005: Registration Permission Denied To Raw Backend Error

```text
Username already exists or is locked
  -> RTDB denies primary user row creation
  -> App reports raw Firebase permission denied
  -> User cannot tell conflict from outage
  -> Auth rollback may leave inconsistent state if wrong phase is deleted
  -> Need domain conflict message and phase-aware rollback
```

Related assumptions: ASSUMP-002, ASSUMP-007.
Related risks: R-014, R-021.

### FG-006: Stale Remote Config To Broken Old Client

```text
Release artifact ships
  -> Remote Config release manifest is not deployed
  -> Old client sees stale policy
  -> App says current or fails to prompt
  -> Backend rules/protocol may become incompatible
  -> Need stale-policy state and release evidence for deployed manifest
```

Related assumptions: ASSUMP-004.
Related risks: R-006, R-018.

### FG-007: Android Picker Handle To Missing Diagnostics Export

```text
Diagnostics export uses Android picker
  -> Picker returns content URI or `/document/...`
  -> App treats handle as filesystem path
  -> File write fails with path error
  -> User cannot share diagnostics for failure
  -> Need platform-handle detection and app-owned fallback JSON file
```

Related assumptions: ASSUMP-008.
Related risks: R-015.

### FG-008: Offline Request Quota From Stale Online Split

```text
Peer backend presence is stale
  -> UI reads raw online flag
  -> Action routes to wrong direct-connect/offline-request branch
  -> User burns quota or gets silent denial
  -> Connection remains unresolved
  -> Need shared freshness resolver and explicit blocked-action messaging
```

Related assumptions: ASSUMP-003, ASSUMP-010.
Related risks: R-016, R-020.

### FG-009: File Buffer Pressure To Corrupt Or Unbounded Transfer

```text
Large file or slow receiver
  -> Sender continues writing chunks while file data channel remains above high watermark
  -> Buffered data grows or transfer stalls without a clear terminal reason
  -> Receiver may hold stale temp sink or partial temp file after failure/cancel
  -> User sees failed/corrupt transfer or degraded peer session
  -> Need persistent receive sink cleanup plus high/low watermark send proof
```

Related assumptions: ASSUMP-014, ASSUMP-011.
Related risks: R-011.

### FG-010: Split Peer UI Truth To False Connected

```text
Data lane remains open while presence is stale or call state is failed/recovering
  -> One UI surface reads data-session truth and another reads call/presence truth
  -> User sees Connected beside Failed, Recovering, Offline, or stale state
  -> User starts wrong action or mistrusts call/chat status
  -> Need one peer status projection plus split-state diagnostics
```

Interruption point: `ConnectionDiagnostics` projection precedence and `peerConnectionDiagnosticsProvider`.
Current local evidence: `connection_diagnostics_test.dart`, `chat_panel_connectivity_test.dart`, and `friend_flow_test.dart --plain-name "video renderer"` cover failed/recovering/data-lane split behavior and `peer_ui_state_split_detected`.

Related assumptions: ASSUMP-003, ASSUMP-009, ASSUMP-013.
Related risks: R-005, R-009, R-020.

### FG-011: Stale Data ICE Callback To Permission Denied

```text
Disconnect, reconnect, or room cleanup starts while local ICE callback is queued
  -> Firebase data-peer room is deleted or replaced
  -> Stale callback writes old `callerICE` or `calleeICE` path
  -> RTDB role/existence rule denies `signaling.writeICE`
  -> Direct connect attempt dies or diagnostic points at Firebase permission
  -> Need generation-bound local ICE writes plus room deletion after peer binding disposal
```

Interruption point: local ICE write listener in `ProtocolBrainImpl`.
Current local evidence: `packages/protocol_brain/test/protocol_brain_test.dart --plain-name "ICE"` covers both live ICE write failure surfacing as a failed session and queued local ICE after disconnect not writing a stale room.

Related assumptions: ASSUMP-002, ASSUMP-011.
Related risks: R-014, R-015.

### FG-012: Diagnostics Sanitizer To Lost Causal Events

```text
Crash diagnostics builds summaries from 200 recent events
  -> Recursive sanitizer applies the generic 20-item list cap to top-level `events`
  -> Export keeps only heartbeat/UI tail records
  -> Call/failure events appear in summaries but not in raw event evidence
  -> Postmortem cannot prove why a room went terminal or busy
  -> Need top-level event-window preservation plus focused export tests
```

Interruption point: `CrashDiagnosticsService.exportDiagnostics`.
Current local evidence: `crash_diagnostics_service_test.dart --plain-name "app event log is bounded when exported"` proves the sanitized export keeps the 200-record window.

Related assumptions: ASSUMP-008, ASSUMP-011.
Related risks: R-015.

## Scenario Generation Rule

For each new bug, RCA, or failed test:

1. Add or update the failure chain.
2. Link assumptions, risks, blockers, and debt.
3. Identify the earliest state where the chain could be interrupted.
4. Add the smallest deterministic regression test for that interruption.
5. Promote repeated chains into release-gate scenarios.
