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
- `AuthenticatedSession.sessionGeneration` is the account-scope boundary. Runtime reuse, protocol brain creation, request/call/connection state, messages, file transfers, user search, and recent searches must match the active generation or reset to empty/idle state.
- Device-global settings such as theme, media device preferences, audio settings, and update settings stay outside the session scope.
- Runtime startup depends on a validated local identity candidate plus active authenticated session generation.

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
- Remaining: account deletion workflow and a fuller `AuthSessionCoordinator` extraction if the provider-based session coordinator becomes insufficient.

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
- Startup with local identity but missing backend user routes to signed-out flow and does not recreate backend data.
- Startup with invalid/deleted Firebase user clears local session before protected UI renders.
- Cached local identity with mismatched Firebase/backend uid clears local session before restoration.
- Stale local profile fields are refreshed from backend identity during restoration.
- Settings/search/friend routes do not render protected content while auth/session is loading.
- Account deletion is a first-class workflow once implemented.
- Registration backend-write failure signs out and leaves Drift identity empty.
- Onboarding registration permission denial shows a friendly conflict message and hides raw Firebase error text.

Related: [[Permissions Matrix]], [[Database Schema]].
