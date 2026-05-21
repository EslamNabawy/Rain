# Rain Worktree Cleanup And Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current Rain folder into a clean, stable, source-focused workspace while preserving the CI-green recovery baseline.

**Architecture:** Treat `codex/stable-recovery-20260521` as the canonical safe baseline. Clean generated outputs and detached worktrees before refactoring code. Then polish docs, package metadata, analyzer policy, and oversized Dart files in small tested slices.

**Tech Stack:** Flutter 3.44, Dart workspace resolution, Melos 7, Riverpod, Drift, Firebase Realtime Database, GitHub Actions, PowerShell release scripts.

---

## Current Snapshot

- Active worktree: `D:\old project\Rain`
- Active branch: `codex/stable-recovery-20260521`
- Current HEAD: `818851e fix: clear firebase audit gate`
- Latest known passing GitHub CI/CD: `https://github.com/EslamNabawy/Rain/actions/runs/26253559715`
- Secondary worktree: `D:\old project\Rain\build\main-promote-check`, detached at `0a85301 Merge manual artifact workflow into main`
- Local stashes:
  - `stash@{0}`: broken later connection/Iroh/Command Center work
  - `stash@{1}`: old leftover plan/doc cleanup
  - `stash@{2}`: pre-rollback backup
  - `stash@{3}`: older safe-clean worktree backup
- Tracked source files: about 251
- Main local output weight:
  - `apps/rain`: about 1506 MB, mostly `build/` and `.dart_tool/`
  - `.dart_tool`: about 403 MB
  - `final product`: about 290 MB
  - `packages/*/build`: about 289 MB combined
  - `build`: about 270 MB, including downloaded artifacts, test cache, and nested worktree

## Cleanup Rules

- Do not merge `dev` or `origin/main` into this branch until the Iroh/Rust/Command Center line is intentionally excluded or isolated.
- Do not drop stashes until the current branch is merged or backed up in GitHub.
- Do not delete `final product` artifacts until the user confirms local artifact retention policy.
- Prefer source cleanup over behavior changes first.
- After every code cleanup task, run the smallest relevant test, then the full Melos gates before merging.

---

### Task 1: Lock The Safe Baseline

**Files:**
- Modify: none
- Inspect: Git state only

- [ ] **Step 1: Confirm current branch and clean state**

Run:

```powershell
git status --short --branch
git log --oneline --decorate -5
```

Expected:

```text
## codex/stable-recovery-20260521...origin/codex/stable-recovery-20260521
818851e ... fix: clear firebase audit gate
```

- [ ] **Step 2: Confirm CI is still green**

Run:

```powershell
gh run view 26253559715 --json status,conclusion,url,headSha,headBranch
```

Expected: `status` is `completed`, `conclusion` is `success`, `headSha` is `818851e60b96b24cf776d77f7945f76b1cb0a3d7`.

- [ ] **Step 3: Create a local safety tag for the recovery point**

Run:

```powershell
git tag rain-stable-recovery-2026-05-22 818851e60b96b24cf776d77f7945f76b1cb0a3d7
git tag --list "rain-stable-recovery-*"
```

Expected: `rain-stable-recovery-2026-05-22` appears.

- [ ] **Step 4: Commit**

No commit is needed unless a tag push is requested. If pushing the tag is approved, run:

```powershell
git push origin rain-stable-recovery-2026-05-22
```

---

### Task 2: Quarantine The Nested Worktree

**Files:**
- Modify: none initially
- Candidate cleanup target: `D:\old project\Rain\build\main-promote-check`

- [ ] **Step 1: Verify the nested worktree is clean**

Run:

```powershell
git -C "D:\old project\Rain\build\main-promote-check" status --short --branch
git -C "D:\old project\Rain\build\main-promote-check" log -1 --oneline --decorate
```

Expected:

```text
## HEAD (no branch)
0a85301 ... Merge manual artifact workflow into main
```

- [ ] **Step 2: Remove the nested worktree from inside `build/`**

Run:

```powershell
git worktree remove "D:\old project\Rain\build\main-promote-check"
git worktree prune
git worktree list --porcelain
```

Expected: only `D:/old project/Rain` remains.

- [ ] **Step 3: Commit**

No commit is needed unless `.gitignore` or docs are changed in a later task.

---

### Task 3: Clean Generated Local Outputs Safely

**Files:**
- Modify: none initially
- Candidate cleanup targets:
  - `D:\old project\Rain\.dart_tool`
  - `D:\old project\Rain\apps\rain\.dart_tool`
  - `D:\old project\Rain\apps\rain\build`
  - `D:\old project\Rain\apps\rain\coverage`
  - `D:\old project\Rain\packages\peer_core\build`
  - `D:\old project\Rain\packages\peer_core\coverage`
  - `D:\old project\Rain\packages\protocol_brain\build`
  - `D:\old project\Rain\packages\protocol_brain\coverage`
  - `D:\old project\Rain\packages\rain_core\build`
  - `D:\old project\Rain\packages\rain_core\coverage`
  - `D:\old project\Rain\backend\firebase\functions\node_modules`
  - `D:\old project\Rain\build\github-artifacts-26197760726`
  - `D:\old project\Rain\build\test_cache`
  - `D:\old project\Rain\build\actionlint-1.7.8`
  - `D:\old project\Rain\build\native_assets`
  - `D:\old project\Rain\build\unit_test_assets`

- [ ] **Step 1: Print candidate sizes**

Run:

```powershell
$paths = @(
  ".dart_tool",
  "apps/rain/.dart_tool",
  "apps/rain/build",
  "apps/rain/coverage",
  "packages/peer_core/build",
  "packages/peer_core/coverage",
  "packages/protocol_brain/build",
  "packages/protocol_brain/coverage",
  "packages/rain_core/build",
  "packages/rain_core/coverage",
  "backend/firebase/functions/node_modules",
  "build/github-artifacts-26197760726",
  "build/test_cache",
  "build/actionlint-1.7.8",
  "build/native_assets",
  "build/unit_test_assets"
)
$repo = (Resolve-Path ".").Path
foreach ($relative in $paths) {
  $full = Join-Path $repo $relative
  if (Test-Path -LiteralPath $full) {
    $files = Get-ChildItem -LiteralPath $full -Recurse -Force -File -ErrorAction SilentlyContinue
    [pscustomobject]@{
      Path = $relative
      MB = [math]::Round((($files | Measure-Object Length -Sum).Sum / 1MB), 2)
    }
  }
}
```

Expected: every printed path is ignored/generated, not source.

- [ ] **Step 2: Remove only verified generated directories**

Run:

```powershell
$repo = (Resolve-Path ".").Path
$paths = @(
  ".dart_tool",
  "apps/rain/.dart_tool",
  "apps/rain/build",
  "apps/rain/coverage",
  "packages/peer_core/build",
  "packages/peer_core/coverage",
  "packages/protocol_brain/build",
  "packages/protocol_brain/coverage",
  "packages/rain_core/build",
  "packages/rain_core/coverage",
  "backend/firebase/functions/node_modules",
  "build/github-artifacts-26197760726",
  "build/test_cache",
  "build/actionlint-1.7.8",
  "build/native_assets",
  "build/unit_test_assets"
)
foreach ($relative in $paths) {
  $target = Join-Path $repo $relative
  if (-not (Test-Path -LiteralPath $target)) { continue }
  $resolved = (Resolve-Path -LiteralPath $target).Path
  if (-not $resolved.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove outside repo: $resolved"
  }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
```

Expected: `git status --short` remains clean except for intentionally changed plan/docs files.

- [ ] **Step 3: Restore dependency caches only when needed**

Run:

```powershell
dart pub get
```

Expected: root workspace dependencies restore without lock drift.

---

### Task 4: Normalize Ignore Policy

**Files:**
- Modify: `.gitignore`
- Modify: `apps/rain/.gitignore`

- [ ] **Step 1: Add broad generated dependency ignores at root**

Patch `.gitignore` so these entries are present:

```gitignore
**/node_modules/
**/.gradle/
**/coverage/
**/build/
```

Keep existing specific entries for local dart defines and `final product`.

- [ ] **Step 2: Decide Android wrapper policy**

Current state: `apps/rain/android/gradlew`, `gradlew.bat`, and `gradle/wrapper/gradle-wrapper.jar` are present locally but ignored and untracked. GitHub CI passes through Flutter tooling, but a clean local clone is more conventional if the wrapper is tracked.

Implementation choice for execution:

```text
Default: keep ignored for now, because CI is green and changing Android wrapper tracking is not required for this cleanup.
Follow-up: if local standalone Gradle builds are required, explicitly track wrapper files in a separate commit.
```

- [ ] **Step 3: Verify ignored outputs are not tracked**

Run:

```powershell
git check-ignore -v apps/rain/build backend/firebase/functions/node_modules packages/rain_core/build
git status --short --ignored | Select-Object -First 80
```

Expected: generated folders appear as ignored; source files do not.

- [ ] **Step 4: Commit**

Run:

```powershell
git add .gitignore apps/rain/.gitignore
git commit -m "chore: normalize generated output ignores"
```

---

### Task 5: Fix Package Metadata And Documentation Truth

**Files:**
- Modify: `apps/rain/README.md`
- Modify: `packages/peer_core/README.md`
- Modify: `packages/protocol_brain/README.md`
- Modify: `packages/rain_core/README.md`
- Modify: `packages/peer_core/LICENSE`
- Modify: `packages/protocol_brain/LICENSE`
- Modify: `packages/rain_core/LICENSE`
- Modify: `packages/peer_core/CHANGELOG.md`
- Modify: `packages/protocol_brain/CHANGELOG.md`
- Modify: `packages/rain_core/CHANGELOG.md`
- Modify: `docs/github-ci-cd.md`

- [ ] **Step 1: Replace template package READMEs**

Use short internal READMEs:

```markdown
# peer_core

WebRTC transport primitives for Rain.

## Scope

- Owns peer connection lifecycle.
- Owns data-channel framing and chunk handling.
- Does not know about Rain UI, Drift storage, or Firebase user records.

## Validation

```powershell
cd packages/peer_core
flutter test
```
```

```markdown
# protocol_brain

Signaling, session, retry, and connection-memory logic for Rain.

## Scope

- Owns signaling adapter contracts.
- Owns session establishment and retry policy.
- Uses `peer_core` for raw peer transport.
- Does not own UI or local message persistence.

## Validation

```powershell
cd packages/protocol_brain
flutter test
```
```

```markdown
# rain_core

Local persistence and domain services for Rain.

## Scope

- Owns Drift database schema and generated database code.
- Owns local identity, friends, messages, offline queue, and file-transfer records.
- Does not own Firebase signaling or Flutter UI.

## Validation

```powershell
cd packages/rain_core
flutter test
```
```

- [ ] **Step 2: Replace `apps/rain/README.md`**

Use:

```markdown
# Rain App

Flutter desktop and Android shell for Rain.

## Source Layout

- `lib/application`: bootstrap, Riverpod providers, runtime orchestration.
- `lib/core`: compile-time and platform configuration.
- `lib/infrastructure`: Firebase adapters and device/app services.
- `lib/presentation`: routes, screens, widgets, and theme.

## Local Run

```powershell
flutter run -d windows --dart-define-from-file=tool/dart_defines.example.json
```

## Validation

```powershell
flutter analyze
flutter test
```
```

- [ ] **Step 3: Replace placeholder licenses with truthful non-publishing text**

Use this exact content unless the owner chooses an open-source license first:

```text
Copyright (c) 2026 Rain.

All rights reserved.

This package is part of the Rain application workspace and is not licensed for
public redistribution as a standalone package.
```

- [ ] **Step 4: Replace placeholder changelogs**

Use:

```markdown
# Changelog

## 0.1.0

- Internal workspace package used by Rain.
```

- [ ] **Step 5: Update CI docs to match actual workflows**

Fix `docs/github-ci-cd.md` so:

```text
CI/CD runs on pushes and PRs.
Build Rain Apps is manual workflow_dispatch.
Release Rain is tag/manual release publishing.
```

- [ ] **Step 6: Verify no placeholder metadata remains**

Run:

```powershell
rg -n -g '!**/node_modules/**' "T[O]DO:|A new Flutter proj[e]ct|starting point for a Flutter applicati[o]n|T[O]DO: Add your license" apps packages docs README.md
```

Expected: no matches.

- [ ] **Step 7: Commit**

Run:

```powershell
git add apps/rain/README.md packages/peer_core packages/protocol_brain packages/rain_core docs/github-ci-cd.md
git commit -m "docs: replace template package metadata"
```

---

### Task 6: Consolidate Analyzer Configuration

**Files:**
- Modify: `analysis_options.yaml`
- Modify: `apps/rain/analysis_options.yaml`
- Modify: `packages/peer_core/analysis_options.yaml`
- Modify: `packages/protocol_brain/analysis_options.yaml`
- Modify: `packages/rain_core/analysis_options.yaml`

- [ ] **Step 1: Keep root as the source of analyzer policy**

Root `analysis_options.yaml` should contain:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"

  errors:
    invalid_annotation_target: ignore
```

- [ ] **Step 2: Make app and packages include the root policy**

Use this in each child `analysis_options.yaml`:

```yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 3: Verify analyzer still passes**

Run:

```powershell
dart run melos run analyze
```

Expected: all four workspace members pass.

- [ ] **Step 4: Commit**

Run:

```powershell
git add analysis_options.yaml apps/rain/analysis_options.yaml packages/*/analysis_options.yaml
git commit -m "chore: centralize analyzer policy"
```

---

### Task 7: Add A Safe Workspace Cleanup Script

**Files:**
- Create: `scripts/clean_workspace.ps1`
- Modify: `README.md`

- [ ] **Step 1: Create the script**

Create `scripts/clean_workspace.ps1`:

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$IncludeFinalProduct
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$relativePaths = @(
  '.dart_tool',
  'apps/rain/.dart_tool',
  'apps/rain/build',
  'apps/rain/coverage',
  'packages/peer_core/.dart_tool',
  'packages/peer_core/build',
  'packages/peer_core/coverage',
  'packages/protocol_brain/.dart_tool',
  'packages/protocol_brain/build',
  'packages/protocol_brain/coverage',
  'packages/rain_core/.dart_tool',
  'packages/rain_core/build',
  'packages/rain_core/coverage',
  'backend/firebase/functions/node_modules',
  'build/github-artifacts-26197760726',
  'build/test_cache',
  'build/actionlint-1.7.8',
  'build/native_assets',
  'build/unit_test_assets'
)

if ($IncludeFinalProduct) {
  $relativePaths += 'final product'
}

foreach ($relative in $relativePaths) {
  $target = Join-Path $repo $relative
  if (-not (Test-Path -LiteralPath $target)) {
    continue
  }

  $resolved = (Resolve-Path -LiteralPath $target).Path
  if (-not $resolved.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove outside repo: $resolved"
  }

  if ($PSCmdlet.ShouldProcess($resolved, 'Remove generated workspace output')) {
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
```

- [ ] **Step 2: Document usage in root README**

Add:

```markdown
## Clean Generated Outputs

Preview cleanup:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1 -WhatIf
```

Clean generated caches and build folders:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1
```

The script does not remove `final product` unless `-IncludeFinalProduct` is passed.
```

- [ ] **Step 3: Verify script syntax**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/clean_workspace.ps1 -WhatIf
```

Expected: prints removal candidates without deleting them.

- [ ] **Step 4: Commit**

Run:

```powershell
git add scripts/clean_workspace.ps1 README.md
git commit -m "chore: add safe workspace cleanup script"
```

---

### Task 8: Split Oversized App Providers

**Files:**
- Modify: `apps/rain/lib/application/state/app_providers.dart`
- Create: `apps/rain/lib/application/state/settings_providers.dart`
- Create: `apps/rain/lib/application/state/identity_providers.dart`
- Create: `apps/rain/lib/application/state/messaging_providers.dart`
- Create: `apps/rain/lib/application/state/runtime_providers.dart`
- Create: `apps/rain/lib/application/state/search_providers.dart`
- Test: existing app tests

- [ ] **Step 1: Move theme and recent-search providers**

Move `AppThemeMode`, `AppThemeModeX`, `ThemeModeController`, `themeModeProvider`, `RecentSearchesController`, and `recentSearchesProvider` to `settings_providers.dart`.

- [ ] **Step 2: Export moved providers from `app_providers.dart`**

Add:

```dart
export 'settings_providers.dart';
```

Keep existing imports working.

- [ ] **Step 3: Run focused tests**

Run:

```powershell
cd apps/rain
flutter test test/app_settings_store_test.dart test/search_screen_test.dart
```

Expected: pass.

- [ ] **Step 4: Move identity providers**

Move `identityRepositoryProvider`, `identityProvider`, and `IdentityController` to `identity_providers.dart`. Import shared providers from `app_providers.dart` only if needed through smaller internal provider modules.

- [ ] **Step 5: Move messaging and transfer providers**

Move `messagesProvider`, `MessagesController`, `fileTransfersProvider`, `FileTransfersController`, `fileTransferViewsProvider`, and `FileTransferViewsController` to `messaging_providers.dart`.

- [ ] **Step 6: Move runtime and connection providers**

Move `brainProvider`, `runtimeControllerProvider`, `RuntimeController`, `connectionsProvider`, and `ConnectionsController` to `runtime_providers.dart`.

- [ ] **Step 7: Move search providers**

Move `userSearchProvider`, `UserSearchController`, and `UserSearchState` wiring to `search_providers.dart`.

- [ ] **Step 8: Run app tests**

Run:

```powershell
cd apps/rain
flutter test
```

Expected: pass.

- [ ] **Step 9: Commit**

Run:

```powershell
git add apps/rain/lib/application/state apps/rain/test
git commit -m "refactor: split app provider modules"
```

---

### Task 9: Split `home_screen.dart` Into Focused Widgets

**Files:**
- Modify: `apps/rain/lib/presentation/screens/home_screen.dart`
- Create: `apps/rain/lib/presentation/widgets/home/shell_header.dart`
- Create: `apps/rain/lib/presentation/widgets/home/link_status.dart`
- Create: `apps/rain/lib/presentation/widgets/home/friends_list.dart`
- Create: `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
- Create: `apps/rain/lib/presentation/widgets/home/file_transfer_bubble.dart`
- Test: existing widget tests

- [ ] **Step 1: Move shell/header widgets**

Move `_ShellHeader` and `_RainHeaderIcon` into `shell_header.dart` as public or library-private widgets according to import needs.

- [ ] **Step 2: Move connection status widgets**

Move `_CompactLinkStatusPill`, `_MobileLinkStatusBar`, `_MobileLinkGlyph`, `_MobileLinkMeter`, `_ConnectionActionButton`, and `_LinkStatCard` into `link_status.dart`.

- [ ] **Step 3: Move friend list widgets**

Move `_FriendsListView` and `_FriendTile` into `friends_list.dart`.

- [ ] **Step 4: Move chat panel**

Move `_ChatPanel` and `_ChatPanelState` into `chat_panel.dart`.

- [ ] **Step 5: Move file transfer bubble**

Move `_FileTransferBubble` into `file_transfer_bubble.dart`.

- [ ] **Step 6: Run focused UI tests**

Run:

```powershell
cd apps/rain
flutter test test/root_screen_test.dart test/rain_navigation_shell_test.dart test/chat_composer_test.dart test/friend_flow_test.dart
```

Expected: pass.

- [ ] **Step 7: Commit**

Run:

```powershell
git add apps/rain/lib/presentation apps/rain/test
git commit -m "refactor: split home screen widgets"
```

---

### Task 10: Split Runtime Controller By Responsibility

**Files:**
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Create: `apps/rain/lib/application/runtime/file_transfer_runtime.dart`
- Create: `apps/rain/lib/application/runtime/message_runtime.dart`
- Create: `apps/rain/lib/application/runtime/friend_runtime.dart`
- Test: runtime and friend/file transfer tests

- [ ] **Step 1: Extract file-transfer helpers**

Move file transfer send/receive helpers and private file-transfer structs into `file_transfer_runtime.dart`. Keep `RainRuntimeController` as the public facade.

- [ ] **Step 2: Extract message helpers**

Move message send, queue, delivery acknowledgement, and channel message handling helpers into `message_runtime.dart`.

- [ ] **Step 3: Extract friend request helpers**

Move friend request refresh, accept/reject/block/unblock helpers into `friend_runtime.dart`.

- [ ] **Step 4: Run focused tests**

Run:

```powershell
cd apps/rain
flutter test test/friend_flow_test.dart test/runtime_network_loss_test.dart test/file_transfer_speed_export_test.dart
```

Expected: pass.

- [ ] **Step 5: Commit**

Run:

```powershell
git add apps/rain/lib/application/runtime apps/rain/test
git commit -m "refactor: split runtime controller helpers"
```

---

### Task 11: Split Protocol Brain Session Logic

**Files:**
- Modify: `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
- Create: `packages/protocol_brain/lib/src/ice_candidate_policy.dart`
- Create: `packages/protocol_brain/lib/src/session_retry_policy.dart`
- Create: `packages/protocol_brain/lib/src/active_session.dart`
- Test: protocol brain tests

- [ ] **Step 1: Move `_ActiveSession`**

Move `_ActiveSession` into `active_session.dart` and expose only the methods required by `ProtocolBrainImpl`.

- [ ] **Step 2: Move ICE policy helpers**

Move ICE attempt and transport policy selection helpers into `ice_candidate_policy.dart`.

- [ ] **Step 3: Move retry helpers**

Move retry/backoff/memory decision helpers into `session_retry_policy.dart`.

- [ ] **Step 4: Run protocol tests**

Run:

```powershell
cd packages/protocol_brain
flutter test
```

Expected: pass.

- [ ] **Step 5: Commit**

Run:

```powershell
git add packages/protocol_brain/lib packages/protocol_brain/test
git commit -m "refactor: split protocol brain session policy"
```

---

### Task 12: Rename Ambiguous Command Widgets

**Files:**
- Rename: `apps/rain/lib/presentation/widgets/rain_command_widgets.dart` to `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`
- Modify imports in: `apps/rain/lib/**`, `apps/rain/test/**`
- Test: widget tests

- [ ] **Step 1: Rename file**

Run:

```powershell
git mv apps/rain/lib/presentation/widgets/rain_command_widgets.dart apps/rain/lib/presentation/widgets/rain_chat_widgets.dart
```

- [ ] **Step 2: Replace imports**

Run:

```powershell
rg -n "rain_command_widgets" apps/rain/lib apps/rain/test
```

Then replace import paths with:

```dart
package:rain/presentation/widgets/rain_chat_widgets.dart
```

- [ ] **Step 3: Rename tests**

Run:

```powershell
git mv apps/rain/test/rain_command_widgets_test.dart apps/rain/test/rain_chat_widgets_test.dart
```

- [ ] **Step 4: Verify no old name remains**

Run:

```powershell
rg -n -g '!docs/superpowers/plans/**' "rain_command_widgets|Command Center|connection_command|Iroh|iroh|rust_lib_rain|flutter_rust_bridge" apps/rain/lib apps/rain/test packages docs .github pubspec.yaml apps/rain/pubspec.yaml
```

Expected: no matches, except `rain_chat_widgets` names if intentionally used.

- [ ] **Step 5: Run focused tests**

Run:

```powershell
cd apps/rain
flutter test test/rain_chat_widgets_test.dart test/home_screen_test.dart
```

If `test/home_screen_test.dart` does not exist, run:

```powershell
cd apps/rain
flutter test test/root_screen_test.dart test/chat_composer_test.dart
```

- [ ] **Step 6: Commit**

Run:

```powershell
git add apps/rain/lib apps/rain/test
git commit -m "refactor: rename chat widget module"
```

---

### Task 13: Reconcile Branches And Stashes

**Files:**
- Modify: none

- [ ] **Step 1: Confirm recovery branch is still clean**

Run:

```powershell
git status --short --branch
git log --oneline --decorate -8
```

- [ ] **Step 2: Create PR from recovery branch**

Run:

```powershell
gh pr create --base dev --head codex/stable-recovery-20260521 --title "Restore stable Rain baseline" --body "Restores the CI-green Rain baseline and excludes the broken Iroh/Rust/Command Center branch line."
```

- [ ] **Step 3: Do not merge `dev` into recovery**

Use cherry-picks only for known-good commits after review. Specifically avoid commits that add:

```text
apps/rain/rust/
apps/rain/rust_builder/
apps/rain/lib/infrastructure/iroh/
apps/rain/lib/src/rust/
connection_command_center.dart
flutter_rust_bridge.yaml
```

- [ ] **Step 4: Archive stashes after PR merge**

Before dropping stashes, export patches:

```powershell
New-Item -ItemType Directory -Force -Path build/stash-archive | Out-Null
git stash show -p 'stash@{0}' > build/stash-archive/stash-0-mess-before-stable-recovery.patch
git stash show -p 'stash@{1}' > build/stash-archive/stash-1-leftover-plan-docs.patch
git stash show -p 'stash@{2}' > build/stash-archive/stash-2-before-file-transfer-rollback.patch
git stash show -p 'stash@{3}' > build/stash-archive/stash-3-safe-clean-worktree.patch
```

Then drop only after confirming the patches are not needed:

```powershell
git stash drop 'stash@{0}'
git stash drop 'stash@{0}'
git stash drop 'stash@{0}'
git stash drop 'stash@{0}'
```

The repeated `stash@{0}` is intentional because indexes shift after each drop.

---

### Task 14: Final Verification Gate

**Files:**
- Modify: none

- [ ] **Step 1: Restore dependencies**

Run:

```powershell
dart pub get
```

- [ ] **Step 2: Run full analysis**

Run:

```powershell
dart run melos run analyze
```

Expected: all workspace packages pass.

- [ ] **Step 3: Run full tests**

Run:

```powershell
dart run melos run test
```

Expected: all non-emulator tests pass; emulator-only tests may remain skipped unless CI/emulator flag is enabled.

- [ ] **Step 4: Run Firebase backend audit**

Run:

```powershell
cd backend/firebase/functions
npx --yes npm@10.8.2 ci --ignore-scripts --no-audit
npx --yes npm@10.8.2 audit --omit=dev --audit-level=moderate
cd ../../..
```

Expected: `found 0 vulnerabilities`.

- [ ] **Step 5: Verify no forbidden backend/transport artifacts returned**

Run:

```powershell
rg -n -g '!**/node_modules/**' -g '!docs/superpowers/plans/**' "Supabase|supabase|Iroh|iroh|Command Center|connection_command|flutter_rust_bridge|rust_lib_rain" apps/rain/lib apps/rain/test packages backend scripts docs .github pubspec.yaml apps/rain/pubspec.yaml
```

Expected: no matches.

- [ ] **Step 6: Verify GitHub CI**

Run:

```powershell
git push
gh run list --branch codex/stable-recovery-20260521 --limit 1 --json databaseId,status,conclusion,url
```

Expected: new run completes with `conclusion: success`.

---

## Execution Order

1. Task 1: Lock baseline.
2. Task 2: Remove nested worktree.
3. Task 3: Clean generated outputs.
4. Task 4: Normalize ignores.
5. Task 5: Fix docs and package metadata.
6. Task 6: Centralize analyzer policy.
7. Task 7: Add cleanup script.
8. Task 8-11: Split oversized code files.
9. Task 12: Rename ambiguous command widget module.
10. Task 13: Reconcile branches and stashes.
11. Task 14: Final verification.

## Risks

- `dev` and `origin/main` contain the later broken branch line. Treat this recovery branch as canonical unless the owner explicitly wants to recover specific commits.
- `final product` contains user-facing artifacts. Do not delete it during automated cleanup unless explicitly requested.
- Android wrapper files are untracked and ignored. CI passes without changing this, so wrapper policy should be a separate decision.
- Refactoring `home_screen.dart`, `app_providers.dart`, and `rain_runtime_controller.dart` is high-touch. Do it after workspace cleanup and docs fixes, not before.
