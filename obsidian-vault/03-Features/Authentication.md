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

## Dependencies

- Firebase Auth
- RTDB `users`
- Drift `identity_table`

## Edge Cases

- Keyboard must not hide login fields on Android.
- Username normalization must be consistent.
- Demo/prod Firebase config must not be mixed.

## Testing Requirements

- Sign in.
- Register.
- Invalid credentials.
- Android keyboard layout.

Related: [[Permissions Matrix]], [[Database Schema]].
