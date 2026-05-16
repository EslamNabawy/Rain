import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Supabase contract stays aligned with the app validator', () {
    final workspaceRoot = Directory.current.parent.parent;
    final schemaFile = File.fromUri(
      workspaceRoot.uri.resolve('backend/supabase/schema.sql'),
    );
    final backendReadmeFile = File.fromUri(
      workspaceRoot.uri.resolve('backend/supabase/README.md'),
    );
    final verifyFile = File.fromUri(
      workspaceRoot.uri.resolve('backend/supabase/verify.sql'),
    );
    final adapterFile = File.fromUri(
      workspaceRoot.uri.resolve(
        'packages/protocol_brain/lib/adapters/supabase_adapter.dart',
      ),
    );
    final aliasFile = File.fromUri(
      workspaceRoot.uri.resolve(
        'packages/protocol_brain/lib/adapters/supabase_auth_alias.dart',
      ),
    );
    final androidSmokeFile = File.fromUri(
      workspaceRoot.uri.resolve(
        'apps/rain/tool/android_presence_refresh_smoke.dart',
      ),
    );
    final liveSmokeFile = File.fromUri(
      workspaceRoot.uri.resolve('apps/rain/tool/live_supabase_smoke.dart'),
    );
    final validatorFile = File.fromUri(
      workspaceRoot.uri.resolve(
        'packages/rain_core/lib/src/input_validator.dart',
      ),
    );

    final schema = schemaFile.readAsStringSync();
    final backendReadme = backendReadmeFile.readAsStringSync();
    final verify = verifyFile.readAsStringSync();
    final adapter = adapterFile.readAsStringSync();
    final alias = aliasFile.readAsStringSync();
    final androidSmoke = androidSmokeFile.readAsStringSync();
    final liveSmoke = liveSmokeFile.readAsStringSync();
    final validator = validatorFile.readAsStringSync();

    expect(
      schema,
      contains(
        r"username text primary key check (username ~ '^[a-z0-9_]{3,24}$')",
      ),
      reason: 'Supabase must accept the same username length as the app.',
    );
    expect(
      schema,
      contains('create table if not exists public.app_config'),
      reason:
          'Supabase should expose an app_config row for the force-update gate.',
    );
    expect(
      schema,
      contains('create policy "app_config_select_public"'),
      reason: 'The force-update gate should be readable before login.',
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
      reason:
          'Username substring search should use pg_trgm instead of seq scans.',
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
      contains('create table if not exists public.friendships'),
      reason: 'Accepted friendships should persist beyond local session data.',
    );
    expect(
      schema,
      contains('create policy "friendships_select_participants"'),
      reason: 'Friendship rows should be readable by both participants.',
    );
    expect(
      schema,
      contains('create index if not exists users_online_last_heartbeat_idx'),
      reason:
          'Presence cleanup should use an index on the heartbeat timestamp.',
    );
    expect(
      schema,
      contains('create or replace function public.canonical_room_id'),
      reason:
          'Room rows should be normalized through a canonical room id helper.',
    );
    expect(
      schema,
      contains('rooms_canonical_room_id_check'),
      reason: 'Room ids and room participants must stay aligned.',
    );
    expect(
      schema,
      contains('rooms_participant_order_check'),
      reason: 'Room participants should stay in canonical sorted order.',
    );
    expect(
      schema,
      contains('guard_immutable_user_identity_fields'),
      reason:
          'Username ownership fields should remain immutable after registration.',
    );
    expect(
      schema,
      contains('uid = (select auth.uid())::text'),
      reason:
          'RLS policies should cache auth.uid() instead of recomputing per row.',
    );
    expect(
      schema,
      contains('participant.uid = (select auth.uid())::text'),
      reason:
          'Room policies should cache auth.uid() inside the EXISTS subquery.',
    );
    expect(
      backendReadme,
      contains('<username>@auth.<your-project-host>'),
      reason:
          'The backend runbook should document the auth alias used by the app.',
    );
    expect(
      alias,
      contains("return 'auth.\$host';"),
      reason:
          'The app-managed alias should derive from the Supabase project host.',
    );
    expect(
      adapter,
      contains('supabasePreferredEmailFromUsername'),
      reason: 'The Supabase adapter should use the shared auth alias helper.',
    );
    expect(
      androidSmoke,
      contains('supabasePreferredEmailFromUsername'),
      reason:
          'The Android presence smoke should authenticate with the same alias as the app.',
    );
    expect(
      alias,
      contains('@example.com'),
      reason:
          'The shared alias helper should retain the previous alias as a login fallback.',
    );
    expect(
      alias,
      contains('@rain.local'),
      reason:
          'The Supabase adapter should retain the previous invalid alias as a login fallback while existing local state is migrated.',
    );
    expect(
      alias,
      contains('@gmail.com'),
      reason:
          'The Supabase adapter should retain the legacy alias fallback for existing accounts.',
    );
    expect(
      androidSmoke,
      contains('supabaseLoginEmailsFromUsername'),
      reason:
          'The Android presence smoke should be able to authenticate legacy accounts before it provisions new ones.',
    );
    expect(
      liveSmoke,
      contains('SupabaseSignalingAdapter'),
      reason:
          'The live Supabase smoke should reuse the shared Supabase adapter auth path.',
    );
    expect(
      liveSmoke,
      isNot(contains('expectedSupabaseAnonKey')),
      reason:
          'Live smoke tooling should not hardcode a specific publishable key.',
    );
    expect(
      verify,
      contains("to_regclass('public.app_config') is not null as exists"),
      reason: 'The verification script should check the live app_config table.',
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
      reason:
          'The verification script should check the live friend_requests table.',
    );
    expect(
      verify,
      contains("to_regclass('public.friendships') is not null as exists"),
      reason:
          'The verification script should check the live friendships table.',
    );
    expect(
      verify,
      contains("cleanup_backend_state"),
      reason: 'The verification script should check the cleanup RPC.',
    );
  });

  test(
    'Supabase deployment surface contains no permissive public write policy scripts',
    () {
      final workspaceRoot = Directory.current.parent.parent;
      final supabaseDir = Directory.fromUri(
        workspaceRoot.uri.resolve('backend/supabase/'),
      );
      final offenders = <String>[];

      for (final file
          in supabaseDir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.sql')) {
          continue;
        }

        final sql = file.readAsStringSync().toLowerCase();
        final hasPublicWrite =
            sql.contains('for insert with check (true)') ||
            sql.contains('for update using (true)') ||
            sql.contains('for all using (true)');
        if (hasPublicWrite) {
          offenders.add(file.path);
        }
      }

      expect(offenders, isEmpty, reason: 'Permissive public write SQL found');
    },
  );

  test('Supabase rooms require accepted friendship between participants', () {
    final workspaceRoot = Directory.current.parent.parent;
    final schema = File.fromUri(
      workspaceRoot.uri.resolve('backend/supabase/schema.sql'),
    ).readAsStringSync().toLowerCase();

    expect(
      schema,
      contains('create or replace function public.accept_friend_request'),
    );
    expect(schema, contains('from public.friendships existing_friendship'));
    expect(schema, contains('existing_friendship.user_a = rooms.user_a'));
    expect(schema, contains('existing_friendship.user_b = rooms.user_b'));
  });

  test(
    'Supabase ICE writes use append RPC instead of client read-modify-write',
    () {
      final workspaceRoot = Directory.current.parent.parent;
      final schema = File.fromUri(
        workspaceRoot.uri.resolve('backend/supabase/schema.sql'),
      ).readAsStringSync().toLowerCase();
      final adapter = File.fromUri(
        workspaceRoot.uri.resolve(
          'packages/protocol_brain/lib/adapters/supabase_adapter.dart',
        ),
      ).readAsStringSync();

      expect(
        schema,
        contains('create or replace function public.append_room_ice'),
      );
      expect(adapter, contains("'append_room_ice'"));
      expect(adapter, contains('.rpc('));
      expect(adapter, isNot(contains('.select(field)')));
    },
  );
}
