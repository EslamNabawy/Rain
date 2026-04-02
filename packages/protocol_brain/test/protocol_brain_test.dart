import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

void main() {
  test('roomId is deterministic regardless of peer order', () {
    expect(roomId('alice', 'bob'), 'alice:bob');
    expect(roomId('bob', 'alice'), 'alice:bob');
  });

  test('connection memory usability respects cache rules', () {
    final memory = ConnectionMemory(
      peerId: 'bob',
      lastConnectedAt: DateTime.now().millisecondsSinceEpoch,
      cachedIce: const [],
      fingerprint: 'x',
      consecutiveFailures: 0,
    );

    expect(memory.isUsable, isFalse);
  });

  test('backend identity serializes separately for firebase and supabase', () {
    const identity = BackendIdentity(
      username: 'alice',
      uid: 'uid-1',
      displayName: 'Alice',
      gender: null,
      registeredAt: 1,
      lastSeen: 2,
      lastHeartbeat: 3,
      online: true,
    );

    expect(
      identity.toFirebaseJson(),
      <String, Object?>{
        'username': 'alice',
        'displayName': 'Alice',
        'gender': null,
        'registeredAt': 1,
        'lastSeen': 2,
        'lastHeartbeat': 3,
        'online': true,
        'uid': 'uid-1',
      },
    );

    expect(
      identity.toSupabaseJson(),
      <String, Object?>{
        'username': 'alice',
        'display_name': 'Alice',
        'gender': null,
        'registered_at': 1,
        'last_seen': 2,
        'last_heartbeat': 3,
        'online': true,
        'uid': 'uid-1',
      },
    );
  });
}
