# Failure Graph

Last updated: 2026-06-07

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
  -> App or picker wrapper treats handle as filesystem path
  -> File write fails with path error
  -> User cannot share diagnostics for failure
  -> Need native Android SAF write with bytes, platform-handle detection, and app-owned fallback JSON file for wrapper failures
```

Related assumptions: ASSUMP-008.
Related risks: R-015.
Current local evidence: `crash_diagnostics_service_test.dart` covers content URI, `/document/...`, newline-split `/\ndocument/...`, and the `file_picker 12.0.0-beta.3` wrapper failure path that throws `FileSystemException` for `/document/12`.

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

### FG-011: Data ICE Lifecycle To Permission Denied

```text
Disconnect, reconnect, or cleanup starts while local ICE callback is queued
  -> Firebase data-peer room is deleted or replaced
  -> Stale callback writes old `callerICE` or `calleeICE` path
  -> RTDB role/existence rule denies `signaling.writeICE`
  -> Direct connect attempt dies or diagnostic points at Firebase permission
  -> Need generation-bound local ICE writes plus room deletion after peer binding disposal

Data channel reaches connected while local trickle ICE is still arriving
  -> Connected-state handler deletes the active Firebase room as early cleanup
  -> Current-session late ICE writes the correct `callerICE` or `calleeICE` bucket
  -> RTDB room-existence rule denies a valid write because the active room is gone
  -> Direct route briefly connects, then the session fails on Firebase permission denied
  -> Need active room lifetime to extend until disconnect/failure/session cleanup
```

Interruption point: local ICE write listener in `ProtocolBrainImpl`.
Current local evidence: `packages/protocol_brain/test/protocol_brain_test.dart --plain-name "ICE"` covers live ICE write failure surfacing as a failed session, queued local ICE after disconnect not writing a stale room, and connected sessions keeping the signaling room alive for late local ICE.

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

### FG-013: Pending Logout/Delete To Interactive Shell

```text
User taps logout or delete account
  -> Delete path starts runtime shutdown before backend/Auth deletion, or logout waits on presence/session/backend cleanup before ending local authority
  -> Runtime provider remains ready or loading with a previous runtime value
  -> AppStartupState treats the previous/null runtime as ready
  -> Account deletion publishes global loading before password/tombstone preflight finishes, or destructive progress remains a Settings-local splash while bottom navigation remains interactive
  -> Firebase Auth deletion happens while account-scoped RTDB listeners or protocol room listeners are still subscribed
  -> User can switch tabs, trigger connect/account actions, gets stuck after logout, loses wrong-password feedback, delete account behaves like plain logout, or the login-screen transition is followed by permission-denied listener errors
  -> Need logout local-session clear before cleanup wait, delete-account backend/Auth delete before runtime/local teardown, required tombstone failure session restoration with visible error, no global runtime loading during non-destructive delete preflight, full-screen deleting-account phase after password verification, account-listener and protocol-session cancellation before Auth deletion, optional account cleanup decoupled from the tombstone write, signed-out authority handoff, non-null runtime readiness, and shutdown action guards
```

Interruption point: `runtimeControllerProvider`, `AppStartupState`, and runtime action preflights.
Current local/live evidence: `apps/rain/test/runtime_startup_test.dart` covers logout reaching signed-out while cleanup is blocked, destructive deletion calling backend delete while runtime cleanup is blocked, bad-password delete restoration, Settings staying mounted while password verification is pending, the `deletingAccount` app phase after password verification, account listener and active protocol session cancellation before Firebase Auth deletion, required tombstone failure preserving the session/local identity, and connect rejection after shutdown; `apps/rain/test/settings_screen_test.dart` covers visible delete-error feedback; `apps/rain/test/app_routes_test.dart` covers protected shell absence during blocked startup plus route preservation during `deletingAccount`; `apps/rain/test/auth_identity_source_of_truth_test.dart` covers same-device deleted-account login copy; `packages/protocol_brain/test/firebase_contract_test.dart` locks that optional account cleanup is not bundled with the required tombstone in one all-or-nothing RTDB update and that legacy missing-uid account rows require email-bound ownership before tombstone. The 2026-06-07 Firebase emulator account-deletion gate passed, and live `rain-8fb4b-default-rtdb` rules were deployed/read back with the missing-uid branch.

Related assumptions: ASSUMP-001, ASSUMP-007, ASSUMP-013.
Related risks: R-021, R-022.

## Scenario Generation Rule

For each new bug, RCA, or failed test:

1. Add or update the failure chain.
2. Link assumptions, risks, blockers, and debt.
3. Identify the earliest state where the chain could be interrupted.
4. Add the smallest deterministic regression test for that interruption.
5. Promote repeated chains into release-gate scenarios.
