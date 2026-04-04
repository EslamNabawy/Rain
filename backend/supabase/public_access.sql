-- Allow public read access to users for online status
-- Run in Supabase Dashboard > SQL Editor

-- Drop restrictive policies and create permissive ones
drop policy if exists "Allow anonymous insert on users" on public.users;
drop policy if exists "Allow authenticated update on users" on public.users;
drop policy if exists "Allow authenticated read on users" on public.users;

-- Allow anyone to read users (for presence/online status)
create policy "Public read users" on public.users
  for select using (true);

-- Allow anyone to insert/update their own user record
create policy "Public insert users" on public.users
  for insert with check (true);

create policy "Public update users" on public.users
  for update using (true);

-- Allow public rooms access for signaling
drop policy if exists "Allow public rooms" on public.rooms;
create policy "Public rooms" on public.rooms
  for all using (true);