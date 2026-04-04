-- Fix RLS policies for public read access
-- Run in Supabase Dashboard > SQL Editor

-- Users: allow public read
DROP POLICY IF EXISTS "Allow anonymous insert on users" ON public.users;
DROP POLICY IF EXISTS "Allow authenticated update on users" ON public.users;
DROP POLICY IF EXISTS "Allow authenticated read on users" ON public.users;

CREATE POLICY "users_public_read" ON public.users FOR SELECT USING (true);
CREATE POLICY "users_public_insert" ON public.users FOR INSERT WITH CHECK (true);
CREATE POLICY "users_public_update" ON public.users FOR UPDATE USING (true);

-- Rooms: allow public access
DROP POLICY IF EXISTS "Allow public rooms" ON public.rooms;

CREATE POLICY "rooms_public_all" ON public.rooms FOR ALL USING (true);

-- Friend requests: allow public insert
DROP POLICY IF EXISTS "friend_requests_public" ON public.friend_requests;

CREATE POLICY "friend_requests_public" ON public.friend_requests FOR ALL USING (true);