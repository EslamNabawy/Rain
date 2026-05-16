create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create or replace function public.canonical_room_id(user_one text, user_two text)
returns text
language sql
immutable
strict
as $$
  select least(user_one, user_two) || ':' || greatest(user_one, user_two);
$$;

create or replace function public.guard_immutable_user_identity_fields()
returns trigger
language plpgsql
as $$
begin
  if old.username is distinct from new.username then
    raise exception 'username is immutable';
  end if;

  if old.uid is distinct from new.uid then
    raise exception 'uid is immutable';
  end if;

  if old.registered_at is distinct from new.registered_at then
    raise exception 'registered_at is immutable';
  end if;

  return new;
end;
$$;

create extension if not exists pg_trgm;

create table if not exists public.users (
  username text primary key check (username ~ '^[a-z0-9_]{3,24}$'),
  uid text not null unique check (uid <> ''),
  display_name text not null default '',
  gender text check (gender in ('male', 'female')),
  registered_at bigint not null default 0,
  last_seen bigint not null default 0,
  last_heartbeat bigint not null default 0,
  online boolean not null default false,
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.app_config (
  id boolean primary key default true check (id = true),
  min_required_version text not null default '',
  update_url text not null default '',
  updated_at timestamptz not null default timezone('utc', now())
);

insert into public.app_config (id)
values (true)
on conflict (id) do nothing;

alter table public.users
  add column if not exists gender text;

do $$
begin
  alter table public.users
    add constraint users_gender_check
    check (gender is null or gender in ('male', 'female'));
exception
  when duplicate_object then null;
end
$$;

create table if not exists public.rooms (
  room_id text primary key,
  user_a text references public.users (username) on delete cascade,
  user_b text references public.users (username) on delete cascade,
  offer jsonb,
  answer jsonb,
  caller_ice jsonb not null default '[]'::jsonb,
  callee_ice jsonb not null default '[]'::jsonb,
  created_at bigint not null default 0
);

alter table public.rooms
  add column if not exists user_a text references public.users (username) on delete cascade;

alter table public.rooms
  add column if not exists user_b text references public.users (username) on delete cascade;

update public.rooms
   set user_a = least(split_part(room_id, ':', 1), split_part(room_id, ':', 2)),
       user_b = greatest(split_part(room_id, ':', 1), split_part(room_id, ':', 2))
 where (user_a is null or user_b is null)
   and position(':' in room_id) > 0;

do $$
begin
  alter table public.rooms
    add constraint rooms_user_a_not_null
    check (user_a is not null);
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  alter table public.rooms
    add constraint rooms_user_b_not_null
    check (user_b is not null);
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  alter table public.rooms
    add constraint rooms_distinct_users_check
    check (user_a <> user_b);
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  alter table public.rooms
    add constraint rooms_participant_order_check
    check (
      user_a = least(user_a, user_b)
      and user_b = greatest(user_a, user_b)
    );
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  alter table public.rooms
    add constraint rooms_canonical_room_id_check
    check (room_id = public.canonical_room_id(user_a, user_b));
exception
  when duplicate_object then null;
end
$$;

create table if not exists public.friend_requests (
  from_user text not null references public.users (username) on delete cascade,
  to_user text not null references public.users (username) on delete cascade,
  sent_at bigint not null,
  primary key (from_user, to_user),
  constraint friend_requests_not_self check (from_user <> to_user)
);

create table if not exists public.friendships (
  user_a text not null references public.users (username) on delete cascade,
  user_b text not null references public.users (username) on delete cascade,
  accepted_at bigint not null,
  primary key (user_a, user_b),
  constraint friendships_distinct_users check (user_a <> user_b),
  constraint friendships_participant_order_check check (
    user_a = least(user_a, user_b)
    and user_b = greatest(user_a, user_b)
  )
);

create or replace function public.accept_friend_request(request_from text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_username text;
  normalized_request_from text := lower(trim(request_from));
  first_user text;
  second_user text;
begin
  select username
    into current_username
    from public.users
   where uid = (select auth.uid())::text
   limit 1;

  if current_username is null then
    raise exception 'authenticated user has no Rain identity';
  end if;

  if normalized_request_from = current_username then
    raise exception 'cannot accept self request';
  end if;

  if not exists (
    select 1
      from public.friend_requests
     where from_user = normalized_request_from
       and to_user = current_username
  ) then
    raise exception 'friend request does not exist';
  end if;

  first_user := least(normalized_request_from, current_username);
  second_user := greatest(normalized_request_from, current_username);

  insert into public.friendships (user_a, user_b, accepted_at)
  values (
    first_user,
    second_user,
    floor(extract(epoch from clock_timestamp()) * 1000)
  )
  on conflict (user_a, user_b) do update
    set accepted_at = excluded.accepted_at;

  delete from public.friend_requests
   where (from_user = normalized_request_from and to_user = current_username)
      or (from_user = current_username and to_user = normalized_request_from);
end;
$$;

revoke all on function public.accept_friend_request(text) from public;
grant execute on function public.accept_friend_request(text) to authenticated;

create or replace function public.append_room_ice(
  target_room_id text,
  target_role text,
  target_candidate jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_count integer;
begin
  if target_role not in ('caller', 'callee') then
    raise exception 'invalid ICE role';
  end if;

  if target_candidate is null then
    raise exception 'ICE candidate is required';
  end if;

  update public.rooms as target_room
     set caller_ice = case
           when target_role = 'caller'
             then coalesce(target_room.caller_ice, '[]'::jsonb)
               || jsonb_build_array(target_candidate)
           else target_room.caller_ice
         end,
         callee_ice = case
           when target_role = 'callee'
             then coalesce(target_room.callee_ice, '[]'::jsonb)
               || jsonb_build_array(target_candidate)
           else target_room.callee_ice
         end,
         created_at = floor(extract(epoch from clock_timestamp()) * 1000)
   where target_room.room_id = target_room_id
     and exists (
       select 1
         from public.users participant
        where participant.uid = (select auth.uid())::text
          and participant.username in (target_room.user_a, target_room.user_b)
     )
     and exists (
       select 1
         from public.friendships existing_friendship
        where existing_friendship.user_a = target_room.user_a
          and existing_friendship.user_b = target_room.user_b
     );

  get diagnostics updated_count = row_count;
  if updated_count = 0 then
    raise exception 'room not found or not authorized';
  end if;
end;
$$;

revoke all on function public.append_room_ice(text, text, jsonb) from public;
grant execute on function public.append_room_ice(text, text, jsonb) to authenticated;

create index if not exists users_username_trgm_idx
  on public.users
  using gin (username gin_trgm_ops);

create index if not exists users_online_last_heartbeat_idx
  on public.users (last_heartbeat)
  where online = true;

create index if not exists rooms_user_a_idx
  on public.rooms (user_a);

create index if not exists rooms_user_b_idx
  on public.rooms (user_b);

create index if not exists rooms_created_at_idx
  on public.rooms (created_at);

create index if not exists friend_requests_to_user_idx
  on public.friend_requests (to_user);

create index if not exists friendships_user_a_idx
  on public.friendships (user_a);

create index if not exists friendships_user_b_idx
  on public.friendships (user_b);

drop trigger if exists users_set_updated_at on public.users;
create trigger users_set_updated_at
before update on public.users
for each row
execute function public.set_updated_at();

drop trigger if exists users_guard_immutable_identity on public.users;
create trigger users_guard_immutable_identity
before update on public.users
for each row
execute function public.guard_immutable_user_identity_fields();

drop trigger if exists app_config_set_updated_at on public.app_config;
create trigger app_config_set_updated_at
before update on public.app_config
for each row
execute function public.set_updated_at();

alter table public.users enable row level security;
alter table public.app_config enable row level security;
alter table public.rooms enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;

alter table public.users replica identity full;
alter table public.app_config replica identity full;
alter table public.rooms replica identity full;
alter table public.friend_requests replica identity full;
alter table public.friendships replica identity full;

drop policy if exists "users_select_authenticated" on public.users;
create policy "users_select_authenticated"
on public.users
for select
to authenticated
using (true);

drop policy if exists "app_config_select_public" on public.app_config;
create policy "app_config_select_public"
on public.app_config
for select
to anon, authenticated
using (true);

drop policy if exists "users_insert_own_identity" on public.users;
create policy "users_insert_own_identity"
on public.users
for insert
to authenticated
with check (uid = (select auth.uid())::text);

drop policy if exists "users_update_own_identity" on public.users;
create policy "users_update_own_identity"
on public.users
for update
to authenticated
using (uid = (select auth.uid())::text)
with check (uid = (select auth.uid())::text);

drop policy if exists "users_delete_own_identity" on public.users;
create policy "users_delete_own_identity"
on public.users
for delete
to authenticated
using (uid = (select auth.uid())::text);

drop policy if exists "rooms_select_authenticated" on public.rooms;
create policy "rooms_select_authenticated"
on public.rooms
for select
to authenticated
using (
  exists (
    select 1
    from public.users participant
    where participant.uid = (select auth.uid())::text
      and participant.username in (rooms.user_a, rooms.user_b)
  )
  and exists (
    select 1
    from public.friendships existing_friendship
    where existing_friendship.user_a = rooms.user_a
      and existing_friendship.user_b = rooms.user_b
  )
);

drop policy if exists "rooms_insert_authenticated" on public.rooms;
create policy "rooms_insert_authenticated"
on public.rooms
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users participant
    where participant.uid = (select auth.uid())::text
      and participant.username in (rooms.user_a, rooms.user_b)
  )
  and exists (
    select 1
    from public.friendships existing_friendship
    where existing_friendship.user_a = rooms.user_a
      and existing_friendship.user_b = rooms.user_b
  )
);

drop policy if exists "rooms_update_authenticated" on public.rooms;
create policy "rooms_update_authenticated"
on public.rooms
for update
to authenticated
using (
  exists (
    select 1
    from public.users participant
    where participant.uid = (select auth.uid())::text
      and participant.username in (rooms.user_a, rooms.user_b)
  )
  and exists (
    select 1
    from public.friendships existing_friendship
    where existing_friendship.user_a = rooms.user_a
      and existing_friendship.user_b = rooms.user_b
  )
)
with check (
  exists (
    select 1
    from public.users participant
    where participant.uid = (select auth.uid())::text
      and participant.username in (rooms.user_a, rooms.user_b)
  )
  and exists (
    select 1
    from public.friendships existing_friendship
    where existing_friendship.user_a = rooms.user_a
      and existing_friendship.user_b = rooms.user_b
  )
);

drop policy if exists "rooms_delete_authenticated" on public.rooms;
create policy "rooms_delete_authenticated"
on public.rooms
for delete
to authenticated
using (
  exists (
    select 1
    from public.users participant
    where participant.uid = (select auth.uid())::text
      and participant.username in (rooms.user_a, rooms.user_b)
  )
  and exists (
    select 1
    from public.friendships existing_friendship
    where existing_friendship.user_a = rooms.user_a
      and existing_friendship.user_b = rooms.user_b
  )
);

drop policy if exists "friend_requests_select_sender_or_recipient" on public.friend_requests;
create policy "friend_requests_select_sender_or_recipient"
on public.friend_requests
for select
to authenticated
using (
  exists (
    select 1
    from public.users sender
    where sender.username = friend_requests.from_user
      and sender.uid = (select auth.uid())::text
  )
  or exists (
    select 1
    from public.users recipient
    where recipient.username = friend_requests.to_user
      and recipient.uid = (select auth.uid())::text
  )
);

drop policy if exists "friend_requests_insert_sender" on public.friend_requests;
create policy "friend_requests_insert_sender"
on public.friend_requests
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users sender
    where sender.username = friend_requests.from_user
      and sender.uid = (select auth.uid())::text
  )
);

drop policy if exists "friend_requests_update_sender" on public.friend_requests;
create policy "friend_requests_update_sender"
on public.friend_requests
for update
to authenticated
using (
  exists (
    select 1
    from public.users sender
    where sender.username = friend_requests.from_user
      and sender.uid = (select auth.uid())::text
  )
)
with check (
  exists (
    select 1
    from public.users sender
    where sender.username = friend_requests.from_user
      and sender.uid = (select auth.uid())::text
  )
);

drop policy if exists "friend_requests_delete_sender_or_recipient" on public.friend_requests;
create policy "friend_requests_delete_sender_or_recipient"
on public.friend_requests
for delete
to authenticated
using (
  exists (
    select 1
    from public.users sender
    where sender.username = friend_requests.from_user
      and sender.uid = (select auth.uid())::text
  )
  or exists (
    select 1
    from public.users recipient
    where recipient.username = friend_requests.to_user
      and recipient.uid = (select auth.uid())::text
  )
);

drop policy if exists "friendships_select_participants" on public.friendships;
create policy "friendships_select_participants"
on public.friendships
for select
to authenticated
using (
  exists (
    select 1
    from public.users participant
    where participant.uid = (select auth.uid())::text
      and participant.username in (friendships.user_a, friendships.user_b)
  )
);

drop policy if exists "friendships_insert_participants" on public.friendships;
drop policy if exists "friendships_insert_via_existing_reciprocal_request" on public.friendships;
create policy "friendships_insert_via_existing_reciprocal_request"
on public.friendships
for insert
to authenticated
with check (
  exists (
    select 1
    from public.users participant
    where participant.uid = (select auth.uid())::text
      and participant.username in (friendships.user_a, friendships.user_b)
  )
  and exists (
    select 1
    from public.friend_requests incoming_request
    where incoming_request.from_user in (friendships.user_a, friendships.user_b)
      and incoming_request.to_user in (friendships.user_a, friendships.user_b)
      and incoming_request.from_user <> incoming_request.to_user
  )
);

drop policy if exists "friendships_update_participants" on public.friendships;
create policy "friendships_update_participants"
on public.friendships
for update
to authenticated
using (
  exists (
    select 1
    from public.users participant
    where participant.uid = (select auth.uid())::text
      and participant.username in (friendships.user_a, friendships.user_b)
  )
)
with check (
  exists (
    select 1
    from public.users participant
    where participant.uid = (select auth.uid())::text
      and participant.username in (friendships.user_a, friendships.user_b)
  )
);

drop policy if exists "friendships_delete_participants" on public.friendships;
create policy "friendships_delete_participants"
on public.friendships
for delete
to authenticated
using (
  exists (
    select 1
    from public.users participant
    where participant.uid = (select auth.uid())::text
      and participant.username in (friendships.user_a, friendships.user_b)
  )
);

do $$
begin
  alter publication supabase_realtime add table public.users;
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  alter publication supabase_realtime add table public.rooms;
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  alter publication supabase_realtime add table public.friend_requests;
exception
  when duplicate_object then null;
end
$$;

do $$
begin
  alter publication supabase_realtime add table public.friendships;
exception
  when duplicate_object then null;
end
$$;

create or replace function public.cleanup_backend_state()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  now_ms bigint := floor(extract(epoch from clock_timestamp()) * 1000);
  stale_presence_before bigint := now_ms - (7 * 60 * 1000);
  stale_room_before bigint := now_ms - (15 * 60 * 1000);
  offlined_users integer := 0;
  deleted_rooms integer := 0;
begin
  update public.users
     set online = false,
         last_seen = greatest(last_seen, now_ms)
   where online = true
     and last_heartbeat < stale_presence_before;
  get diagnostics offlined_users = row_count;

  delete from public.rooms
   where created_at < stale_room_before;
  get diagnostics deleted_rooms = row_count;

  return jsonb_build_object(
    'offlinedUsers', offlined_users,
    'deletedRooms', deleted_rooms,
    'stalePresenceBefore', stale_presence_before,
    'staleRoomBefore', stale_room_before
  );
end;
$$;

revoke all on function public.cleanup_backend_state() from public;
grant execute on function public.cleanup_backend_state() to service_role;
