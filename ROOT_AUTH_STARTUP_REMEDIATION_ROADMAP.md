# Auth, Account, Startup, Splash, Navigation Remediation Roadmap

Date: 2026-06-03

This roadmap consolidates the required fixes from:

- [AUTHENTICATION_AUDIT.md](AUTHENTICATION_AUDIT.md)
- [ACCOUNT_LIFECYCLE_ANALYSIS.md](ACCOUNT_LIFECYCLE_ANALYSIS.md)
- [STARTUP_SEQUENCE_ANALYSIS.md](STARTUP_SEQUENCE_ANALYSIS.md)
- [SPLASH_SCREEN_INVESTIGATION.md](SPLASH_SCREEN_INVESTIGATION.md)
- [NAVIGATION_INITIALIZATION_AUDIT.md](NAVIGATION_INITIALIZATION_AUDIT.md)
- [STATE_MANAGEMENT_FAILURE_ANALYSIS.md](STATE_MANAGEMENT_FAILURE_ANALYSIS.md)

## Critical Architecture Defects

1. Local Drift identity is used as signed-in truth before Firebase/backend validation.
2. Runtime startup can recreate backend account records from stale local identity.
3. Logout clears local session after backend sign-out, so backend failure can preserve local identity.
4. Account deletion is not implemented as a first-class lifecycle.
5. Startup loading is split between global splash and route-local splash.
6. Router/shell initialize before authenticated session/runtime readiness.
7. Protected routes are siblings of `/` and can bypass `RootScreen` gates.
8. Account-scoped providers are manually invalidated rather than disposed by a session scope.

## Implementation Progress

- 2026-06-03 Phase 1 implementation complete: `IdentityController` now treats local Drift identity as a cached session candidate and validates it against backend account existence plus current auth uid ownership before restoring signed-in state. Missing/deleted backend account data, missing uid data, uid mismatch, and session-expired errors clear local session data. Register/login save local identity only after backend identity/presence writes. Tests cover deleted backend account, uid mismatch, and backend profile refresh.
- 2026-06-03 active overlay Phase 2 / roadmap Phase 03 implementation complete: runtime logout clears local Drift session data before best-effort backend sign-out, handles failed `adapter.signOut()` without preserving cached identity, clears local session even when a previous app-exit shutdown future exists, and invalidates session-scoped providers from a `finally` path. Tests cover failed sign-out and logout-after-app-exit shutdown.
- Remaining phases: explicit startup state machine, global splash gate, navigation readiness, and session lifecycle hardening.

## Dependency-Ordered Plan

### Phase 00: Evidence And Test Lock

Priority: P0

Tasks:

- Add failing tests for stale local identity after backend account deletion.
- Add failing tests for Firebase sign-out throwing during logout.
- Add failing tests for `/settings`, `/search`, and `/friend/:username` while identity/runtime is loading.
- Add failing tests that backend profile is not recreated until session validation passes.

Definition of done:

- Bugs are reproducible in automated tests.
- No production code changes before these tests exist.

### Phase 01: Auth Session Contract

Priority: P0
Depends on: Phase 00

Tasks:

- Define `AuthSessionState`.
- Define `AuthenticatedSession`.
- Define `AuthSessionCoordinator`.
- Define source-of-truth rules:
  - local identity is only a session candidate,
  - Firebase Auth proves backend credential,
  - RTDB identity proves account existence,
  - runtime starts only after authenticated session is valid.

Definition of done:

- Session states and transitions are documented and tested.

### Phase 02: Startup Gate

Priority: P0
Depends on: Phase 01

Tasks:

- Move global app readiness above protected router/shell.
- Render full-screen splash for bootstrap, session validation, and runtime initialization.
- Render force-update gate before auth/home.
- Render auth flow only when signed out.
- Render app shell only when session is authenticated and runtime is ready.

Definition of done:

- No shell, nav, settings, search, friend profile, or home content renders before ready.

### Phase 03: Deterministic Logout And Reset

Priority: P0
Depends on: Phase 01

Tasks:

- Change logout/reset ordering to guarantee local session clear.
- Make presence offline and Firebase sign-out best effort.
- Dispose runtime and session providers even if backend cleanup fails.
- Route to signed-out auth flow immediately after local clear.

Definition of done:

- Logout succeeds locally even with Firebase permission/sign-out failure.
- Reopening after logout never restores old identity.

Progress:

- 2026-06-03: Complete under the active execution overlay as Phase 2. Local session clearing runs before best-effort backend sign-out, failed sign-out is diagnostic-only after local clear, logout after existing app-exit shutdown still clears local session, and runtime provider invalidation runs in `finally`.

### Phase 04: Backend Account Validation

Priority: P0
Depends on: Phase 01

Tasks:

- Validate cached Firebase user for username.
- Validate backend `users/{username}` exists and belongs to Firebase uid.
- If backend account is missing, clear local session instead of recreating it.
- Move runtime `upsertIdentity` behind an explicit "validated session may update profile/presence" permission.

Definition of done:

- External backend deletion does not get undone by app startup.

Progress:

- 2026-06-03: Cached identity restoration path is guarded by backend account validation and current auth uid matching. Runtime startup profile/presence behavior still needs to be placed behind an explicit validated-session permission in a later startup/session phase.

### Phase 05: Account Deletion Workflow

Priority: P1
Depends on: Phases 01, 03, 04

Tasks:

- Add account deletion contract.
- Add adapter/backend methods for account-owned RTDB cleanup or tombstoning.
- Handle Firebase Auth re-authentication requirement.
- Clear local session in all outcomes.
- Message partial backend deletion failures.

Definition of done:

- User can delete account from the app and cannot reopen into the deleted identity.

### Phase 06: Session-Scoped Providers

Priority: P1
Depends on: Phases 01, 03

Tasks:

- Key account-scoped providers by `AuthenticatedSession.sessionGeneration`.
- Remove manual invalidation list as the primary cleanup mechanism.
- Keep device-global providers outside the session scope.
- Move account-scoped settings into session cleanup/migration.

Definition of done:

- User A state cannot leak into user B after logout/login.

### Phase 07: Router Refactor

Priority: P1
Depends on: Phase 02

Tasks:

- Split route trees into startup, auth, and protected app routes.
- Make router refresh listen to app readiness, not only identity.
- Remove protected route rendering while readiness is not `ready`.

Definition of done:

- Deep links/protected routes during loading route to splash/auth gate correctly.

### Phase 08: UI Cleanup

Priority: P2
Depends on: Phases 02, 07

Tasks:

- Remove route-local splash usage for app startup.
- Update settings/search/friend profile to require authenticated session.
- Remove `Unknown` protected profile fallback caused by auth loading.

Definition of done:

- Loading/error/signed-out states are visually distinct and professional.

### Phase 09: Release Gate

Priority: P0
Depends on: Phases 00-08

Tasks:

- Add tests to Melos/hard release gate.
- Update Obsidian architecture and memory notes.
- Add diagnostics for session validation and logout/reset.

Definition of done:

- Release fails if logout, account deletion, startup gate, splash, or protected navigation regress.
