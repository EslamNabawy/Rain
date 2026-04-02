# Supabase Backend

This directory contains the schema and cleanup function needed by Rain's Supabase signaling adapter.

## Services To Enable

- Auth Email provider with email confirmations disabled
- Realtime for `users`, `rooms`, and `friend_requests`
- Edge Functions

## Apply The Schema

Apply [schema.sql](schema.sql) in the Supabase SQL editor or through the CLI:

```powershell
supabase db push
```

The schema creates:

- `public.users`
- `public.rooms`
- `public.friend_requests`
- row-level security policies that keep `users.uid` as the ownership source of truth
- optional user profile metadata such as gender, kept on the `users` row
- a `cleanup_backend_state()` RPC used by the scheduled Edge Function

Rain keeps the current username/password UX in the app. On Supabase, the adapter authenticates with a derived alias email in the form `<username>@rain.local`, so the Email provider must be enabled and email confirmation must stay off for these app-managed accounts.

## Deploy The Cleanup Function

Set the secrets first:

```powershell
supabase secrets set SUPABASE_URL=https://YOUR_PROJECT.supabase.co
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY
```

Deploy the function:

```powershell
supabase functions deploy presence-cleanup --no-verify-jwt
```

Schedule it every 3 minutes from the Supabase dashboard. The function calls `cleanup_backend_state()` which:

- marks users offline when `last_heartbeat` is older than 7 minutes
- deletes signaling rooms that have been untouched for 15 minutes

## Suggested Validation

1. Register two users and verify `public.users.uid` matches the authenticated Supabase `auth.uid()` for each account.
2. Send a friend request and verify it appears in `public.friend_requests`.
3. Establish a connection and confirm `public.rooms` entries disappear after connect or the cleanup window.
4. Stop heartbeats and verify presence flips to offline after the next scheduled cleanup run.
