import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Supabase contract stays aligned with the app validator', () {
    final workspaceRoot = Directory.current.parent.parent;
    final schemaFile = File.fromUri(
      workspaceRoot.uri.resolve('backend/supabase/schema.sql'),
    );
    final verifyFile = File.fromUri(
      workspaceRoot.uri.resolve('backend/supabase/verify.sql'),
    );
    final validatorFile = File.fromUri(
      workspaceRoot.uri.resolve('packages/rain_core/lib/src/input_validator.dart'),
    );

    final schema = schemaFile.readAsStringSync();
    final verify = verifyFile.readAsStringSync();
    final validator = validatorFile.readAsStringSync();

    expect(
      schema,
      contains(
        r"username text primary key check (username ~ '^[a-z0-9_]{3,24}$')",
      ),
      reason: 'Supabase must accept the same username length as the app.',
    );
    expect(
      validator,
      contains(r"RegExp(r'^[a-z0-9_]{3,24}$')"),
      reason: 'The app validator should stay in sync with the Supabase schema.',
    );
    expect(
      schema,
      contains('create policy "friend_requests_update_sender"'),
      reason: 'Friend request upserts need an update policy to pass RLS.',
    );
    expect(
      schema,
      contains('create extension if not exists pg_trgm;'),
      reason: 'Username substring search should use pg_trgm instead of seq scans.',
    );
    expect(
      schema,
      contains('create index if not exists rooms_user_a_idx'),
      reason: 'Room participant lookups should be indexed for RLS and cleanup.',
    );
    expect(
      schema,
      contains('create index if not exists rooms_user_b_idx'),
      reason: 'Room participant lookups should be indexed for RLS and cleanup.',
    );
    expect(
      schema,
      contains('create index if not exists rooms_created_at_idx'),
      reason: 'Cleanup should delete old rooms without a table scan.',
    );
    expect(
      schema,
      contains('create index if not exists friend_requests_to_user_idx'),
      reason: 'Friend request inbox queries should avoid sequential scans.',
    );
    expect(
      schema,
      contains('create index if not exists users_online_last_heartbeat_idx'),
      reason: 'Presence cleanup should use an index on the heartbeat timestamp.',
    );
    expect(
      schema,
      contains('uid = (select auth.uid())::text'),
      reason: 'RLS policies should cache auth.uid() instead of recomputing per row.',
    );
    expect(
      schema,
      contains('participant.uid = (select auth.uid())::text'),
      reason: 'Room policies should cache auth.uid() inside the EXISTS subquery.',
    );
    expect(
      verify,
      contains("to_regclass('public.users') is not null as exists"),
      reason: 'The verification script should check the live users table.',
    );
    expect(
      verify,
      contains("to_regclass('public.rooms') is not null as exists"),
      reason: 'The verification script should check the live rooms table.',
    );
    expect(
      verify,
      contains("to_regclass('public.friend_requests') is not null as exists"),
      reason: 'The verification script should check the live friend_requests table.',
    );
    expect(
      verify,
      contains("cleanup_backend_state"),
      reason: 'The verification script should check the cleanup RPC.',
    );
  });
}
