# Rain App — Diagnostics Fix + Unified Tracing Design
**Date:** 2026-08-27
**Version:** 1.0.8 (build 9) — Windows, channel `demo`
**Source:** `rain-diagnostics-2026-08-27T204636-059426Z.json` (200 events, 25 ops, 1 call summary, 1 lastCrash)
**Status:** Design approved for implementation (tooling fallback: `create_brainstorm` failed with `Bun is not defined`, `bootstrapper` model `openai/gpt-5.2-codex` not found — synthesized manually from 6 branches)

---

## 1. Problem

### 1.1 User request
> Read diagnostics export and create (a) plan to fix all failures shown, (b) plan to track all app logs + pressing/interactions + what happens all time to trace problems.

### 1.2 What diagnostics shows

**Crash-adjacent (lastCrash, non-fatal `signaling.register`):**
```
Exception: Username "nour" is already taken or locked.
FirebaseSignalingAdapter.register:1376
 -> DebugSignalingAdapter._traceFuture:485
 -> IdentityController.register:147
 -> _OnboardingScreenState._submit:664
durationMs 1210, username [id:a49c68bd], passwordProvided true
```
User tried `nour` while `nourr` is active session user. Lock presumably prevents re-use, but error is generic, no suggestion, no expiry info.

**Call failure (callSummaries[0]):**
- `callId d6329f03`, peer `11491775` (`rowida`), `audio`, caller `f138fddd` (`nourr`)
- `ringing -> failed`, `mediaFailureReason: mediaConnectionFailed`, `failureTaxonomy: unknown` (3/3 unknown)
- `iceCandidateWriteCount 0`, `iceCandidateReadCount 0`, `relayFallbackAttempted false`
- Paradox: data `peer_core` session for same `pairId 3ac93655` succeeds flawlessly:
  - 12 local candidates, 3 data channels (`rain.file`, `rain.chat`), `host->host udp direct` (RTT 3-11ms), 13 ICE writes (~547ms) + remote adds
  - But `voice_*` room has `hasOffer false`, `hasAnswer false`, `hasCandidate false`, no SDP, mutedCount 2, voice ICE watches subscribed but never fire
- Presence kills call: `presence_session_expired` for rowida at `20:46:10.208` → `end_for_peer_requested` → `endCall 941ms` → `failed`. Second expiry at `20:46:35.252` even after disconnect. `watchPresence eventCount 2→3→4 online false/true flip`.
- Split-brain warning: `peer_ui_state_split_detected` — `callPhase failed` vs `sessionState connected` on same peer `11491775`/`3ac93655` → UI precedence undefined.
- Slow ops: `sendHeartbeat 1179ms/369ms/367ms`, `createOutgoingCall 738ms`, `writeICE 546-558ms`, `setPresence 371ms` on Windows desktop (not mobile). 25 ops, 0 reported failures, but latency >500ms p50.
- Cleanup hang: `voice_signaling_subscription_cancel_timeout` ×4, `subscriptionIndex 0..3`, `timeoutMs 2000` → 8s sequential hang on `brain_disconnect_requested` (`presence Expired` intent), blocks peer `media_state disposed`.
- Provider churn: `Provider<ConnectionDiagnostics> 15`, `PeerConnectivity 13`, `FriendsController 7` updates where `previousType == nextType` (no semantic change). 55 `ui_state` events of 200 (27%). `provider_disposed` interleaved with `provider_updated` suggests widget lifecycle thrash.
- Failure taxonomy useless: `unknown:3` captures everything; no distinction between `sdp_missing`, `ice_timeout`, `presence_expired`, `remote_offline`.

**Successful parts (to preserve):**
- Data plane works. Direct P2P over IPv4 host-host succeeds, chat/file messages delivered (`rain.chat` 135-137B, `rain.file` 215B).
- Heartbeats generally 366-369ms, offline detection works, but too aggressive.
- `debugEventSummary`: 200 events, `debug 133/info 58/warning 7/error 2` — good base, but no interaction events, no trace correlation.

### 1.3 Impact if not fixed
- Onboarding blocks returning users with locked names → churn.
- Voice calls 100% fail in demo (1/1), but data calls succeed → confuses users, “Call could not connect. Try again.” with no retry.
- 8s hang on hangup → ANR-like freeze.
- Unknown taxonomy → cannot prioritize, cannot alert.
- No press/interaction trace → cannot reproduce “what did user tap before failure”.

---

## 2. Findings by Branch

### Branch 1 — `auth_registration` (Identity / Username Claim)
**Scope:** Fix `nour` taken/locked race in `FirebaseSignalingAdapter.register` + onboarding UX.

- Root cause: claim is not atomic. Two paths: (a) username doc exists → exception, (b) lock doc exists with no TTL check. `failureReason null` in update block suggests lock cleanup missing. No pre-check, so UX discovers late after 1210ms write.
- Current flow: `_OnboardingScreenState._submit` → `IdentityController.register` → `_traceFuture` wraps but rethrows generic exception. No `usernameAvailable` query, no suggestion engine.
- Security note: `passwordProvided true` logged; ensure not logging plaintext password (diagnostics shows boolean only — correct).
- Options evaluated:
  - **Atomic transaction + TTL** (recommended): Firestore transaction on `usernames/{lower}` with `owner`, `lockedUntil`, `attemptCount`. On register, `runTransaction`: if absent or `lockedUntil < now` → claim; else → return `taken` with `nextAvailableAt` + top-3 suggestions (`nour_1`, `nour.rowida`, etc.). Needs Cloud Rule + composite index not needed. Pros: race-free, survives concurrent register. Cons: extra read (cost +1).
  - Pre-check + reserve: two-step with race window (not safe).
  - Backend queue: overkill for demo, adds function latency.
- Quick fix: catch `Exception: Username ... taken or locked` and show dialog “`nour` is taken — try `nour_7`, `nour.2026`? Or Sign in?” with Sign In CTA. Do not block lock forever; add 10-min lock expiry + janitor (like `cleanupStaleVoiceCallArtifacts`).
- Instrumentation: log `username_check{available,suggestedCount,lockAgeMs}` and `register_attempt{conflictReason}`.

### Branch 2 — `voice_webrtc_signaling` (Voice Call Media Path)
**Scope:** Fix `mediaConnectionFailed` with `hasOffer false / hasAnswer false` and data-vs-voice ICE confusion.

- Timeline proof:
  ```
  20:45:59.569 created voice call d6329f03 status=ringing hasOffer false hasAnswer false
  20:45:59.571 media_state startingLocalMedia -> 20:45:59.583 localMediaReady
  20:45:59.583 firebase_frame_send_started invite seq1 hasSdp false
  20:46:00.322 createOutgoingCall OK 738ms pairId 3ac93655 (== data session roomId!)
  20:46:10.208 presence expired → endCall failed (941ms) → phase failed
  ```
  Data session `3ac93655` already exists with `localCandidateCount 12` and ICE flowing. Voice call reuses same `pairId` but never writes `offer`/`answer`/`candidates` to `voice/*` path. `iceCandidateWriteCount 0` confirms voice ICE path dead.

- Hypotheses (ranked):
  1. **SDP creation skipped:** `audio_call_media_connection_created` fires but `createOffer`/`setLocalDescription` never called for voice `RTCPeerConnection`. Data `peer_core` code does it; voice `call_media` stops at `localMediaReady`. Check `call_media` `phase` state machine — missing transition `localMediaReady -> creatingOffer`.
  2. **Room/PairId collision:** `pairId 3ac93655` derived deterministically from `(caller,callee)` — same for data and voice. Writes collide: data uses `rooms/{roomId}/callerICE/*`, voice uses `voice/{callId}/offer` but also maybe `pairId` lock `a4311a7d` (see `lockPath [firebase-path:a4311a7d]`). If voice lock thinks room exists, `corruptRoomWasRepaired false` suggests no repair.
  3. **Offer not watched:** callee never gets `watchVoiceOffer` because caller never wrote it. Logs show `watchVoiceOffer subscribed` but zero `stream_event` for it.
  4. **ICE gathering never starts** for voice PC (closed too early: `peerConnectionClosed true, disposed true` at `20:46:19.162` after 8s timeout, but gathering should have started at `20:45:59.583`).

- Evidence against relay: direct host-host works for data (RTT 3ms), so network not blocked; `relayFallbackAttempted false` correct but should be attempted after ~3s.

- Fix path:
  - Audit `CallMediaController` / `VoiceSignalingAdapter`: ensure `createOffer({audio:true, video:false})` + `setLocalDescription` + write to `voice/{callId}/offer` with `sdpType offer`. Mirror answer path.
  - Separate namespaces: `rooms/{pairId}` for data, `calls/{callId}` for voice — verify not sharing same document. Add assert `pairId != callId`.
  - Add ICE gathering for voice: listen `onIceCandidate` → `writeVoiceIceCandidate` (currently only `writeICE` for `rooms/*`). Increment `iceCandidateWriteCount` correctly.
  - Timeout & fallback: if `hasOffer false` after 1500ms → `failureTaxonomy sdp_missing`, surface “Failed to create call — retry”. If ICE count 0 after 3000ms → try TURN.
  - Presence interaction: do not fail call solely on `presence_expired` if `sessionState connected` (split-brain). Rule: voice fail only if `presence expired && data session disconnected && no heartbeat 30s`. Today code does `end_for_peer_requested` immediately on expiry → too aggressive.

### Branch 3 — `failure_taxonomy_diagnostics`
**Scope:** Replace `unknown:3` with actionable taxonomy.

- Current: `failureReason mediaConnectionFailed`, `failureTaxonomy unknown`, `reasonCode failed`, detail generic. No `selectedCandidateRoute` loss at `20:46:35.259` (null after earlier `direct host->host`).
- Proposed taxonomy (enum):
  ```
  sdp_missing           // hasOffer/hasAnswer false
  sdp_exchange_failed   // write/read SDP Firestore error
  ice_gathering_failed  // 0 candidates after 3s
  ice_timeout           // candidates sent but no pair selected 5s
  dtls_failed           // peerConnectionState failed
  presence_expired      // watchPresence offline true
  presence_split_brain  // presence offline but data session connected
  peer_rejected / peer_busy / timeout_ringing (no answer 30s)
  cleanup_timeout       // subscription cancel 2000ms
  ```
- Implementation: `VoiceFailureClassifier` mapping `CallState + MediaState + PresenceSnapshot + NetworkOp` → taxonomy. Log with `failureTaxonomy`, `phase`, `hasOffer/hasAnswer`, `iceCounts`, `presenceAgeMs`, `rtt`.
- Diagnostics: add `failureTaxonomy` histogram to `debugEventSummary` and `callSummaries[*].failureTaxonomy`. Export to crash diagnostics record.
- User-facing: `Call could not connect. Try again. [SDP missing]` with retry CTA vs “Peer is offline” vs “Network — try TURN”.

### Branch 4 — `observability_tracing` (Unified Logging + Interaction Tracing)
**Scope:** Track *all* app logs + pressing/interactions + what happens all time with trace correlation.

- Today's gaps: only `provider_updated/disposed`, `operation_*`, `session_*` — zero `tap`, `navigation`, `input`, `lifecycle` events. No `traceId` linking `writeICE ×6` to single call. `count` aggregation hides individual latencies (e.g., `count:2` for 547ms). No offline export control.
- Design goals (per AGENTS.md: correctness > reliability > security > maintainability > simplicity):
  - **Single source of truth:** one `AppLogger` / `DiagnosticsController` that all layers call; no `print`.
  - **Structured & redacted:** JSON schema, PII scrub (`username → hash`, `candidate → length only`, `password → boolean`), size caps.
  - **Trace/span model (OpenTelemetry-lite):** `traceId` per user flow (register, call d6329f03, presence session hlqt531qoh), `spanId` per operation, `parentSpanId`. Propagated via `Async` context + Riverpod `Ref`.
  - **Interaction capture:** every press, navigation, text submit, lifecycle (`resume` already logged, add `pause`, `inactive`), connection change.
  - **Sampling & performance:** ring buffer 1000 events in mem, async flush to local store, no await on UI thread.
  - **Export/redaction already done for diagnostics** (hash filtering) — keep.

- Detailed plan in §3.

### Branch 5 — `presence_heartbeat_performance`
**Scope:** Fix heartbeat 367-1179ms jitter and presence false expiry.

- Data: `sendHeartbeat` duration: 1179ms max, 366-369ms typical, 6 ops. `setPresence 371ms`. `freshnessWindowMs 30000`, but `presenceAgeMs 2792` when confirmed online yet expired 10s later. `lastHeartbeat 1787863556773` vs `now 1787863547653` shows ~9s drift.
- Root: no jitter → thundering herd every 10s? Synchronous `await` on main isolate blocks UI. No offline queue → retry storms.
- Fixes (ranked):
  1. **Adaptive heartbeat:** 10s ±20% jitter, batch `setPresence + sendHeartbeat` into one `presenceHeartbeat` write, skip if already online and `presenceAge < 15s` (`cache_presence`).
  2. **Grace window:** increase `freshnessWindowMs` 30→45s for demo, or `gracePeriod 5s` after expiry before `end_for_peer`. Check `sessionState connected` → extend window to 60s.
  3. **Local cache:** `PresenceCache` with `lastSeen`, `lastHeartbeat`, `resolvedOnline` — `call_start_presence_confirmed` already does `presenceAgeMs 2792` check; reuse for `watchPresence` debouncing (500ms).
  4. **Firebase tuning:** coalesce writes (see §3), add index on `lastHeartbeat`, use `FieldValue.serverTimestamp()` not client `now`, avoid `cleanupStaleVoiceCallArtifacts` on every resume (limit 25 → could scan 25 docs each resume → 3ms locally but 371ms write).
  5. **Metric:** `heartbeat_latency_p50/p95`, `presence_flap_count`, alert if `p95 >500ms`.

### Branch 6 — `ui_state_provider_churn`
**Scope:** Reduce noisy providers and fix split state.

- Noise: `ConnectionDiagnostics` 15× and `PeerConnectivity` 13× where `previousType == nextType` (object identity change, not value change). Causes 55/200 events, rebuilds, and obscures real changes.
- Root: providers rebuild on every `peer_core` `session_changed` (5× at 20:45:46) even if `routeKind direct`, `rtt 0.011` unchanged. `NotifierProvider` uses `UnmodifiableMapView` → new instance each emit → `previous != next` by identity but equality same.
- Split warning `peer_ui_state_split_detected` fires at `20:46:11.151` after `endCall`. Code projects UI precedence between `callPhase failed` and `sessionState connected`. Today no rule.
- Fixes:
  - **Debounce + structural equality:** add `select` / `distinct` to providers; override `==`/`hashCode` for `PeerConnectivitySnapshot`, `ConnectionDiagnostics`; use `ref.watch(provider.select((s)=>s.hash))` or `distinctUntilChanged`.
  - **Single derived projection:** `PeerUiState = {callPhase, sessionState, presence, failureTaxonomy}` with precedence: `failed > ringing > connected > idle`. One provider, one update.
  - **Consolidate watches:** replace 4 separate `watchCall`/`watchVoiceOffer`/`watchVoiceAnswer`/`watchIceCandidates` with one `watchVoiceSession(callId)` multiplexed stream → reduces 4× `subscription_cancel_timeout`.
  - **Cleanup timeout fix:** `cancel()` should be `Future.any([sub.cancel(), Future.delayed(500ms)])` with `timeout 500ms` not 2000ms, and parallel `Future.wait` not sequential loop over 4 subs (currently sequential → 8s). See §3.5.

---

## 3. Recommendation — Two-Track Plan

### Track A — Fix Diagnostics Failures (Phased)

#### Phase 0 — Quick Wins (1-2 days, no breaking changes)
- [ ] **Auth UX:** catch `taken or locked` → dialog with suggestions + “Sign in” button. Add `username_suggestion` helper (lowercase, strip spaces, append 2-digit). Log `register_conflict`.
- [ ] **Taxonomy stub:** map `mediaConnectionFailed + hasOffer false -> sdp_missing`, `presence_expired` distinct, log it. Change `failureTaxonomy unknown` → at least 4 values. No logic change.
- [ ] **Provider distinct:** add `==/hash` + `select` to `ConnectionDiagnostics`, `PeerConnectivityController`. Expect 70% reduction in `provider_updated` noise. Keep warning but add `detail: {callPhase, sessionPhase}`.
- [ ] **Heartbeat jitter:** add `±20%` jitter to `sendHeartbeat` timer (10s → 8-12s), measure p95. One-line change.

#### Phase 1 — Voice Signaling Correctness (3-5 days, highest risk)
- [ ] **Audit & instrument voice SDP path:** add logs `voice_createOffer_started/completed`, `voice_setLocalDescription`, `voice_offer_written {hasSdp, sdpType, callId}`, `voice_answer_received`. Assert `hasOffer true` within 1.5s or fail `sdp_missing`.
- [ ] **Fix `call_media` state machine:** after `localMediaReady` → `creatingOffer` → `offerSent`. Ensure `createOffer` called with `audio:true` and `iceRestart false`.
- [ ] **Separate ICE paths:** create `VoiceIceController` using `voice/{callId}/callerICE` & `calleeICE` (not `rooms/{pairId}`). Verify `iceCandidateWriteCount` increments. Keep data `rooms/{pairId}` untouched.
- [ ] **Room identity:** ensure `callId != pairId`, log both. Add `lockClaimResult` already logs `pairId 3ac93655` — add `voiceRoomId vs dataRoomId` comparison.
- [ ] **Tests:** unit `VoiceSignalingAdapter` with fake Firestore: `invite hasSdp true`, callee `watchVoiceOffer` receives. Integration: two emulators `nourr -> rowida` audio call must reach `connected` phase in <4s, no presence flap.

#### Phase 2 — Presence & Performance (2-3 days)
- [ ] **Grace period:** before `end_for_peer_requested` on `session_expired`, check `sessionState == connected && rtt != null && lastDataMessage <5s` → delay 5s, re-check presence. Log `presence_split_brain_delayed`.
- [ ] **Heartbeat coalesce:** merge `setPresence` + `sendHeartbeat` into single `upsertPresence {online, lastHeartbeat, sessionId, state}` with `serverTimestamp`. Cache locally, skip write if `now - lastWrite <8s`.
- [ ] **Latency budget:** add `firebase_write_latency` histogram, alert `>600ms p95`. Add index if `cleanupStaleVoiceCallArtifacts` slow (currently 3ms OK).
- [ ] **TURN fallback:** behind flag `allowRelayFallback`. If `iceCandidateWriteCount >0 && selectedCandidatePairId == null` after 4s → restart ICE with `iceTransportPolicy relay`.

#### Phase 3 — Cleanup & Reliability (2 days)
- [ ] **Parallel subscription cancel:** replace sequential `for (sub in subs) await sub.cancel().timeout(2s)` with `Future.wait(subs.map((s)=>s.cancel().timeout(500ms).catchError(...)))`. Log `voice_signaling_subscription_cancel_timeout` as `warning` not blocking. Target <600ms total.
- [ ] **EndCall idempotency:** `endCall {callId, endedAt, reasonCode}` already best-effort. Make `callee` side also handle `failed` idempotently (today duplicate `signaling_end_call_started` at 20:46:35 for same `d6329f03`).
- [ ] **Update channel `demo` guard:** `update.status current` already — add `minimumVersion` bump test.

**Exit criteria for Track A:** 10 consecutive audio calls `ringing -> connected` <4s, `iceCandidateWriteCount >3`, taxonomy not `unknown`, no `cancel_timeout` >600ms, heartbeat p95 <500ms, provider updates <5 per 10s.

### Track B — Unified Tracing System (“track all logs + pressing + what happen all time”)

#### B.1 Goals & Non-Goals
- **Goals:** full trace of *what happened, when, why, who, how long* for any bug with zero repro steps needed. Capture logs, interactions, network, WebRTC, lifecycle, state, with correlation.
- **Non-goals:** not a replacement for crash reporter (keep `lastCrash`), not full video replay, not tracking across users.

#### B.2 Event Schema (single JSON shape for `events[]`)

```dart
// lib/infrastructure/diagnostics/app_event.dart
class AppEvent {
  String traceId;      // flow id: uuid v4, e.g., "tr_3ac9..." per call/register
  String? spanId;      // operation id
  String? parentSpanId;
  String kind;         // "app_event"
  String category;     // network | ui_state | call | connection | webrtc | interaction | lifecycle | presence
  String name;         // e.g., "tap", "operation_started", "peer_connected", "heartbeat_sent"
  String severity;     // debug | info | warning | error | fatal
  DateTime recordedAt; // server-clock-adjusted, monotonic
  Duration? durationMs;
  Map<String,dynamic> context; // redacted, size-capped 2KB
  int count; // aggregation (keep but also store first/last timestamps)
}
```

- Existing `operation_started/completed` maps to `span` with `durationMs`. Add `traceId` to both.
- Redaction: `username -> [id:hash8]` already done; add `candidate -> length only`, `sdp -> type+length`, `password -> bool`, `ip -> family only`.
- Size cap: 2KB per context, truncate `decisions[]` etc.

#### B.3 Layers & What to Capture

| Layer | What | Where to hook | Example events |
|-------|------|---------------|----------------|
| **Interaction (pressing)** | tap, longPress, doubleTap, scroll, swipe, textInput, submit, back, navigation push/pop | `InteractionLogger` wrapper: `GestureDetector` + `NavigatorObserver` + `TextField.onSubmitted`; Riverpod `ProviderObserver` already logs `provider_*` | `interaction_tap {widget, route, traceId, position}`, `interaction_navigation {from,to,reason}`, `interaction_input {field,length}` |
| **UI State** | provider add/update/dispose with diff, not just type | `DiagnosticsProviderObserver` (extends `ProviderObserver`) — add `diff` and throttle | `provider_updated {provider, prevHash, nextHash, changedKeys}` |
| **Network** | every Firebase op: started/completed/failed + watch subscribe/event/unsubscribe | `DebugSignalingAdapter._traceFuture` & `_traceWatch` — add `traceId` param | `operation_started {operation, kind, traceId}`, `stream_event {operation, eventCount}` |
| **Call** | invite, ring, accept, end, reason, taxonomy, route | `CallController` / `VoiceSignalingAdapter` | `state_changed {phase, failureTaxonomy, traceId, callId}` |
| **WebRTC** | peerState, candidate add, channel open, mediaState | `peer_core`, `call_media` | `remote_ice_candidate_added {candidateLength, traceId}` |
| **Connection/Presence** | session connect/disconnect, heartbeat, presence watch | `ConnectionManager`, `PresenceHeartbeat` | `session_connected {rtt, routeKind, traceId}`, `heartbeat_sent {durationMs}` |
| **Lifecycle** | app resume/pause, network_available, error | `WidgetsBindingObserver`, `FirebaseCrashlytics` | `network_available {recoverablePeerCount}` |
| **System** | performance tier, memory, battery | `PerformanceController` | `tier_changed {tier, reason}` |

- **Pressing specifics:** log logical action, not raw pixels (privacy). E.g., `tap {target: "onboarding_submit_button", route: "/onboarding"}` not `(x: 123, y:456)`. Capture `widget key` or `semanticLabel`.

#### B.4 Trace Correlation (most important)

```dart
// per flow
final traceId = TraceContext.create(); // uuid
// propagate via Zone or Riverpod override
runZoned(() => register(traceId), zoneValues: {#traceId: traceId});

// all child spans inherit
Future<T> traceFuture<T>(String operation, String kind, Future<T> Function(String traceId) fn) async {
  final spanId = newSpanId();
  log(operation_started, traceId, spanId);
  final sw = Stopwatch()..start();
  try {
    final res = await fn(traceId);
    log(operation_completed, traceId, spanId, durationMs: sw.elapsedMilliseconds);
    return res;
  } catch (e, st) {
    log(operation_failed, traceId, spanId, error: e, stackTrace: st);
    rethrow;
  }
}
```

- One `traceId` per: `register_{username}`, `call_{callId}`, `session_{pairId}`, `heartbeat_cycle`.
- Link `call traceId` to `data session traceId` when `pairId` shared → `parentTraceId` field.
- Include `traceId` in Firebase doc for cross-device correlation: `calls/{callId} {traceId, creatorTraceId}`.

#### B.5 Storage & Performance

- **In-memory ring:** `DiagnosticsBuffer(capacity: 1000)` — current 200/1000 OK. Keep `debug 133/info 58` levels; add `interaction` at `debug`.
- **Persist:** `Drift` (SQLite) table `app_events` with index `(traceId, recordedAt)`, TTL 7 days, prune job daily. Also persist `callSummaries` and `lastCrash`.
- **No blocking:** `log()` is sync enqueue, `flush()` is `unawaited` with `try/catch`, backpressure drop oldest.
- **Sampling:** `debug` always in mem, `info+` persisted, `debug` persisted only if `traceId` has `error/warning` (tail sampling).
- **Export:** already exports `rain-diagnostics-YYYY-MM-DDTHHmmss.json` with `exportedAt`, `app`, `events`, summaries. Keep redaction. Add:
  ```json
  {
    "traceSummaries": [{"traceId":"tr_...","flow":"call","durationMs":11082,"eventCount":42,"outcome":"failed:sdp_missing"}],
    "interactionSummary": {"tapCount":12,"navigationCount":3,"mostTapped":"call_button"}
  }
  ```
  Add `shareDiagnostics()` button (already exists?) → `Share.shareXFiles([jsonFile])` or `mailto:`. Add `copyTraceId` long-press.

#### B.6 UI for Tracing / Debug

- **Debug overlay (demo only):** floating `DiagnosticsSheet` showing live tail (last 20 events, filter by `traceId`/`category`), `Copy diagnostics` FAB. Gate behind `kDebugMode` or `channel == demo`.
- **Trace viewer:** internal page `/debug/traces` list `traceId` → timeline (span waterfall) for call `d6329f03`.
- **Interaction heatmap (optional):** overlay tap indicators for 500ms after tap in demo — helps repro.

#### B.7 Privacy & Cost

- Hash `username`/`peerId` as `[id:hash]` (already). Do not log `password`, `sdp`, `ip`, `candidate` raw — log `length`, `type`, `family`.
- Firebase cost already counted: `signalingReads 2, signalingWrites 4, cleanupWrites 2` per diagnostics — acceptable. New tracing adds 0 Firebase writes (local only) except `traceId` field in `calls/{callId}` (+0 writes, field in existing doc). Heartbeat coalesce actually *reduces* cost ~50%.
- Local DB size: 1000 events × ~400B avg → 400KB + 7-day TTL → <5MB worst.

#### B.8 Implementation Steps (B)

1. **Core (2 days):** create `TraceContext`, `AppLogger`, `DiagnosticsBuffer`, `DiagnosticsProviderObserver` extension. Replace all `print`/`debugPrint` with `log()`.
2. **Interaction (1 day):** add `InteractionLogger` widget wrapping `MaterialApp`, `AppNavigatorObserver`, log `tap/navigation/input`.
3. **Propagation (1 day):** thread `traceId` through `register`, `createOutgoingCall`, `sendHeartbeat`, `writeICE`. Update `_traceFuture` signature.
4. **Persist & Export (1.5 days):** Drift setup, `DiagnosticsRepository` with `saveEvent`, `queryByTraceId`, `exportJson`, `prune`. Wire `shareDiagnostics`.
5. **UI (1 day):** `DiagnosticsSheet`, `/debug/traces` page (demo).
6. **Tests (1.5 days):** verify `tap -> event count+1`, `traceId` propagates end-to-end, export redacts PII, buffer drops oldest, no await in `build`.

**Exit criteria Track B:** tap button → event appears in export json within 100ms, `traceId` links `operation_started` + `tap` + `call failed` same flow, diagnostics json opens after `share`, no jank (`frame time <16ms` with logger on).

---

## 4. Cross-Cutting Concerns

**Security:**
- Keep `passwordProvided bool` not string. Audit `context` for `candidate`, `sdp`, `email`.
- Validate username suggestion not enumerable (rate-limit `fetchIdentity` 2× already 5ms OK, but add 10 req/min per IP via rules).
- Diagnostic export file contains no raw IP — already truncated to `addressFamily ipv4`.

**Reliability:**
- All new Firebase writes `bestEffort true` already — keep.
- Add `retry` with exponential backoff for `sendHeartbeat` only if `failed true` (0 failures today, but 1179ms suggests near timeout).
- `voice_signaling_subscription_cancel_timeout` parallelization prevents 8s hang → reliability.

**Maintainability:**
- One `AppEvent` schema, not per-category ad-hoc maps. Generate `toJson` with `freezed`.
- Keep `debug_signaling_adapter.dart:485` wrapper single point; no scattered `log()`.

**Operational simplicity:**
- No new backend. No OTEL collector. Uses existing Firebase + local SQLite.
- Feature flags: `allowContinuousCallAnimation true` already — add `enableInteractionTracing true` for demo.

**Performance:**
- Budget: `log()` <10µs, `buffer enqueue` <5µs, `persist` batch 50 events ~5ms background. Measured via `slowestOperations` already 500ms+ for Firebase — tracing adds 0 to that path.
- Disable `debug` persist in `release` unless trace has error.

---

## 5. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| SDP fix requires refactor of `call_media` | Regress data session | Keep data `peer_core` untouched, new `VoiceMediaService` class, flag `useNewVoiceSdp` |
| Presence grace delays real offline detection | User waits 5s extra for “peer offline” | Show “Reconnecting…” interim, only delay `endCall` not UI; use `split_brain` taxonomy |
| Interaction logging noisy (55 already) | 200→600 events | Sample: throttle `provider_updated` to distinct, cap `tap` 30/s, drop duplicate `session_changed` |
| Diagnostics file grows big | Share fails | Cap export 500 events, compress gzip option, TTL prune |
| Hash collisions hide bug | Hard to map `[id:xxx]` to user | Add local `idMap` (hash→displayName) only in export, not uploaded |

---

## 6. Verification Plan

- **Repro scripts:**
  - `register_collision_test`: try register `nour` while `nourr` online → expect suggestion dialog, no crash, log `register_conflict`.
  - `call_sdp_test`: `nourr` → `rowida` audio call, assert `hasOffer true`, `hasAnswer true`, `iceWriteCount >0`, `phase connected` <4s, no `unknown` taxonomy.
  - `presence_flap_test`: kill `rowida` heartbeat 35s → `watchPresence offline` but `sessionState connected` → no immediate `endCall`, after 5s → `presence_split_brain`.
  - `cleanup_timeout_test`: hangup call → `cancel` all 4 subs <700ms, no `cancel_timeout` warning.
  - `interaction_trace_test`: tap onboarding submit → diagnostics json contains `interaction_tap {target:onboarding_submit}` + same `traceId` as `signaling.register`.

- **Metrics to watch (after fix):**
  - `failureTaxonomy != unknown` 100%
  - `call_success_rate` audio >95% (demo target)
  - `heartbeat_p95 <500ms`, `createOutgoingCall p95 <400ms`
  - `provider_updated` rate <5 /10s
  - `diagnostics_export_size` ~150-300KB

---

## 7. Open Questions

- [ ] Should `pairId 3ac93655` be reused for voice? Recommendation: **no**, use `callId` for voice docs. Confirm with `protocol_brain` owner.
- [ ] `demo` channel `minimumVersion 1.0.8` — will we force update for tracing schema change? No, schema additive.
- [ ] TURN server credentials available? If not, relay fallback cannot be tested; gate behind config.
- [ ] Where to upload diagnostics? Keep local + manual share, or auto-upload on `fatal true` to Crashlytics? Decide: auto-upload only `fatal true` with consent.

---

## 8. Appendix — Diagnostics Timeline Annotated

```
20:45:46 data session 3ac93655 HOST-HOST direct established (12 cands, 3 chans)
20:45:47-50 ICE trickle data OK (~547ms each, 6 writes)
20:45:59.569 VOICE call d6329f03 CREATED hasOffer false  ← BUG
20:46:00.322 VOICE invite written 738ms pairId=3ac93655 (collision)
20:46:10.208 presence rowida OFFLINE → voice FAILED mediaConnectionFailed unknown ← WRONG (data still up)
20:46:11.150 split-brain warning callPhase failed vs session connected
20:46:13-19 4× subscription cancel timeout 2s sequential = 8s hang
20:46:19.162 media disposed, brain_disconnect presence Expired
20:46:35 second presence expiry, second endCall attempt (idempotent)
```
**Fix order:** SDP → presence grace → cancel parallel → taxonomy → tracing.

---

**Next step:** Implement Phase 0 before next demo build; review voice SDP diff in `protocol_brain` PR.
