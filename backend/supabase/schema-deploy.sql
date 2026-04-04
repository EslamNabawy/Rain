-- Simplified schema (tables already exist)
-- Just add any missing columns/policies

-- Addgender column if not exists
alter table public.users add column if not exists gender text;

-- Add gender check constraint
do $$
begin
  alter table public.users add constraint users_gender_check check (gender is null or gender in ('male', 'female'));
exception when duplicate_object then null;
end $$;

-- Ensure indexes exist
create index if not exists idx_users_online on public.users(online) where online = true;
create index if not exists idx_users_last_seen on public.users(last_seen);
create index if not exists idx_rooms_users on public.users(username);