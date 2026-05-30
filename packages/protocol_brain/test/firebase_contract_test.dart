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
    expect(rules, contains('data.exists() && newData.val() === data.val()'));
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
    final rules = _repoFile('backend/firebase/database.rules.json');
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(
      rules,
      contains('''"userSearch": {
      ".read": "auth != null"'''),
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
    expect(rules, contains("root.child('presence/'"));
    expect(rules, contains("'/lastHeartbeat').isNumber()"));
    expect(rules, contains("< 45000"));
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
    expect(
      rules,
      contains(
        "root.child('presence/' + newData.child('callee').val() + '/online').val() === true",
      ),
    );
    expect(
      rules,
      contains(
        "now - root.child('presence/' + newData.child('callee').val() + '/lastHeartbeat').val() < 45000",
      ),
    );
    expect(
      rules,
      contains(
        "root.child('presence/' + newData.child('to').val() + '/online').val() === true",
      ),
    );
  });

  test('Firebase incoming call watcher repairs corrupt inbox entries', () {
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(adapter, contains('_removeCorruptVoiceCallInboxEntry'));
    expect(adapter, contains(r'voiceCallInboxes/$username/$callId'));
    expect(adapter, isNot(contains('controller.addError(error, stackTrace)')));
  });

  test('Firebase voice user locks are claimed transactionally', () {
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );

    expect(adapter, contains('Future<bool> _claimActiveVoiceUserLock'));
    expect(adapter, contains('required int createdAt'));
    expect(adapter, contains('lockRef.runTransaction'));
    expect(adapter, contains('VoiceActiveUserLock.fromJson'));
    expect(adapter, contains('existing.expiresAt > createdAt'));
    expect(adapter, contains('Transaction.abort()'));
    expect(adapter, isNot(contains('await lockRef.set(lock.toJson())')));
  });

  test('Firebase cleanup removes corrupt terminal call locks by callId', () {
    final adapter = _repoFile(
      'packages/protocol_brain/lib/adapters/firebase_adapter.dart',
    );
    final functions = _repoFile('backend/firebase/functions/index.js');

    expect(adapter, contains('VoiceCallRoom.tryParseForCleanup'));
    expect(functions, contains('queueExpiredVoiceLock'));
    expect(functions, contains("path: call.pairId ? `activeVoicePairs/"));
    expect(functions, contains("path: call.caller ? `activeVoiceUsers/"));
    expect(functions, contains("path: call.callee ? `activeVoiceUsers/"));
    expect(functions, contains('voiceLockMatchesExpected'));
    expect(functions, contains('current.callId !== expected.callId'));
  });

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

  test('Firebase room ICE writes are guarded by explicit sender role', () {
    final rules = _repoFile('backend/firebase/database.rules.json');

    expect(
      rules,
      contains(r'''"callerICE": {
          "$candidateId": {
            ".write": "auth != null'''),
      reason: 'callerICE candidates must not inherit broad room write access.',
    );
    expect(
      rules,
      contains(
        "root.child('users/' + root.child('rooms/' + \$roomId + '/userA').val() + '/uid').val() === auth.uid",
      ),
      reason: 'callerICE writes must be limited to the canonical caller role.',
    );
    expect(
      rules,
      contains(r'''"calleeICE": {
          "$candidateId": {
            ".write": "auth != null'''),
      reason: 'calleeICE candidates must not inherit broad room write access.',
    );
    expect(
      rules,
      contains(
        "root.child('users/' + root.child('rooms/' + \$roomId + '/userB').val() + '/uid').val() === auth.uid",
      ),
      reason: 'calleeICE writes must be limited to the canonical callee role.',
    );
  });

  test('Firebase room role rules reject cross-role ICE writes', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final callerIceRules = _rulesSlice(rules, '"callerICE"', '"calleeICE"');
    final calleeIceRules = _rulesSlice(
      rules,
      '"calleeICE"',
      '"activeVoicePairs"',
    );

    expect(
      callerIceRules,
      contains(
        "root.child('users/' + root.child('rooms/' + \$roomId + '/userA').val() + '/uid').val() === auth.uid",
      ),
    );
    expect(
      callerIceRules,
      isNot(
        contains(
          "root.child('users/' + root.child('rooms/' + \$roomId + '/userB').val() + '/uid').val() === auth.uid",
        ),
      ),
      reason: 'Canonical callee must not be able to write callerICE.',
    );
    expect(
      calleeIceRules,
      contains(
        "root.child('users/' + root.child('rooms/' + \$roomId + '/userB').val() + '/uid').val() === auth.uid",
      ),
    );
    expect(
      calleeIceRules,
      isNot(
        contains(
          "root.child('users/' + root.child('rooms/' + \$roomId + '/userA').val() + '/uid').val() === auth.uid",
        ),
      ),
      reason: 'Canonical caller must not be able to write calleeICE.',
    );
  });

  test('Firebase room identity metadata is immutable after create', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final roomRules = _rulesSlice(rules, '"rooms"', '"activeVoicePairs"');
    final attemptIdRules = _rulesSlice(roomRules, '"attemptId"', '"createdAt"');
    final createdAtRules = _rulesSlice(roomRules, '"createdAt"', '"updatedAt"');

    expect(
      rules,
      contains(
        '"userA": {\n          ".write": "auth != null && !root.child(\'security/blockedUids/\' + auth.uid).exists() && data.exists() && newData.val() === data.val()',
      ),
    );
    expect(
      rules,
      contains(
        '"userB": {\n          ".write": "auth != null && !root.child(\'security/blockedUids/\' + auth.uid).exists() && data.exists() && newData.val() === data.val()',
      ),
    );
    expect(
      rules,
      contains(
        "newData.child('attemptId').val() === \$roomId + ':' + newData.child('createdAt').val()",
      ),
      reason: 'New room attempts must bind attemptId to the createdAt reset.',
    );
    expect(
      roomRules,
      contains(
        "data.exists() && newData.exists() && newData.hasChildren(['userA', 'userB', 'attemptId', 'createdAt', 'updatedAt', 'expiresAt', 'offer'])",
      ),
      reason: 'Existing-room resets must be full room replacements.',
    );
    expect(roomRules, contains("!newData.child('answer').exists()"));
    expect(roomRules, contains("!newData.child('callerICE').exists()"));
    expect(roomRules, contains("!newData.child('calleeICE').exists()"));
    expect(
      attemptIdRules,
      contains('data.exists() && newData.val() === data.val()'),
      reason: 'Isolated attemptId writes must be immutable.',
    );
    expect(
      attemptIdRules,
      isNot(
        contains(
          "newData.isString() && root.child('users/' + root.child('rooms/'",
        ),
      ),
      reason: 'userA must not rewrite attemptId without clearing answer/ICE.',
    );
    expect(
      createdAtRules,
      contains('data.exists() && newData.val() === data.val()'),
      reason: 'Isolated createdAt writes must be immutable.',
    );
    expect(
      createdAtRules,
      isNot(
        contains(
          "newData.isNumber() && root.child('users/' + root.child('rooms/'",
        ),
      ),
      reason: 'userA must not rewrite createdAt without clearing answer/ICE.',
    );
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
    expect(
      rules,
      contains(
        "newData.val() === 'failed' && root.child('voiceCalls/' + \$callId + '/status').val() === 'ringing' && root.child('users/' + root.child('voiceCalls/' + \$callId + '/callee').val() + '/uid').val() === auth.uid",
      ),
      reason: 'Callee must be able to reject or busy an incoming ringing call.',
    );
    expect(rules, contains("newData.val() === 'negotiating'"));
    expect(rules, contains("newData.val() === 'connected'"));
    expect(
      rules,
      contains(
        "newData.val() === 'ended' && root.child('voiceCalls/' + \$callId + '/status').val() !== 'ended'",
      ),
    );
    expect(
      rules,
      contains(
        "root.child('activeVoicePairs/' + root.child('voiceCalls/' + \$callId + '/pairId').val() + '/callId').val() === \$callId",
      ),
      reason: 'Terminal ended writes must match the active call lock.',
    );
    expect(adapter, contains('_ensureVoiceRole'));
    expect(adapter, contains('VoiceCallRole.caller'));
    expect(adapter, contains('VoiceCallRole.callee'));
  });

  test('Firebase voice room participant fields are immutable after create', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final voiceCallsRules = _rulesSlice(
      rules,
      '"voiceCalls"',
      '"connectionRequests"',
    );

    for (final field in <String>[
      'pairId',
      'caller',
      'callee',
      'createdAt',
      'expiresAt',
    ]) {
      expect(
        voiceCallsRules,
        contains(
          '"$field": {\n          ".write": "auth != null && data.exists() && newData.val() === data.val()',
        ),
        reason: '$field must not be replaceable after call creation.',
      );
    }
  });

  test('Firebase voice room create rejects preseeded SDP and ICE branches', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final voiceCallsRules = _rulesSlice(
      rules,
      '"voiceCalls"',
      '"connectionRequests"',
    );

    expect(voiceCallsRules, contains("!newData.child('offer').exists()"));
    expect(voiceCallsRules, contains("!newData.child('answer').exists()"));
    expect(
      voiceCallsRules,
      contains("!newData.child('ice').exists()"),
      reason: 'Create must not be able to preseed caller or callee ICE.',
    );
    for (final field in <String>[
      'acceptedAt',
      'connectedAt',
      'endedAt',
      'endedBy',
      'reasonCode',
      'reason',
    ]) {
      expect(
        voiceCallsRules,
        contains("!newData.child('$field').exists()"),
        reason: '$field must not be accepted at call-room creation.',
      );
    }
    expect(
      voiceCallsRules,
      contains(
        "newData.child('muted').hasChildren([newData.child('caller').val(), newData.child('callee').val()])",
      ),
    );
    expect(
      voiceCallsRules,
      contains(
        "newData.child('muted/' + newData.child('caller').val()).val() === false",
      ),
    );
    expect(
      voiceCallsRules,
      contains(
        "newData.child('cameraMuted/' + newData.child('callee').val()).val() === false",
      ),
    );
  });

  test('Firebase voice inbox create is locked to ringing status', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final inboxRules = _rulesSlice(rules, '"voiceCallInboxes"', '"voiceCalls"');

    expect(
      inboxRules,
      contains("data.exists() || newData.child('status').val() === 'ringing'"),
    );
    expect(
      inboxRules,
      contains(
        ".validate\": \"!newData.exists() || (newData.hasChildren(['from', 'to', 'pairId', 'status', 'createdAt', 'updatedAt', 'expiresAt']) && (data.exists() || newData.child('status').val() === 'ringing')",
      ),
      reason: 'Non-ringing statuses may only be written after inbox creation.',
    );
  });

  test('Firebase active voice user locks cannot be deleted by stale calls', () {
    final rules = _repoFile('backend/firebase/database.rules.json');
    final activeVoiceUsersRules = _rulesSlice(
      rules,
      '"activeVoiceUsers"',
      '"voiceCallInboxes"',
    );

    expect(
      activeVoiceUsersRules,
      contains(
        "root.child('voiceCalls/' + data.child('callId').val() + '/pairId').val() === data.child('pairId').val()",
      ),
    );
    expect(
      activeVoiceUsersRules,
      contains(
        "root.child('voiceCalls/' + data.child('callId').val() + '/caller').val() === data.child('caller').val()",
      ),
    );
    expect(
      activeVoiceUsersRules,
      contains(
        "root.child('voiceCalls/' + data.child('callId').val() + '/callee').val() === data.child('callee').val()",
      ),
    );
    expect(
      activeVoiceUsersRules,
      contains(
        "root.child('voiceCalls/' + data.child('callId').val() + '/status').val() === 'ended'",
      ),
      reason: 'Newer non-terminal call locks must survive stale cleanup.',
    );
  });

  test(
    'Firebase expired missing-room user locks can be deleted by either side',
    () {
      final rules = _repoFile('backend/firebase/database.rules.json');
      final activeVoiceUsersRules = _rulesSlice(
        rules,
        '"activeVoiceUsers"',
        '"voiceCallInboxes"',
      );

      expect(
        activeVoiceUsersRules,
        contains(
          "!root.child('voiceCalls/' + data.child('callId').val()).exists() && (root.child('users/' + data.child('caller').val() + '/uid').val() === auth.uid || (data.child('expiresAt').val() <= now && root.child('users/' + data.child('callee').val() + '/uid').val() === auth.uid))",
        ),
        reason:
            'Expired missing-room locks must be cleanupable by the callee too; '
            'otherwise a reverse-direction retry can stay blocked forever.',
      );
    },
  );

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

String _rulesSlice(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  if (start < 0) {
    throw StateError('Missing rules marker: $startMarker');
  }
  final end = source.indexOf(endMarker, start + startMarker.length);
  if (end < 0) {
    throw StateError('Missing rules marker: $endMarker');
  }
  return source.substring(start, end);
}
