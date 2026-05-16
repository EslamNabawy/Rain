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

Do not use ad hoc SQL snippets that create public insert, update, or all-access
policies. Rain's security boundary depends on the RLS policies in
`schema.sql`, and emergency fixes must preserve those ownership checks.

The schema creates:

- `public.users`
- `public.app_config`
- `public.rooms`
- `public.friend_requests`
- `public.friendships`
- a public read-only app config row used by the force-update gate
- row-level security policies that keep `users.uid` as the ownership source of truth
- room constraints that keep `room_id`, `user_a`, and `user_b` aligned
- indexes for username search, room participant lookups, stale presence cleanup, and friend-request inbox reads
- optional user profile metadata such as gender, kept on the `users` row
- a `cleanup_backend_state()` RPC used by the scheduled Edge Function

After the schema is applied, run [verify.sql](verify.sql) in the SQL editor to confirm the expected tables, indexes, policies, publication entries, and cleanup RPC are present.

For a live deployment walkthrough with exact commands and expected results, use [DEPLOYMENT_RUNBOOK.md](DEPLOYMENT_RUNBOOK.md).

Rain keeps the current username/password UX in the app. On Supabase, the adapter authenticates with a derived alias email in the form `<username>@auth.<your-project-host>`, so the Email provider must be enabled and email confirmation must stay off for these app-managed accounts. Supabase Auth currently rejects example/test domains for email signups, so the app derives the alias from the project host instead of using `example.com`.

## Configure The Update Gate

The app reads the minimum supported version from `public.app_config`. Seed or update the singleton row after applying the schema:

```sql
insert into public.app_config (id, min_required_version, update_url)
values (true, '1.0.0', 'https://github.com/EslamNabawy/Rain/releases')
on conflict (id) do update
set min_required_version = excluded.min_required_version,
    update_url = excluded.update_url;
```

Leave `min_required_version` empty if you do not want to force an upgrade yet. `update_url` is optional; when blank, the app falls back to `RAIN_UPDATE_URL`.

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
- runs with the service role so it can bypass RLS safely for maintenance

If you change the function or schema, rerun `verify.sql` so the database contract stays aligned with the app.

## Suggested Validation

1. Register two users and verify `public.users.uid` matches the authenticated Supabase `auth.uid()` for each account.
2. Send a friend request and verify it appears in `public.friend_requests`.
3. Accept the request and verify the pair appears in `public.friendships`.
4. Establish a connection and confirm `public.rooms` entries disappear after connect or the cleanup window.
5. Stop heartbeats and verify presence flips to offline after the next scheduled cleanup run.
