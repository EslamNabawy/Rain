create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table if not exists public.users (
  username text primary key check (username ~ '^[a-z0-9_]{3,20}$'),
  uid text not null unique check (uid <> ''),
  display_name text not null default '',
  gender text check (gender in ('male', 'female')),
  registered_at bigint not null default 0,
  last_seen bigint not null default 0,
  last_heartbeat bigint not null default 0,
  online boolean not null default false,
  updated_at timestamptz not null default timezone('utc', now())
);

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
   set user_a = split_part(room_id, ':', 1),
       user_b = split_part(room_id, ':', 2)
 where (user_a is null or user_b is null)
   and position(':' in room_id) > 0;

create table if not exists public.friend_requests (
  from_user text not null references public.users (username) on delete cascade,
  to_user text not null references public.users (username) on delete cascade,
  sent_at bigint not null,
  primary key (from_user, to_user),
  constraint friend_requests_not_self check (from_user <> to_user)
);

drop trigger if exists users_set_updated_at on public.users;
create trigger users_set_updated_at
before update on public.users
for each row
execute function public.set_updated_at();

alter table public.users enable row level security;
alter table public.rooms enable row level security;
alter table public.friend_requests enable row level security;

alter table public.users replica identity full;
alter table public.rooms replica identity full;
alter table public.friend_requests replica identity full;

drop policy if exists "users_select_authenticated" on public.users;
create policy "users_select_authenticated"
on public.users
for select
to authenticated
using (true);

drop policy if exists "users_insert_own_identity" on public.users;
create policy "users_insert_own_identity"
on public.users
for insert
to authenticated
with check (uid = auth.uid()::text);

drop policy if exists "users_update_own_identity" on public.users;
create policy "users_update_own_identity"
on public.users
for update
to authenticated
using (uid = auth.uid()::text)
with check (uid = auth.uid()::text);

drop policy if exists "users_delete_own_identity" on public.users;
create policy "users_delete_own_identity"
on public.users
for delete
to authenticated
using (uid = auth.uid()::text);

drop policy if exists "rooms_select_authenticated" on public.rooms;
create policy "rooms_select_authenticated"
on public.rooms
for select
to authenticated
using (
  exists (
    select 1
    from public.users participant
    where participant.uid = auth.uid()::text
      and participant.username in (rooms.user_a, rooms.user_b)
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
    where participant.uid = auth.uid()::text
      and participant.username in (rooms.user_a, rooms.user_b)
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
    where participant.uid = auth.uid()::text
      and participant.username in (rooms.user_a, rooms.user_b)
  )
)
with check (
  exists (
    select 1
    from public.users participant
    where participant.uid = auth.uid()::text
      and participant.username in (rooms.user_a, rooms.user_b)
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
    where participant.uid = auth.uid()::text
      and participant.username in (rooms.user_a, rooms.user_b)
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
      and sender.uid = auth.uid()::text
  )
  or exists (
    select 1
    from public.users recipient
    where recipient.username = friend_requests.to_user
      and recipient.uid = auth.uid()::text
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
      and sender.uid = auth.uid()::text
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
      and sender.uid = auth.uid()::text
  )
  or exists (
    select 1
    from public.users recipient
    where recipient.username = friend_requests.to_user
      and recipient.uid = auth.uid()::text
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
