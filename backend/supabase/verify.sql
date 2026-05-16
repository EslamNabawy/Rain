select
  'users' as object_name,
  to_regclass('public.users') is not null as exists;

select
  'app_config' as object_name,
  to_regclass('public.app_config') is not null as exists;

select
  'rooms' as object_name,
  to_regclass('public.rooms') is not null as exists;

select
  'friend_requests' as object_name,
  to_regclass('public.friend_requests') is not null as exists;

select
  'friendships' as object_name,
  to_regclass('public.friendships') is not null as exists;

select
  'cleanup_backend_state' as object_name,
  exists (
    select 1
    from pg_proc
    where proname = 'cleanup_backend_state'
      and pronamespace = 'public'::regnamespace
  ) as exists;

select
  'accept_friend_request' as object_name,
  exists (
    select 1
    from pg_proc
    where proname = 'accept_friend_request'
      and pronamespace = 'public'::regnamespace
  ) as exists;

select
  'append_room_ice' as object_name,
  exists (
    select 1
    from pg_proc
    where proname = 'append_room_ice'
      and pronamespace = 'public'::regnamespace
  ) as exists;

select
  indexname
from pg_indexes
where schemaname = 'public'
  and tablename in ('users', 'rooms', 'friend_requests', 'friendships')
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
  and tablename in ('users', 'app_config', 'rooms', 'friend_requests', 'friendships')
order by tablename, policyname;

select
  pubname,
  schemaname,
  tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
  and tablename in ('users', 'rooms', 'friend_requests', 'friendships')
order by tablename;
