import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/services/rain_runtime_controller.dart';
import 'package:rain_core/rain_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const String expectedSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9teGdvbWZzZGdmaWR6ZnlkdGpkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUxNTcwMDQsImV4cCI6MjA5MDczMzAwNH0.xtranl425vN_Nc2EZLRXgQuoFODPmXEAFPJGazBYu4E';

Future<void> main() async {
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
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw StateError('Missing SUPABASE_URL or SUPABASE_ANON_KEY dart define');
  }
  stdout.writeln('SUPABASE_ANON_KEY_LEN=${supabaseAnonKey.length}');
  stdout.writeln(
    'SUPABASE_ANON_KEY_HEAD=${supabaseAnonKey.substring(0, supabaseAnonKey.length < 16 ? supabaseAnonKey.length : 16)}',
  );
  stdout.writeln(
    'SUPABASE_ANON_KEY_TAIL=${supabaseAnonKey.substring(supabaseAnonKey.length < 16 ? 0 : supabaseAnonKey.length - 16)}',
  );
  final keyChecksum = supabaseAnonKey.codeUnits.fold<int>(
    0,
    (int total, int unit) => (total + unit) % 0x7fffffff,
  );
  stdout.writeln('SUPABASE_ANON_KEY_SUM=$keyChecksum');
  if (supabaseAnonKey != expectedSupabaseAnonKey) {
    final maxLen = supabaseAnonKey.length < expectedSupabaseAnonKey.length
        ? supabaseAnonKey.length
        : expectedSupabaseAnonKey.length;
    for (var i = 0; i < maxLen; i++) {
      if (supabaseAnonKey.codeUnitAt(i) != expectedSupabaseAnonKey.codeUnitAt(i)) {
        stdout.writeln(
          'SUPABASE_ANON_KEY_DIFF index=$i app=${supabaseAnonKey.codeUnitAt(i)} expected=${expectedSupabaseAnonKey.codeUnitAt(i)}',
        );
        break;
      }
    }
    stdout.writeln(
      'SUPABASE_ANON_KEY_EQUAL=false expected_len=${expectedSupabaseAnonKey.length}',
    );
  } else {
    stdout.writeln('SUPABASE_ANON_KEY_EQUAL=true');
  }

  const aliceUsername = 'rainuser1';
  const bobUsername = 'rainuser2';
  const password = 'rain1234';
  final roomId = _roomId(aliceUsername, bobUsername);

  final aliceClient = SupabaseClient(
    supabaseUrl,
    supabaseAnonKey,
    authOptions: const AuthClientOptions(
      authFlowType: AuthFlowType.implicit,
      autoRefreshToken: false,
    ),
  );
  final bobClient = SupabaseClient(
    supabaseUrl,
    supabaseAnonKey,
    authOptions: const AuthClientOptions(
      authFlowType: AuthFlowType.implicit,
      autoRefreshToken: false,
    ),
  );

  final aliceAdapter = SupabaseSignalingAdapter(client: aliceClient);
  final bobAdapter = SupabaseSignalingAdapter(client: bobClient);

  final aliceDb = RainDatabase(NativeDatabase.memory());
  final bobDb = RainDatabase(NativeDatabase.memory());

  final aliceIdentity = RainIdentity(
    username: aliceUsername,
    displayName: aliceUsername,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    gender: null,
  );
  final bobIdentity = RainIdentity(
    username: bobUsername,
    displayName: bobUsername,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    gender: null,
  );

  final aliceBrain = createDefaultProtocolBrain(
    selfUsername: aliceUsername,
    adapter: aliceAdapter,
    iceServers: const <Map<String, dynamic>>[],
    connectionMemoryStore: DriftConnectionMemoryStore(aliceDb),
    peerFactory: _LiveSmokePeerCore.new,
  );
  final bobBrain = createDefaultProtocolBrain(
    selfUsername: bobUsername,
    adapter: bobAdapter,
    iceServers: const <Map<String, dynamic>>[],
    connectionMemoryStore: DriftConnectionMemoryStore(bobDb),
    peerFactory: _LiveSmokePeerCore.new,
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
    await _loginWithPasswordGrant(aliceClient, aliceUsername, password);
    await _loginWithPasswordGrant(bobClient, bobUsername, password);

    await runtimeAlice.start();
    await runtimeBob.start();

    final friendRequestFuture = bobAdapter.onFriendRequest(bobUsername).first;
    await runtimeAlice.sendFriendRequest(bobUsername);
    final inboundFriendRequest = await friendRequestFuture;
    if (inboundFriendRequest != aliceUsername) {
      throw StateError('Expected bob to receive a friend request from alice');
    }

    await runtimeBob.acceptFriend(aliceUsername);

    final aliceConnected = aliceBrain.onPeerConnected.first;
    await runtimeAlice.connectPeer(bobUsername);

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
      final identity = await aliceAdapter.fetchIdentity(aliceUsername);
      return identity != null && identity.online == false;
    }, description: 'alice offline cleanup');
    await _waitUntil(() async {
      final identity = await bobAdapter.fetchIdentity(bobUsername);
      return identity != null && identity.online == false;
    }, description: 'bob offline cleanup');

    stdout.writeln('LIVE_SUPABASE_SMOKE_DETAILS');
    stdout.writeln('  alice=$aliceUsername');
    stdout.writeln('  bob=$bobUsername');
    stdout.writeln('  room=$roomId');
  } finally {
    await runtimeAlice.dispose();
    await runtimeBob.dispose();
    try {
      await aliceAdapter.deleteRoom(roomId);
    } catch (_) {}
    try {
      await aliceAdapter.deleteFriendRequest(bobUsername, aliceUsername);
    } catch (_) {}
    try {
      await aliceAdapter.deleteFriendRequest(aliceUsername, bobUsername);
    } catch (_) {}
    await aliceAdapter.signOut();
    await bobAdapter.signOut();
    await aliceDb.close();
    await bobDb.close();
    await aliceClient.dispose();
    await bobClient.dispose();
  }
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

Future<void> _loginWithPasswordGrant(
  SupabaseClient client,
  String username,
  String password,
) async {
  final email = '$username@gmail.com';
  final apiKey = supabaseAnonKey.trim();
  final bodyJson = jsonEncode(<String, String>{
    'email': email,
    'password': password,
  });
  final script = '''
\$headers = @{
  apikey = '$apiKey'
  Authorization = 'Bearer $apiKey'
  'Content-Type' = 'application/json'
}
\$body = '$bodyJson'
Invoke-RestMethod -Uri '$supabaseUrl/auth/v1/token?grant_type=password' -Headers \$headers -Method Post -Body \$body | ConvertTo-Json -Depth 6
''';
  final result = await Process.run(
    'powershell.exe',
    <String>['-NoProfile', '-Command', script],
    runInShell: false,
  );
  final body = (result.stdout as String?)?.trim().isNotEmpty == true
      ? (result.stdout as String).trim()
      : (result.stderr as String?)?.trim() ?? '';
  if (result.exitCode != 0) {
    throw StateError(
      'Password grant failed for $email: ${result.exitCode} $body',
    );
  }

  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final refreshToken = decoded['refresh_token'] as String?;
  if (refreshToken == null || refreshToken.isEmpty) {
    throw StateError('Password grant response missing refresh token for $email');
  }

  await client.auth.setSession(refreshToken);
}

class _LiveSmokePeerCore implements PeerCore {
  _LiveSmokePeerCore({
    Duration connectDelay = const Duration(milliseconds: 800),
  }) : _connectDelay = connectDelay;

  final Duration _connectDelay;

  final StreamController<RTCIceCandidate> _iceController =
      StreamController<RTCIceCandidate>.broadcast();
  final StreamController<void> _connectedController =
      StreamController<void>.broadcast();
  final StreamController<void> _disconnectedController =
      StreamController<void>.broadcast();
  final StreamController<PeerMessage> _messageController =
      StreamController<PeerMessage>.broadcast();
  final StreamController<String> _channelOpenController =
      StreamController<String>.broadcast();
  final StreamController<String> _channelCloseController =
      StreamController<String>.broadcast();
  final StreamController<PeerState> _stateController =
      StreamController<PeerState>.broadcast();

  Timer? _connectTimer;
  PeerState _state = PeerState.idle;
  bool _connectedFired = false;

  @override
  Stream<RTCIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<void> get onConnected => _connectedController.stream;

  @override
  Stream<void> get onDisconnected => _disconnectedController.stream;

  @override
  Stream<PeerMessage> get onMessage => _messageController.stream;

  @override
  Stream<String> get onChannelOpen => _channelOpenController.stream;

  @override
  Stream<String> get onChannelClose => _channelCloseController.stream;

  @override
  Stream<PeerState> get onStateChange => _stateController.stream;

  @override
  PeerState get state => _state;

  @override
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {}

  @override
  Future<void> closeChannel(String channelId) async {}

  @override
  Future<RTCSessionDescription> createOffer() async {
    _transition(PeerState.offering);
    return RTCSessionDescription('fake-offer', 'offer');
  }

  @override
  Future<void> destroy() async {
    _connectTimer?.cancel();
    _connectTimer = null;
    if (_state != PeerState.idle) {
      _transition(PeerState.idle);
    }
  }

  @override
  List<RTCIceCandidate> getLocalCandidates() => const <RTCIceCandidate>[];

  @override
  Future<void> init(PeerConfig config) async {
    _transition(PeerState.ready);
  }

  @override
  Future<void> openChannel(
    String channelId, {
    RTCDataChannelInit? opts,
  }) async {}

  @override
  void send(String channelId, dynamic data) {}

  @override
  Future<void> setAnswer(RTCSessionDescription answer) async {
    _transition(PeerState.connected);
    _connectTimer?.cancel();
    _connectTimer = Timer(_connectDelay, () {
      if (_connectedFired || _state == PeerState.idle) {
        return;
      }
      _connectedFired = true;
      _connectedController.add(null);
    });
  }

  @override
  Future<RTCSessionDescription> setOffer(RTCSessionDescription offer) async {
    _transition(PeerState.answering);
    return RTCSessionDescription('fake-answer', 'answer');
  }

  void _transition(PeerState next) {
    if (_state == next) {
      return;
    }
    _state = next;
    _stateController.add(next);
  }
}
