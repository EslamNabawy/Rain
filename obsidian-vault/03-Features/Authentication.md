# Authentication

## Purpose

Allow users to own a Rain account by username/password.

## Business Value

Provides simple identity for accepted-friend communication without social-network complexity.

## User Flow

1. User opens app.
2. User signs in or creates an account.
3. Firebase Auth verifies identity.
4. Local identity and friend state load.

## Technical Flow

- App uses Firebase Auth.
- Username maps to Rain user records in RTDB.
- Local identity is stored in Drift.
- Current implementation treats Drift `identity_table` as a cached session candidate, not authenticated truth.
- `IdentityController` validates the cached username against Firebase/Auth adapter state and the backend `users/{username}` record before restoring a signed-in app identity.
- Backend `uid` must match the current Firebase/auth adapter uid. Missing backend account data, missing uid data, uid mismatch, or session-expired errors clear local session data instead of restoring the user.
- Register/login write backend identity and presence before saving Drift identity locally, so local cache does not get ahead of backend truth.
- Registration handles RTDB permission-denied conflicts as account-data conflicts instead of raw Firebase errors. If the primary `users/{username}` row fails before creation, the just-created Firebase Auth user is rolled back. If the durable user row was already created and a secondary registration step fails, Rain signs out without deleting Auth, so it does not create a worse Auth/RTDB orphan.
- Logout clears local Drift session data before best-effort backend sign-out, so Firebase permission/sign-out failures cannot keep the old cached identity alive.
- Runtime-provider logout ends the authenticated session from a `finally` path even when cleanup reports a non-local backend failure.
- Runtime-provider logout clears local session data before awaiting runtime/backend cleanup, detaches protected-session authority, and renders signed-out while Firebase/runtime cleanup continues best-effort in the background. Account deletion reauthenticates first, writes the backend tombstone/Auth `deleteAccount` path before runtime teardown, then clears local session and detaches protected-session authority only after the delete succeeds or reaches a post-tombstone point of no return. Required tombstone failure keeps the user signed in and surfaces an error. Optional search, relationship, request, block, presence, and active-call cleanup is best-effort after the tombstone boundary. `AppStartupState` treats runtime loading and null runtime as blocked startup, so protected shell/navigation cannot remain interactive during teardown.
- `RainRuntimeController` rejects new connect actions once shutdown has started. Runtime actions must not start peer sessions while logout/delete is tearing down presence, sessions, and local auth state.
- `AuthenticatedSession.sessionGeneration` is the account-scope boundary. Runtime reuse, protocol brain creation, request/call/connection state, messages, file transfers, user search, and recent searches must match the active generation or reset to empty/idle state.
- Device-global settings such as theme, media device preferences, audio settings, and update settings stay outside the session scope.
- Runtime startup depends on a validated local identity candidate plus active authenticated session generation.
- Account deletion is a first-class destructive lifecycle path. It reauthenticates with the user's password before destructive backend work, tombstones the backend user row instead of hard-deleting it, removes search and account-owned mirror data where client rules allow on a best-effort basis, deletes Firebase Auth last, and only then shuts down runtime sessions best-effort and clears local Drift/authenticated-session state. If the required tombstone fails, Rain keeps the current session instead of behaving like logout.
- The RTDB `users/{username}` write rule binds ownership to Firebase Auth email plus uid. Existing rows with a `uid` keep immutable uid ownership. Legacy rows that are missing `uid` can be tombstoned only by the authenticated user whose email is `$username@rain.local` and whose new tombstone uid is the current auth uid.
- Login requires the backend identity row to still exist and belong to the current Firebase uid after Firebase Auth succeeds. Missing, tombstoned, empty-uid, or wrong-owner backend identity signs out and does not recreate local or backend identity.

## Current Investigation Findings

Related root-cause documents:

- [AUTHENTICATION_AUDIT.md](../../AUTHENTICATION_AUDIT.md)
- [ACCOUNT_LIFECYCLE_ANALYSIS.md](../../ACCOUNT_LIFECYCLE_ANALYSIS.md)
- [STATE_MANAGEMENT_FAILURE_ANALYSIS.md](../../STATE_MANAGEMENT_FAILURE_ANALYSIS.md)
- [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md)

Critical finding: authentication currently has multiple sources of truth. Local Drift identity, Firebase Auth, RTDB user profile, presence, runtime controller state, and router state can disagree. If RTDB account data is deleted externally but local identity and cached Firebase Auth remain, runtime startup can recreate backend profile/presence from the local identity.

Target architecture: an `AuthSessionCoordinator` must own session discovery, Firebase/backend validation, logout, local reset, account deletion, and provider-scope disposal. Local identity should be treated as a session candidate, not authenticated truth.

## Implementation Progress

- 2026-06-03 Phase 1: Cached identity restoration now performs backend validation before publishing signed-in state. Deleted backend accounts and Firebase/backend uid mismatches clear local session data and sign out best-effort. Backend profile data wins over stale local display/gender/created-at cache. Tests cover deleted backend account, uid mismatch, and backend profile refresh.
- 2026-06-03 Phase 2: Deterministic logout/reset now clears local session before best-effort backend sign-out. Tests cover `adapter.signOut()` failure and logout arriving after app-exit shutdown has already started.
- 2026-06-03 Phase 3: `AppStartupState` centralizes update/session/runtime readiness and route refresh behavior.
- 2026-06-03 Phase 4: `RainApp` renders `RainStartupSurface` globally above routed content while startup is loading, update-blocked, failed, or session-expired, preventing normal navigation shell insertion during those phases.
- 2026-06-03 Phase 5: protected route readiness now uses `AppStartupState.canRenderProtectedRoutes`, route-local guards for settings/search/friend pages, and redirect-to-root behavior for unresolved protected paths. Signed-out auth renders outside the app shell through a standalone Navigator/Overlay.
- 2026-06-03 Phase 6: state lifecycle hardening now scopes account-owned providers by `AuthenticatedSession.sessionGeneration`; runtime reuse requires matching username and generation; logout ends the session instead of depending on a broad manual invalidation list. Tests cover generation changes, recent/search reset, signed-out message streams, startup routes, and full Melos validation.
- 2026-06-04 registration conflict hardening: live Firebase evidence showed fresh random registration succeeds, while `users/eslam` already exists. The app now maps RTDB permission-denied during registration to an account conflict message, rolls back Auth only when the primary username row was not created, signs out on secondary backend-save failures, and keeps Drift identity uncached until backend identity/presence writes succeed. Regression tests cover backend-save failure cleanup and onboarding error copy.
- 2026-06-04 account deletion workflow: settings exposes delete account behind confirmation plus password prompt; `SignalingAdapter` now includes `reauthenticate` and `deleteAccount`; `FirebaseSignalingAdapter` reauthenticates, cleans/tombstones RTDB account data while ownership still exists, deletes Firebase Auth last, and filters tombstoned identities from restoration; runtime/provider code clears local session only after the destructive path starts and preserves the session on bad-password reauth. Follow-up hardening rejects login when backend identity is missing after Auth succeeds, rejects upsert to tombstoned users, and blocks `userSearch` writes for deleted users. Targeted runtime/settings/auth/protocol tests and full Melos analyze/test passed.
- 2026-06-06 pending teardown hardening: logout now clears local session first and renders signed-out while cleanup continues best-effort; destructive account deletion now reauthenticates, calls backend/Auth deletion even when runtime cleanup is blocked, then clears local session; bad-password account deletion restores the active runtime/session; `AppStartupState` no longer treats a null runtime or loading runtime with previous value as ready; connect actions are rejected after runtime shutdown starts. Regression tests cover logout cleanup blocked without startup-loading hang, destructive deletion calling backend delete while runtime cleanup is blocked, bad-password restoration, shutdown connect rejection, and protected route startup behavior.
- 2026-06-07 delete-account failure hardening: account deletion no longer starts runtime shutdown before backend/Auth deletion. Required tombstone failure keeps the signed-in session and reports the error instead of degrading into logout. A second hardening pass separates the required tombstone from optional RTDB mirror cleanup because multi-location update denial on one optional child can reject the whole write. A third provider hardening pass keeps `RuntimeController.deleteAccount` from publishing global runtime loading during password/tombstone preflight, so wrong-password and required-tombstone errors keep Settings mounted long enough to show the modal error. Settings now shows a modal delete error instead of a transient snackbar. The live follow-up hardened `users/{username}` rules for legacy rows missing `uid`, deployed the updated RTDB rules to `rain-8fb4b-default-rtdb`, and read back the deployed rule containing the email-bound missing-uid branch. Local regression tests cover provider/direct-runtime tombstone failure preserving session/local identity, Settings error visibility, Settings staying mounted while password verification is pending, the Firebase adapter source contract, and the Firebase emulator account-deletion path.
- Remaining: user Android retry proof for the reported account, hard-release-gate integration for auth/startup/account-deletion regressions when publishing, and a fuller `AuthSessionCoordinator` extraction if the provider-based session coordinator becomes insufficient.

## Account Deletion Architecture Plan

2026-06-04 Phase 3 review targeted first-class account deletion. Phase 4 implementation completed the local app/runtime/adapter/rules path and local validation.

Required ownership:

- `apps/rain` owns confirmation UI, destructive-flow state, provider/session teardown, and user-facing partial-failure messages.
- `packages/protocol_brain` owns the account deletion signaling contract and Firebase adapter implementation because account cleanup touches Auth and RTDB identity/signaling data.
- `packages/rain_core` owns local session clearing only; no schema migration is currently required.
- `backend/firebase` owns any rules changes needed to delete or tombstone account-owned RTDB data safely.

Sequencing constraints:

- Reauthenticate before the destructive path if Firebase Auth requires recent sign-in.
- Remove `userSearch/{username}` best-effort before tombstone because rules block re-adding/search writes for deleted accounts.
- Write the required `users/{username}` tombstone while the Firebase Auth user still exists. The tombstone keeps `uid`, so optional mirror cleanup can still use ownership rules after the irreversible backend marker is written.
- For legacy backend account rows missing `uid`, the rule permits the tombstone only when Firebase Auth email matches `$username@rain.local` and the tombstone writes the current auth uid. Rows with an existing `uid` cannot be retargeted to another Firebase user.
- Delete the Firebase Auth user last.
- Clear local session and end the authenticated session generation only after backend/Auth deletion succeeds or after the backend tombstone has made the account unrecoverable by normal app login. Required tombstone failure must preserve the session; optional cleanup after tombstone must not block deletion. Password reauthentication and required backend tombstone writes are preflight work for UI readiness purposes and must not publish global runtime loading that unmounts Settings.
- Keep WebRTC cleanup as runtime shutdown/disconnect behavior; account deletion must not move peer/media ownership into auth code.

Implementation notes:

- Reauthentication failures before destructive work do not clear local identity.
- Required tombstone failures keep local identity and authenticated-session generation so the user can retry or export diagnostics.
- `users/{username}` is tombstoned with `accountState: deleted` and `deletedAt`, not removed, so the username stays locked and stale cached identity cannot restore the account.
- If a deployed live rule still denies the required tombstone, read back `/.settings/rules` before changing app code. Account deletion depends on live RTDB rules, not only checked-in rules.
- A remaining Firebase Auth user cannot use normal login to recreate the backend row after tombstoning; login now requires backend identity proof before local/backend save.
- Account deletion has emulator tombstone/no-recreate proof in the hard gate; run fresh emulator or Android smoke proof when changing the production Firebase adapter cleanup split.

## Dependencies

- Firebase Auth
- RTDB `users`
- Drift `identity_table`

## Edge Cases

- Keyboard must not hide login fields on Android.
- Username normalization must be consistent.
- Demo/prod Firebase config must not be mixed.
- Local identity can survive backend account data deletion.
- Firebase Auth can survive RTDB user profile deletion.
- Logout must clear local session even when backend sign-out or presence cleanup fails.
- Logout after app-exit or lifecycle shutdown must still clear local session, even when an earlier `_shutdownFuture` already exists.
- Logout must end protected-session authority after local session clear even if runtime/Firebase cleanup is still pending. Destructive account deletion must not behave like plain logout: after password reauth it must execute backend/Auth deletion before clearing local session, required tombstone failure must leave the signed-in session intact with a visible error, optional cleanup must not make delete look like a no-op, and wrong-password/pre-tombstone failures must not switch the app to global startup loading. A splash/loading state inside Settings with bottom navigation still visible, a global loading screen that never reaches signed-out, or delete account merely logging out is a failure.
- New peer connect/call/file actions must not start after runtime shutdown begins.
- Protected routes must not render while auth/session validation is loading.
- Global startup loading/update/error/session-expired surfaces are owned by `RainApp`, not only by `/`.
- Account-scoped providers must reset on session end, same-user relogin, and user switch.
- Smoke autoprovision must never be enabled in production/stable builds.
- Existing or locked RTDB username records can surface as Firebase permission-denied during registration. The UI must show a clear username/account conflict and must not leave a locally cached identity.
- Registration rollback must not delete Auth after the durable `users/{username}` row exists, because client rules do not allow deleting that row and deleting Auth would create a harder orphan.

## Testing Requirements

- Sign in.
- Register.
- Invalid credentials.
- Android keyboard layout.
- Logout clears local identity even if Firebase sign-out throws.
- Logout clears local identity if app-exit shutdown started first.
- Pending logout leaves the protected app shell and reaches signed-out before best-effort runtime/Firebase cleanup completes. Destructive account deletion leaves the shell only after backend/Auth deletion succeeds or reaches the post-tombstone failure path; wrong-password and required tombstone failure keep the shell/session active with a visible error and without publishing global startup loading during preflight.
- Startup with local identity but missing backend user routes to signed-out flow and does not recreate backend data.
- Startup with invalid/deleted Firebase user clears local session before protected UI renders.
- Cached local identity with mismatched Firebase/backend uid clears local session before restoration.
- Stale local profile fields are refreshed from backend identity during restoration.
- Settings/search/friend routes do not render protected content while auth/session is loading.
- Account deletion requires password reauthentication, does not clear local session on bad password or required tombstone failure, does not unmount Settings during bad-password/pre-tombstone preflight, clears local session after successful or post-tombstone backend/Auth deletion, runs optional RTDB cleanup best-effort, and does not restore a tombstoned backend identity.
- Live RTDB rules for account deletion must be deployed and read back after changing `users/{username}` ownership logic; emulator proof alone is not enough for a user-reported production-like denial.
- Login after backend account deletion must fail without calling `upsertIdentity`, `addToUserSearch`, `setPresence`, or local identity save.
- Registration backend-write failure signs out and leaves Drift identity empty.
- Onboarding registration permission denial shows a friendly conflict message and hides raw Firebase error text.

Related: [[Permissions Matrix]], [[Database Schema]].
