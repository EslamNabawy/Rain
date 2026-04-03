select
  'users' as object_name,
  to_regclass('public.users') is not null as exists;

select
  'rooms' as object_name,
  to_regclass('public.rooms') is not null as exists;

select
  'friend_requests' as object_name,
  to_regclass('public.friend_requests') is not null as exists;

select
  'cleanup_backend_state' as object_name,
  exists (
    select 1
    from pg_proc
    where proname = 'cleanup_backend_state'
      and pronamespace = 'public'::regnamespace
  ) as exists;

select
  indexname
from pg_indexes
where schemaname = 'public'
  and tablename in ('users', 'rooms', 'friend_requests')
order by tablename, indexname;

select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd
from pg_policies
where schemaname = 'public'
  and tablename in ('users', 'rooms', 'friend_requests')
order by tablename, policyname;

select
  pubname,
  schemaname,
  tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
  and tablename in ('users', 'rooms', 'friend_requests')
order by tablename;
