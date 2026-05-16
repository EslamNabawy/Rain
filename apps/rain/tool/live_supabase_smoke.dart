import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:protocol_brain/testing.dart';
import 'package:rain/services/rain_runtime_controller.dart';
import 'package:rain_core/rain_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _definedSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _definedSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
);
const String _definedSmokeUsername = String.fromEnvironment(
  'RAIN_SMOKE_USERNAME',
);
const String _definedSmokePassword = String.fromEnvironment(
  'RAIN_SMOKE_PASSWORD',
);
const String _definedSmokePeerUsername = String.fromEnvironment(
  'RAIN_SMOKE_PEER_USERNAME',
);
const String _definedSmokePeerPassword = String.fromEnvironment(
  'RAIN_SMOKE_PEER_PASSWORD',
);
const String _definedSmokeSkipConnect = String.fromEnvironment(
  'RAIN_SMOKE_SKIP_CONNECT',
);

String _readSetting(String name, String fallback) {
  final runtime = Platform.environment[name]?.trim();
  if (runtime != null && runtime.isNotEmpty) {
    return runtime;
  }
  return fallback.trim();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await runLiveSupabaseSmoke();
    stdout.writeln('LIVE_SUPABASE_SMOKE=PASS');
  } catch (error, stackTrace) {
    stderr.writeln('LIVE_SUPABASE_SMOKE=FAIL');
    stderr.writeln(error);
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    exit(exitCode);
  }
}

Future<void> runLiveSupabaseSmoke() async {
  final config = _LiveSmokeConfig.fromEnvironment();
  final roomId = _roomId(config.primaryUsername, config.peerUsername);
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final aliceClient = SupabaseClient(
    config.supabaseUrl,
    config.supabaseAnonKey,
    authOptions: const AuthClientOptions(
      authFlowType: AuthFlowType.implicit,
      autoRefreshToken: false,
    ),
  );
  final bobClient = SupabaseClient(
    config.supabaseUrl,
    config.supabaseAnonKey,
    authOptions: const AuthClientOptions(
      authFlowType: AuthFlowType.implicit,
      autoRefreshToken: false,
    ),
  );

  final aliceAdapter = SupabaseSignalingAdapter(
    projectUrl: config.supabaseUrl,
    client: aliceClient,
  );
  final bobAdapter = SupabaseSignalingAdapter(
    projectUrl: config.supabaseUrl,
    client: bobClient,
  );

  final aliceDb = RainDatabase(NativeDatabase.memory());
  final bobDb = RainDatabase(NativeDatabase.memory());

  final aliceIdentity = RainIdentity(
    username: config.primaryUsername,
    displayName: config.primaryUsername,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    gender: null,
  );
  final bobIdentity = RainIdentity(
    username: config.peerUsername,
    displayName: config.peerUsername,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    gender: null,
  );

  final aliceBrain = createDefaultProtocolBrain(
    selfUsername: config.primaryUsername,
    adapter: aliceAdapter,
    iceServers: const <Map<String, dynamic>>[],
    connectionMemoryStore: DriftConnectionMemoryStore(aliceDb),
    peerFactory: createLiveSmokePeerCore,
  );
  final bobBrain = createDefaultProtocolBrain(
    selfUsername: config.peerUsername,
    adapter: bobAdapter,
    iceServers: const <Map<String, dynamic>>[],
    connectionMemoryStore: DriftConnectionMemoryStore(bobDb),
    peerFactory: createLiveSmokePeerCore,
  );

  final runtimeAlice = RainRuntimeController(
    selfIdentity: aliceIdentity,
    adapter: aliceAdapter,
    brain: aliceBrain,
    database: aliceDb,
    friendStore: FriendStore(aliceDb),
    messageStore: MessageStore(aliceDb),
    offlineQueueStore: OfflineQueueStore(aliceDb),
    messageDeliveryService: MessageDeliveryService(
      messageStore: MessageStore(aliceDb),
      offlineQueueStore: OfflineQueueStore(aliceDb),
    ),
  );
  final runtimeBob = RainRuntimeController(
    selfIdentity: bobIdentity,
    adapter: bobAdapter,
    brain: bobBrain,
    database: bobDb,
    friendStore: FriendStore(bobDb),
    messageStore: MessageStore(bobDb),
    offlineQueueStore: OfflineQueueStore(bobDb),
    messageDeliveryService: MessageDeliveryService(
      messageStore: MessageStore(bobDb),
      offlineQueueStore: OfflineQueueStore(bobDb),
    ),
  );

  try {
    await _authenticateSmokeUser(
      aliceAdapter,
      config.primaryUsername,
      config.primaryPassword,
    );
    await _authenticateSmokeUser(
      bobAdapter,
      config.peerUsername,
      config.peerPassword,
    );

    await aliceAdapter.deleteRoom(roomId).catchError((_) {});
    await aliceAdapter
        .deleteFriendship(config.primaryUsername, config.peerUsername)
        .catchError((_) {});

    await runtimeAlice.start();
    await runtimeBob.start();

    await runtimeAlice.sendFriendRequest(config.peerUsername);
    await _waitUntil(() async {
      final friend = await runtimeBob.friendStore.loadFriend(
        config.primaryUsername,
      );
      return friend?.state == FriendState.pendingIncoming;
    }, description: 'bob inbound friend request');

    await runtimeBob.acceptFriend(config.primaryUsername);

    await _waitUntil(() async {
      final aliceFriend = await runtimeAlice.friendStore.loadFriend(
        config.peerUsername,
      );
      final bobFriend = await runtimeBob.friendStore.loadFriend(
        config.primaryUsername,
      );
      return aliceFriend?.state == FriendState.friend &&
          bobFriend?.state == FriendState.friend;
    }, description: 'friend acceptance reconciliation');

    if (config.skipConnect) {
      await runtimeAlice.dispose();
      await runtimeBob.dispose();

      await _waitUntil(() async {
        final identity = await aliceAdapter.fetchIdentity(
          config.primaryUsername,
        );
        return identity != null && identity.online == false;
      }, description: 'alice offline cleanup');
      await _waitUntil(() async {
        final identity = await bobAdapter.fetchIdentity(config.peerUsername);
        return identity != null && identity.online == false;
      }, description: 'bob offline cleanup');

      stdout.writeln('LIVE_SUPABASE_SMOKE_DETAILS');
      stdout.writeln('  mode=friend-only');
      stdout.writeln('  alice=${config.primaryUsername}');
      stdout.writeln('  bob=${config.peerUsername}');
      return;
    }

    final aliceConnected = aliceBrain.onPeerConnected.first;
    await runtimeAlice.connectPeer(config.peerUsername);

    await _waitUntil(
      () async => (await _roomRows(aliceClient, roomId)).isNotEmpty,
      description: 'room creation',
    );

    await aliceConnected;

    await _waitUntil(
      () async => (await _roomRows(aliceClient, roomId)).isEmpty,
      description: 'room cleanup',
    );

    await runtimeAlice.dispose();
    await runtimeBob.dispose();

    await _waitUntil(() async {
      final identity = await aliceAdapter.fetchIdentity(config.primaryUsername);
      return identity != null && identity.online == false;
    }, description: 'alice offline cleanup');
    await _waitUntil(() async {
      final identity = await bobAdapter.fetchIdentity(config.peerUsername);
      return identity != null && identity.online == false;
    }, description: 'bob offline cleanup');

    stdout.writeln('LIVE_SUPABASE_SMOKE_DETAILS');
    stdout.writeln('  alice=${config.primaryUsername}');
    stdout.writeln('  bob=${config.peerUsername}');
    stdout.writeln('  room=$roomId');
  } finally {
    await runtimeAlice.dispose();
    await runtimeBob.dispose();
    try {
      await aliceAdapter.deleteRoom(roomId);
    } catch (_) {}
    try {
      await aliceAdapter.deleteFriendship(
        config.primaryUsername,
        config.peerUsername,
      );
    } catch (_) {}
    try {
      await aliceAdapter.deleteFriendRequest(
        config.peerUsername,
        config.primaryUsername,
      );
    } catch (_) {}
    try {
      await aliceAdapter.deleteFriendRequest(
        config.primaryUsername,
        config.peerUsername,
      );
    } catch (_) {}
    await aliceAdapter.signOut();
    await bobAdapter.signOut();
    await aliceDb.close();
    await bobDb.close();
    await aliceClient.dispose();
    await bobClient.dispose();
  }
}

class _LiveSmokeConfig {
  const _LiveSmokeConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.primaryUsername,
    required this.primaryPassword,
    required this.peerUsername,
    required this.peerPassword,
    required this.skipConnect,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String primaryUsername;
  final String primaryPassword;
  final String peerUsername;
  final String peerPassword;
  final bool skipConnect;

  factory _LiveSmokeConfig.fromEnvironment() {
    final supabaseUrl = _readSetting('SUPABASE_URL', _definedSupabaseUrl);
    final supabaseAnonKey = _readSetting(
      'SUPABASE_ANON_KEY',
      _definedSupabaseAnonKey,
    );
    final primaryUsername = _readSetting(
      'RAIN_SMOKE_USERNAME',
      _definedSmokeUsername,
    ).toLowerCase();
    final primaryPassword = _readSetting(
      'RAIN_SMOKE_PASSWORD',
      _definedSmokePassword,
    );
    final peerUsernameSetting = _readSetting(
      'RAIN_SMOKE_PEER_USERNAME',
      _definedSmokePeerUsername,
    ).toLowerCase();
    final peerPasswordSetting = _readSetting(
      'RAIN_SMOKE_PEER_PASSWORD',
      _definedSmokePeerPassword,
    );
    final skipConnect =
        _readSetting(
          'RAIN_SMOKE_SKIP_CONNECT',
          _definedSmokeSkipConnect,
        ).toLowerCase() ==
        'true';

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError('SUPABASE_URL and SUPABASE_ANON_KEY are required');
    }
    if (primaryUsername.isEmpty || primaryPassword.isEmpty) {
      throw StateError(
        'RAIN_SMOKE_USERNAME and RAIN_SMOKE_PASSWORD are required',
      );
    }

    final peerUsername = peerUsernameSetting.isEmpty
        ? _derivePeerUsername(primaryUsername)
        : peerUsernameSetting;
    if (peerUsername == primaryUsername) {
      throw StateError(
        'RAIN_SMOKE_PEER_USERNAME must be different from RAIN_SMOKE_USERNAME',
      );
    }

    return _LiveSmokeConfig(
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
      primaryUsername: primaryUsername,
      primaryPassword: primaryPassword,
      peerUsername: peerUsername,
      peerPassword: peerPasswordSetting.isEmpty
          ? primaryPassword
          : peerPasswordSetting,
      skipConnect: skipConnect,
    );
  }
}

String _derivePeerUsername(String primaryUsername) {
  const suffix = '_peer';
  if (primaryUsername.length + suffix.length <= 24) {
    return '$primaryUsername$suffix';
  }
  return '${primaryUsername.substring(0, 24 - suffix.length)}$suffix';
}

String _roomId(String a, String b) {
  final users = <String>[a, b]..sort();
  return users.join(':');
}

Future<List<Map<String, dynamic>>> _roomRows(
  SupabaseClient client,
  String roomId,
) async {
  final rows = await client.from('rooms').select().eq('room_id', roomId);
  return (rows as List<dynamic>)
      .map((dynamic row) => Map<String, dynamic>.from(row as Map))
      .toList(growable: false);
}

Future<void> _waitUntil(
  Future<bool> Function() predicate, {
  required String description,
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(milliseconds: 250),
}) async {
  final started = DateTime.now();
  while (true) {
    if (await predicate()) {
      return;
    }
    if (DateTime.now().difference(started) > timeout) {
      throw TimeoutException('Timed out waiting for $description');
    }
    await Future<void>.delayed(interval);
  }
}

Future<void> _authenticateSmokeUser(
  SupabaseSignalingAdapter adapter,
  String username,
  String password,
) async {
  try {
    await adapter.login(username, password);
  } catch (_) {
    await adapter.register(username, password);
  }
}
