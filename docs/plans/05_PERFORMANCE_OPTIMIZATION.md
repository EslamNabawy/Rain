# 05 — Performance Optimization Plan

Source: `PROJECT_DEEP_ANALYSIS.md` (no explicit perf findings; these are **inferred from structure**, confidence stated). No perf benchmark was run this pass — metrics below are baselined for *you* to measure.

---

## P-1 — Giant Integration Test Files Block CI Feedback  (TASK-003)
- **Bottleneck:** `friend_flow_test.dart` = **9,212 lines**; `rain_chat_widgets_test.dart` = 2,874; `runtime_startup_test.dart` = 1,510. One failing assertion reruns the whole suite; CI test step is serial + monolithic.
- **Reason:** No per-flow/per-widget isolation; Dart test runner processes each file in one isolate.
- **Expected gain:** 50–70% faster per-change test feedback; failing test localizes to a 200-line file instead of a 9k one.
- **Difficulty:** M (splitting requires import/helper extraction).
- **Benchmark:** `flutter test test/friend_flow_test.dart --reporter=compact` wall-clock before/after.
- **Success metric:** No single test file > 1,500 lines; total CI test time ↓ vs baseline.

## P-2 — God-Object Hot Paths Hurt Maintainability → Ship Cadence  (TASK-004)
- **Bottleneck:** `voice_call_runtime.dart` (3,106) compiled into one translation unit; every call-path edit risks the whole file.
- **Reason:** Monolith; no interface seams for tree-shaking or lazy init.
- **Expected gain:** Faster incremental `flutter analyze`/`build` on call changes; smaller diffs.
- **Difficulty:** XL.
- **Benchmark:** `dart analyze apps/rain` and `flutter build apk --debug --target-platform android-arm64` time before/after extraction.
- **Success metric:** No `lib/` file > 800 lines; build delta per call-change ↓.

## P-3 — Drift WAL + busy_timeout Are Good; Add Read Replicas  (TASK-008)
- **Bottleneck (inferred, LOW confidence):** Single `driftDatabase(name:'rain', shareAcrossIsolates:true)` (`rain_database.dart:303`). All UI reads + background writes hit one executor.
- **Reason:** No read/write split; `PRAGMA busy_timeout=5000` + WAL already set (good).
- **Expected gain:** Smoother scroll on long conversations under active file transfer.
- **Difficulty:** S.
- **Benchmark:** Scroll a 5k-message conversation while a 50MB transfer runs; measure dropped frames.
- **Success metric:** No UI jank ≥ 16ms during concurrent write.

## P-4 — Firebase Watcher Subscription Order Causes 45s Call Stalls  (TASK-005)
- **Bottleneck:** Outgoing call subscribes watchers *after* `startOutgoing()` (`voice_call_runtime.dart:163-169`) → fast remote answer missed → 45s ringing timeout.
- **Reason:** Asymmetric ordering vs incoming path.
- **Expected gain:** Eliminates a class of "call sits in ringing then fails" — direct latency + reliability win.
- **Difficulty:** XS.
- **Benchmark:** Instrument `outgoingRinging → active` latency; assert < 5s with a fast remote.
- **Success metric:** 0 missed-answer outgoing calls in integration suite.

## P-5 — Trickle-ICE Buffering Already Fixed; Verify Candidate Replay  (TASK-007-adjacent)
- **Bottleneck (inferred):** `addRemoteCandidate` chains via `_candidateLock` (fixed F-008). If a candidate arrives before `setRemoteDescription`, it must buffer and flush — verify no drop under poor networks.
- **Reason:** Network-timing dependent.
- **Expected gain:** Fewer ICE-restart loops on flaky mobile networks.
- **Difficulty:** S.
- **Benchmark:** Emulator with 30% packet loss; measure connect time + ICE-restart count.
- **Success metric:** Connect succeeds without manual retry on impaired link.

---

## Performance Priorities (by effort↑ / impact↑)
| Opt | Effort | Impact | Do when |
|---|---|---|---|
| P-4 (watcher order) | XS | HIGH (latency+reliability) | **Now** |
| P-1 (test split) | M | MED (dev velocity) | Sprint 2 |
| P-5 (ICE replay) | S | MED | Sprint 2 |
| P-3 (read split) | S | LOW | Sprint 3 |
| P-2 (god split) | XL | MED (cadence) | Sprint 3 |

> All P-items are **inferred** (no profiling run). P-4 is the only one with a provable code path (TASK-005). Treat P-1..P-3 as hypotheses to baseline before claiming gain.
