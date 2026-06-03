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
- Current implementation uses Drift `identity_table` as the first signed-in UI signal, then validates Firebase Auth during runtime startup.
- Runtime startup can write RTDB `users/{username}` and `presence/{username}` from local identity after Firebase ownership validation.

## Current Investigation Findings

Related root-cause documents:

- [AUTHENTICATION_AUDIT.md](../../AUTHENTICATION_AUDIT.md)
- [ACCOUNT_LIFECYCLE_ANALYSIS.md](../../ACCOUNT_LIFECYCLE_ANALYSIS.md)
- [STATE_MANAGEMENT_FAILURE_ANALYSIS.md](../../STATE_MANAGEMENT_FAILURE_ANALYSIS.md)
- [ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md](../../ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md)

Critical finding: authentication currently has multiple sources of truth. Local Drift identity, Firebase Auth, RTDB user profile, presence, runtime controller state, and router state can disagree. If RTDB account data is deleted externally but local identity and cached Firebase Auth remain, runtime startup can recreate backend profile/presence from the local identity.

Target architecture: an `AuthSessionCoordinator` must own session discovery, Firebase/backend validation, logout, local reset, account deletion, and provider-scope disposal. Local identity should be treated as a session candidate, not authenticated truth.

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
- Protected routes must not render while auth/session validation is loading.
- Smoke autoprovision must never be enabled in production/stable builds.

## Testing Requirements

- Sign in.
- Register.
- Invalid credentials.
- Android keyboard layout.
- Logout clears local identity even if Firebase sign-out throws.
- Startup with local identity but missing backend user routes to signed-out flow and does not recreate backend data.
- Startup with invalid/deleted Firebase user clears local session before protected UI renders.
- Settings/search/friend routes do not render protected content while auth/session is loading.
- Account deletion is a first-class workflow once implemented.

Related: [[Permissions Matrix]], [[Database Schema]].
