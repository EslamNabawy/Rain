# Rain Call Runtime Final Release Gate - 2026-05-25

Gate status: BLOCKED - DRAFT PR OPEN

This gate opened the PR path but did not certify the branch for release. Phase
13 is still blocked because no physical Android device is visible from this
machine and `adb` is not available on `PATH`.

## Source

```text
Branch: codex/rain-rebrand-implementation
Base target: dev
Head commit at gate start: c335a57
Draft PR: https://github.com/EslamNabawy/Rain/pull/7
Manual device gate: BLOCKED
Cloud artifact workflow: NOT TRIGGERED
```

## Git Status Check

The pushed branch matches `origin/codex/rain-rebrand-implementation`.

Local working tree still contains pre-existing uncommitted rebrand planning
docs that were intentionally excluded from this call-runtime release gate:

```text
docs/superpowers/plans/2026-05-24-rain-app-rebrand-phased.md
docs/superpowers/specs/2026-05-24-rain-app-rebrand-phased-rollout.md
docs/superpowers/specs/2026-05-24-rain-brand-identity-design.md
```

## Phase Commit Evidence

Recent call-runtime gate commits:

```text
c335a57 docs: record call stability device gate
74d3710 docs: complete automated validation gate
f9bf396 test: cover call runtime failure recovery
0b928fd feat: use dynamic video camera controls
b38d25d feat: model video device capabilities
50a8f86 fix: simplify call surface rendering
e8e46e5 fix: allow reconnect after manual disconnect
05eca38 fix: stabilize call clock and mute state
22a7fb7 fix: harden video media failures
9014b7e fix: reconcile terminal call state
76a0c87 fix: preserve call direction during retry
e8d0d5a fix: clean stale Firebase call leases
2515071 fix: gate navigation behind Rain startup readiness
f15c812 docs: audit Rain call runtime failures
3398cad docs: plan call runtime stability fixes
```

## Automated Validation

Phase 12 passed on this branch:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

## PR Contents

The draft PR includes:

- root causes fixed across startup readiness, Firebase call leases, retry
  direction, terminal call cleanup, video media failure handling, call clock and
  mute state, reconnect intent reset, call surface rendering, and media device
  capability inventory.
- integrated tests for first-attempt voice/video runtime paths.
- the blocked manual device matrix.
- residual risk notes that real Android device evidence is still missing.

## Cloud Build Decision

The cloud build workflow was not triggered from this gate. Although the branch
is pushed and automated validation is green, the final release purpose is to
ship only after runtime, UI, and manual paths agree. Phase 13 does not yet have
manual device evidence.

Trigger the cloud artifact workflow only when the owner wants fresh test
artifacts for manual device validation, or after the manual-device blocker is
explicitly waived.

## Merge Decision

Do not merge PR #7 until one of these is true:

1. The manual device matrix passes on current artifacts from this branch.
2. The manual device gate is explicitly waived by the owner, and the PR notes
   keep that waiver visible.
