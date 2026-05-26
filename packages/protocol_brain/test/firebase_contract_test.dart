import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _repoFile(String relativePath) {
  final workspaceRoot = _workspaceRoot();
  return File.fromUri(
    workspaceRoot.uri.resolve(relativePath),
  ).readAsStringSync().replaceAll('\r\n', '\n');
}

Directory _workspaceRoot() {
  var current = Directory.current;
  while (true) {
    final marker = File.fromUri(
      current.uri.resolve('backend/firebase/database.rules.json'),
    );
    if (marker.existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate Rain workspace root.');
    }
    current = parent;
  }
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

  test('Firebase relationship payload fields are explicitly allowed', () {
    final rules = _repoFile('backend/firebase/database.rules.json');

    expect(rules, contains('"sentAt"'));
    expect(rules, contains('newData.child(\'sentAt\').isNumber()'));
    expect(rules, contains('newData.isNumber()'));
    expect(rules, contains('"acceptedAt"'));
    expect(rules, contains('newData.child(\'acceptedAt\').isNumber()'));
    expect(rules, contains('"blockedAt"'));
    expect(rules, contains('newData.child(\'blockedAt\').isNumber()'));
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

  test('Firebase search uses bounded handle prefix lookups', () {
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(adapter, contains("child('userSearch')"));
    expect(adapter, contains('orderByKey()'));
    expect(adapter, contains('limitToFirst(_searchLimit)'));
    expect(adapter, isNot(contains("child('users').get()")));
  });

  test('Firebase presence lives in a dedicated lightweight node', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );
    final functions = _repoFile('backend/firebase/functions/index.js');

    expect(rules, contains('"presence"'));
    expect(adapter, contains("child('presence/\$username')"));
    expect(adapter, contains("'lastHeartbeat': now"));
    expect(adapter, isNot(contains("child('users/\$username/online')")));
    expect(functions, contains('.ref("presence")'));
    expect(functions, isNot(contains('.ref("users")')));
  });

  test('Firebase rooms carry explicit lifecycle metadata', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );
    final functions = _repoFile('backend/firebase/functions/index.js');

    expect(rules, contains('"attemptId"'));
    expect(rules, contains('"createdAt"'));
    expect(rules, contains('"updatedAt"'));
    expect(rules, contains('"expiresAt"'));
    expect(rules, contains('".indexOn": ["expiresAt"]'));
    expect(adapter, contains("'attemptId':"));
    expect(adapter, contains("'expiresAt':"));
    expect(functions, contains('.orderByChild("expiresAt")'));
    expect(functions, contains('.endAt(now)'));
  });

  test('Firebase voice signaling uses dedicated ephemeral namespaces', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );
    final functions = _repoFile('backend/firebase/functions/index.js');
    final readme = _repoFile('backend/firebase/README.md');

    for (final node in <String>[
      'activeVoicePairs',
      'activeVoiceUsers',
      'voiceCallInboxes',
      'voiceCalls',
    ]) {
      expect(rules, contains('"$node"'));
      expect(adapter, contains(node));
      expect(functions, contains(node));
      expect(readme, contains(node));
    }
    expect(rules, contains('".indexOn": ["expiresAt"]'));
    expect(functions, contains('exports.cleanupVoiceCalls'));
    expect(functions, contains('orderByChild("expiresAt")'));
    expect(
      functions,
      contains(r'voiceCallInboxes/${call.callee}/${child.key}'),
    );
  });

  test('Firebase voice signaling requires friends and blocks denied users', () {
    final rules = _repoFile('backend/firebase/database.rules.json');

    expect(rules, contains('root.child(\'friendships/\''));
    expect(rules, contains('root.child(\'blocks/\''));
    expect(rules, contains('"activeVoicePairs"'));
    expect(rules, contains('"activeVoiceUsers"'));
    expect(rules, contains('"voiceCalls"'));
    expect(
      rules,
      contains(
        "root.child('activeVoicePairs/' + newData.child('pairId').val() + '/callId').val() === \$callId",
      ),
    );
    expect(
      rules,
      contains(
        "root.child('activeVoiceUsers/' + newData.child('caller').val() + '/callId').val() === \$callId",
      ),
    );
    expect(
      rules,
      contains(
        "root.child('activeVoiceUsers/' + newData.child('callee').val() + '/callId').val() === \$callId",
      ),
    );
    expect(
      rules,
      contains(
        "root.child('friendships/' + newData.child('caller').val() + '/' + newData.child('callee').val()).exists()",
      ),
    );
  });

  test(
    'Firebase voice user locks are claimed transactionally',
    () {
      fail(
        'Phase 02 must make activeVoiceUsers lock claims transactional so two '
        'callers cannot overwrite each other and produce false busy or stale '
        'callee state.',
      );
    },
    skip: 'Phase 02 rewrites activeVoiceUsers lock claim behavior.',
  );

  test(
    'Firebase cleanup removes corrupt terminal call locks by callId',
    () {
      fail(
        'Phase 02 must let cleanup remove activeVoicePairs and both '
        'activeVoiceUsers entries when their callId matches a corrupt terminal '
        'room repaired by the cleanup parser.',
      );
    },
    skip: 'Phase 02 hardens Firebase cleanup.',
  );

  test('Firebase voice signaling stores encrypted SDP and ICE envelopes', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(rules, contains('"offer"'));
    expect(rules, contains('"answer"'));
    expect(rules, contains('"ice"'));
    expect(rules, contains('"caller"'));
    expect(rules, contains('"callee"'));
    expect(rules, contains("'nonce', 'ciphertext', 'mac'"));
    expect(
      rules,
      contains("newData.child('ciphertext').val().length <= 262144"),
    );
    expect(
      rules,
      contains("newData.child('ciphertext').val().length <= 32768"),
    );
    expect(adapter, contains('writeVoiceOffer'));
    expect(adapter, contains('writeVoiceAnswer'));
    expect(adapter, contains('writeIceCandidate'));
    expect(adapter, contains('VoiceSignalingEnvelope.fromJson'));
    expect(adapter, isNot(contains("'sdp':")));
    expect(adapter, isNot(contains("'candidate':")));
  });

  test('Firebase voice signaling validates video metadata fields', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(rules, contains('"mediaMode"'));
    expect(
      rules,
      contains("newData.val() === 'audio' || newData.val() === 'video'"),
    );
    expect(rules, isNot(contains("newData.val() === 'screen'")));
    expect(rules, contains('"cameraMuted"'));
    expect(rules, contains('newData.isBoolean()'));
    expect(rules, contains(r'"$other"'));
    expect(adapter, contains('CallMediaMode mediaMode'));
    expect(adapter, contains('mediaMode: mediaMode'));
    expect(adapter, contains('setCameraMuted'));
    expect(adapter, contains(r'cameraMuted/$normalizedUsername'));
  });

  test('Firebase voice signaling enforces role-specific writes', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(
      rules,
      contains(
        "root.child('users/' + root.child('voiceCalls/' + \$callId + '/caller').val() + '/uid').val() === auth.uid",
      ),
    );
    expect(
      rules,
      contains(
        "root.child('users/' + root.child('voiceCalls/' + \$callId + '/callee').val() + '/uid').val() === auth.uid",
      ),
    );
    expect(rules, contains("newData.val() === 'accepted'"));
    expect(rules, contains("newData.val() === 'negotiating'"));
    expect(rules, contains("newData.val() === 'connected'"));
    expect(adapter, contains('_ensureVoiceRole'));
    expect(adapter, contains('VoiceCallRole.caller'));
    expect(adapter, contains('VoiceCallRole.callee'));
  });

  test('Firebase backend does not depend on managed TURN provider secrets', () {
    final functions = _repoFile('backend/firebase/functions/index.js');
    final readme = _repoFile('backend/firebase/README.md');
    final appDefines = _repoFile('apps/rain/tool/dart_defines.example.json');

    expect(functions, isNot(contains('CLOUDFLARE')));
    expect(functions, isNot(contains('cloudflare')));
    expect(functions, isNot(contains('defineSecret')));
    expect(functions, isNot(contains('api.twilio.com')));
    expect(functions, isNot(contains('TURN_STATIC_AUTH_SECRET')));
    expect(readme, isNot(contains('Cloudflare')));
    expect(appDefines, isNot(contains('CLOUDFLARE_TURN_API_TOKEN')));
    expect(appDefines, isNot(contains('CLOUDFLARE_TURN_KEY_ID')));
    expect(appDefines, contains('"RAIN_ALLOW_PUBLIC_TURN": "true"'));
    expect(appDefines, contains('stun:stun4.l.google.com:19302'));
    expect(appDefines, contains('stun:stun.sipgate.net:10000'));
    expect(appDefines, isNot(contains('stun.cloudflare.com')));
    expect(appDefines, contains('openrelay.metered.ca'));
  });

  test('Firebase rules do not expose unused push notification surface', () {
    final rules = _repoFile('backend/firebase/database.rules.json');

    expect(rules, isNot(contains('"notificationTokens"')));
    expect(rules, isNot(contains('"messagePings"')));
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

  test('Firebase blocks are mirrored and reject blocked relationships', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(rules, contains('"blocks"'));
    expect(rules, contains('"blockedBy"'));
    expect(
      rules,
      contains("root.child('blocks/' + \$to + '/' + \$from).exists()"),
    );
    expect(
      rules,
      contains("root.child('blocks/' + \$from + '/' + \$to).exists()"),
    );
    expect(
      rules,
      contains("root.child('blocks/' + \$username + '/' + \$friend).exists()"),
    );
    expect(
      adapter,
      contains("'blocks/\$normalizedBlocker/\$normalizedBlocked'"),
    );
    expect(
      adapter,
      contains("'blockedBy/\$normalizedBlocked/\$normalizedBlocker'"),
    );
    expect(adapter, contains('onRelationshipChanged'));
  });

  test('Firebase relationship rules reject self relationships', () {
    final rules = _repoFile('backend/firebase/database.rules.json');

    expect(rules, contains(r'$from !== $to'));
    expect(rules, contains(r'$username !== $friend'));
  });
}
