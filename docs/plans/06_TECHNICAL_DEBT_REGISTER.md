# 06 — Technical Debt Register

| ID | Debt | Severity | Cost to Fix | Cost of Ignoring | Recommendation |
|---|---|---|---|---|---|
| DEBT-001 | Signaling uses one app-wide shared key + constant HKDF salt (`signaling_cipher.dart:6-40,164`) | **HIGH** | L (3–4 wk, needs TASK-015) | Privacy promise broken; any key leak decrypts all historical signaling | TASK-001: per-pair X25519 + random salt. Top P0. |
| DEBT-002 | Local Drift DB cleartext (`rain_database.dart:303-316`) | **HIGH** | M (1–2 wk, needs TASK-015) | Message history / file paths / fingerprints readable on device theft | TASK-002: SQLCipher + secure key. Document as ADR-010 Option A until fixed. |
| DEBT-003 | `apps/rain/lib` has 0 mirror unit tests (112 files) | **HIGH** | L (2–3 wk) | Regressions caught only by 9k-line integration suite; slow, unlocalized | TASK-003: per-provider/per-screen tests + split `friend_flow_test.dart`. |
| DEBT-004 | Call/runtime god-objects (`voice_call_runtime.dart` 3,106; `firebase_adapter.dart` 2,912; `rain_runtime_controller.dart` 2,573) | **HIGH** | XL (4–6 wk) | Concentrated race/correctness risk; review bottleneck; grew since audit | TASK-004: extract to focused coordinators + CI line-limit gate. |
| DEBT-005 | `failed→idle` non-terminal transition (`voice_call_session.dart:1134`) | **MED** | XS | Half-dead session resurrection possible | TASK-006: delete edge; make `failed` terminal. |
| DEBT-006 | Mute state race — user toggle vs interruption both write `_microphoneMuted` (`call_media_connection.dart:438,543`) | **MED** | S | Mute/interrupt divergence; wrong mute on reconnect | TASK-007: serialize via media lock. |
| DEBT-007 | No `beforeOpen` schema validation / transactional migrations (`rain_database.dart:142-160`) | **MED** | S | Silent DB corruption on partial upgrade | TASK-008: add `beforeOpen` + transaction-wrap. |
| DEBT-008 | Outgoing call watcher subscribes after invite (`voice_call_runtime.dart:163-169`) | **MED** | XS | Fast remote answer missed → 45s ringing timeout | TASK-005: move watcher before `startOutgoing()`. |
| DEBT-009 | Dense RTDB rules (~776 lines) with enumerated-only contract tests | **MED** | M | Correctness blind spot; hard to extend safely | TASK-017: commented rules source + fuzz harness. |
| DEBT-010 | No OS-backed secret store + no identity keypair columns (`identity.dart:15-18`) | **HIGH** (foundational) | M | Blocks DEBT-001/002; no safe place for keys | TASK-015: `flutter_secure_storage` + `IdentityKeyRepository`. |
| DEBT-011 | Session-reuse discipline not enforced (`voice_call_runtime.dart`) | **MED** | S | Reuse of terminal session → disposed-media entry | TASK-016: fresh-instance guard. |
| DEBT-012 | 27 `debugPrint` in `lib/` + stale "0 print" audit claim | **LOW** | S | Log noise; doc-integrity erosion | TASK-018: route via sanitizer + fix doc. |
| DEBT-013 | No root LICENSE (`README.md:364`) | **LOW** | XS | Legal ambiguity for public repo | TASK-019: add license. |
| DEBT-014 | Untracked root artifacts (`IDEA.md`, `deps.txt`) | **LOW** | XS | Repo noise | TASK-020: gitignore/remove. |
| DEBT-015 | Windows not in merge-gate CI (only release `build-artifacts.yml`) | **LOW** | S | Windows breakage can merge silently | TASK-021: add config-check + build job to `ci.yml`/`main-merge-gate.yml`. |
| DEBT-016 | No remote crash/telemetry (Crashlytics/Sentry absent) | **LOW** | M | Blind in production; can't diagnose field failures | Add Crashlytics behind existing sanitizer (post-1.0). |
| DEBT-017 | No CODEOWNERS / branch protection observed | **LOW** | S | Risky files (call runtime) merge without review | Add `CODEOWNERS` + protected `dev`/`main`. |

> Total: **17 debt items** (4 HIGH, 7 MED, 6 LOW). DEBT-010 is the keystone — it gates DEBT-001/002. DEBT-008/005/006/007/011 are cheap and should land in Sprint 1–2.
