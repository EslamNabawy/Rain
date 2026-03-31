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
}

