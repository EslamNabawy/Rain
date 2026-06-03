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
- Logout clears local Drift session data before best-effort backend sign-out, so Firebase permission/sign-out failures cannot keep the old cached identity alive.
- Runtime-provider logout invalidates session-scoped providers from a `finally` path even when cleanup reports a non-local backend failure.
- Runtime startup still depends on a validated local identity candidate and remains part of later startup/session hardening phases.

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
- Remaining: explicit `AuthSessionCoordinator`, global startup readiness, protected-route gating, account deletion workflow, and session-scoped provider disposal.

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
- Smoke autoprovision must never be enabled in production/stable builds.

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

Related: [[Permissions Matrix]], [[Database Schema]].
