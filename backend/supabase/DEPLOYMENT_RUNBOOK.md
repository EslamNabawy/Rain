# Supabase Deployment Runbook

This runbook is the exact live-deployment path for Rain's Supabase backend.

Project ref used in this repo:

- `omxgomfsdgfidzfydtjd`

## Prerequisites

Before you start, make sure:

- You can open the Supabase Dashboard for the project.
- The Supabase CLI is installed and logged in.
- You have the project database password and service-role key from the Dashboard.
- Your terminal has `psql` available if you want to run the SQL files directly.

## 1. Link The Project

```powershell
supabase link --project-ref omxgomfsdgfidzfydtjd
```

Expected result:

- The CLI reports that the project is linked.
- A local Supabase config is associated with the project ref.

## 2. Apply The Database Schema

Run the canonical schema file directly against the project database:

```powershell
$env:SUPABASE_DB_URL="postgresql://postgres:<password>@db.omxgomfsdgfidzfydtjd.supabase.co:5432/postgres?sslmode=require"
psql -v ON_ERROR_STOP=1 $env:SUPABASE_DB_URL -f backend/supabase/schema.sql
```

Expected result:

- `psql` finishes without SQL errors.
- `public.users`, `public.rooms`, and `public.friend_requests` exist.
- The RLS policies, indexes, and `cleanup_backend_state()` RPC are created or updated.

If you prefer the Dashboard, paste the contents of [schema.sql](schema.sql) into SQL Editor and run it there.

## 3. Verify The Database Contract

Run the verification SQL against the same database:

```powershell
psql -v ON_ERROR_STOP=1 $env:SUPABASE_DB_URL -f backend/supabase/verify.sql
```

Expected result:

- The first queries return `exists = true` for `public.users`, `public.rooms`, `public.friend_requests`, and `cleanup_backend_state()`.
- The index query lists the expected indexes.
- The policy query lists the RLS policies for the three public tables.
- The publication query shows all three tables in `supabase_realtime`.

If any of those checks fail, stop and fix the schema before deploying the function.

## 4. Set Edge Function Secrets

```powershell
supabase secrets set SUPABASE_URL=https://omxgomfsdgfidzfydtjd.supabase.co SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
```

Expected result:

- The CLI confirms the secrets were stored for the project.
- The values are available to the Edge Function as environment variables.

## 5. Deploy The Cleanup Function

```powershell
supabase functions deploy presence-cleanup --no-verify-jwt --project-ref omxgomfsdgfidzfydtjd
```

If Docker is unavailable, use the API bundler instead:

```powershell
supabase functions deploy presence-cleanup --no-verify-jwt --use-api --project-ref omxgomfsdgfidzfydtjd
```

Expected result:

- The CLI reports that `presence-cleanup` deployed successfully.
- The function is available at:

```text
https://omxgomfsdgfidzfydtjd.supabase.co/functions/v1/presence-cleanup
```

## 6. Smoke Test The Function

```powershell
curl -i -X POST https://omxgomfsdgfidzfydtjd.supabase.co/functions/v1/presence-cleanup -H "Content-Type: application/json" -d "{}"
```

Expected result:

- HTTP `200`.
- JSON response shaped like:

```json
{
  "ok": true,
  "result": {
    "offlinedUsers": 0,
    "deletedRooms": 0
  }
}
```

The counts may differ if the database already has stale rows.

## 7. Schedule The Cleanup Job

Enable the cron and HTTP helpers if the project does not already have them:

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;
create extension if not exists vault;
```

Store the project URL and publishable key in Vault:

```sql
select vault.create_secret('https://omxgomfsdgfidzfydtjd.supabase.co', 'project_url');
select vault.create_secret('<supabase-anon-key>', 'publishable_key');
```

Create the recurring job:

```sql
select
  cron.schedule(
    'rain-presence-cleanup',
    '*/3 * * * *',
    $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/presence-cleanup',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'publishable_key')
      ),
      body := '{}'::jsonb
    );
    $$
  ) as job_id;
```

Expected result:

- `cron.schedule` returns a job id.
- The job appears in the Cron dashboard.
- The next run should happen within 3 minutes.

## 8. Post-Deploy Smoke Test

After the job is scheduled:

1. Register two users in the app.
2. Send a friend request.
3. Create a peer connection and confirm the room is deleted after connect.
4. Stop heartbeats for one account.

Expected result:

- The cleanup job marks stale users offline after the heartbeat timeout.
- The room row is deleted after connect or after the cleanup window.
- Friend requests continue to round-trip through the database without RLS errors.
