import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _repoFile(String relativePath) {
  final workspaceRoot = Directory.current.parent.parent;
  return File.fromUri(
    workspaceRoot.uri.resolve(relativePath),
  ).readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  test('Firebase adapter does not store password hashes client-side', () {
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(adapter, isNot(contains('_hashPassword')));
    expect(adapter, isNot(contains('passwordHash')));
  });

  test('Firebase friend request writes are tied to sender identity', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(
      rules,
      contains("root.child('users/' + \$from + '/uid').val() === auth.uid"),
    );
    expect(
      rules,
      isNot(
        contains('''"friendRequests": {
      ".read": "auth != null"'''),
      ),
    );
    expect(rules, contains('"outgoingFriendRequests"'));
    expect(adapter, contains('outgoingFriendRequests/'));
    expect(
      rules,
      isNot(
        contains('''"\$from": {
          ".write": "auth != null"'''),
      ),
    );
  });

  test('Firebase user ownership is immutable and tied to auth email', () {
    final rules = _repoFile('backend/firebase/database.rules.json');

    expect(rules, contains("auth.token.email === \$username + '@rain.local'"));
    expect(rules, contains('!data.exists()'));
    expect(rules, contains("data.child('uid').val() === auth.uid"));
    expect(
      rules,
      contains("newData.child('uid').val() === data.child('uid').val()"),
    );
  });

  test('Firebase rooms require participant metadata and ownership checks', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(rules, contains('"userA"'));
    expect(rules, contains('"userB"'));
    expect(
      rules,
      contains('!data.exists()'),
      reason:
          'Peers must be able to attach offer/answer/ICE listeners before the room is created.',
    );
    expect(rules, contains("data.child('userA').val()"));
    expect(rules, contains("newData.child('userA').val()"));
    expect(
      rules,
      contains(
        "newData.child('userA').val() + ':' + newData.child('userB').val() === \$roomId",
      ),
    );
    expect(
      rules,
      contains("newData.child('userA').val() < newData.child('userB').val()"),
    );
    expect(
      rules,
      contains("newData.child('userA').val() === data.child('userA').val()"),
    );
    expect(rules, contains('!data.exists() && !newData.exists()'));
    expect(adapter, contains("'userA':"));
    expect(adapter, contains("'userB':"));
  });

  test('Firebase signaling room payloads are encrypted envelopes', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(rules, contains('A256GCM-HKDF-SHA256'));
    expect(rules, contains("'nonce', 'ciphertext', 'mac'"));
    expect(rules, contains("newData.child('ciphertext').isString()"));
    expect(rules, contains("newData.child('mac').isString()"));
    expect(rules, isNot(contains("newData.hasChildren(['sdp', 'ts'])")));
    expect(rules, isNot(contains("newData.child('candidate').isString()")));
    expect(adapter, contains('SignalingCipher'));
    expect(adapter, contains('encryptPayload'));
    expect(adapter, contains('decryptPayload'));
    expect(adapter, isNot(contains("'offer': offer.toJson()")));
    expect(adapter, isNot(contains("'answer': answer.toJson()")));
    expect(
      adapter,
      isNot(contains(r"'$path/$candidateKey': iceCandidateToJson(candidate)")),
    );
  });

  test('Firebase friendships require a pending request before creation', () {
    final rules = _repoFile('backend/firebase/database.rules.json');

    expect(
      rules,
      contains(
        "root.child('friendRequests/' + \$username + '/' + \$friend).exists()",
      ),
    );
    expect(
      rules,
      contains(
        "root.child('friendRequests/' + \$friend + '/' + \$username).exists()",
      ),
    );
    expect(
      rules,
      contains("root.child('users/' + \$username + '/uid').val() === auth.uid"),
    );
    expect(
      rules,
      contains("root.child('users/' + \$friend + '/uid').val() === auth.uid"),
    );
  });

  test('Firebase relationship rules reject self relationships', () {
    final rules = _repoFile('backend/firebase/database.rules.json');

    expect(rules, contains(r'$from !== $to'));
    expect(rules, contains(r'$username !== $friend'));
  });
}
