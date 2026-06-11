/// # voice_call_rtdb_rules_contract_test.dart — protocol_brain package
///
/// Contract tests for voice call RTDB security rules ensuring proper access control for rooms, locks, ICE candidates, and inbox entries.
///
/// **Key types:** (no top-level types — test-only file)
///
/// **Package:** protocol_brain
///
/// **Depends on:** flutter_test, dart:convert, dart:io
///
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _rulesRoot() {
  final contents = _repoFile('backend/firebase/database.rules.json');
  final decoded = jsonDecode(contents) as Map<String, Object?>;
  return decoded['rules']! as Map<String, Object?>;
}

Map<String, Object?> _node(Map<String, Object?> root, List<String> path) {
  Object? current = root;
  for (final part in path) {
    if (current is! Map<String, Object?> || !current.containsKey(part)) {
      throw StateError('Missing Firebase rules path: ${path.join('/')}');
    }
    current = current[part];
  }
  if (current is! Map<String, Object?>) {
    throw StateError('Firebase rules path is not an object: ${path.join('/')}');
  }
  return current;
}

String _repoFile(String relativePath) {
  // When run via melos, cwd is the workspace root.
  // When run directly, try to find the workspace root.
  final cwd = Directory.current;
  final candidates = [cwd, cwd.parent, cwd.parent.parent];
  for (final dir in candidates) {
    final f = File('${dir.path}/$relativePath');
    if (f.existsSync()) return f.readAsStringSync().replaceAll('\r\n', '\n');
  }
  // Fallback: try the path relative to this file
  final scriptDir = Directory(Platform.script.toFilePath()).parent;
  final fallback = File('${scriptDir.path}/../../../$relativePath');
  if (fallback.existsSync()) {
    return fallback.readAsStringSync().replaceAll('\r\n', '\n');
  }
  throw StateError('Could not find $relativePath from ${cwd.path}');
}

void main() {
  group('Voice call RTDB rules contract', () {
    late Map<String, Object?> rules;

    setUpAll(() {
      rules = _rulesRoot();
    });

    group('voiceCalls', () {
      test(
        'validate requires v, pairId, caller, callee, status, createdAt, updatedAt, expiresAt',
        () {
          final validate =
              _node(rules, ['voiceCalls', r'$callId'])['.validate'] as String;
          expect(
            validate,
            contains(
              "newData.hasChildren(['v', 'pairId', 'caller', 'callee', 'status', 'createdAt', 'updatedAt', 'expiresAt'])",
            ),
          );
        },
      );

      test('validate requires v === 1', () {
        final validate =
            _node(rules, ['voiceCalls', r'$callId'])['.validate'] as String;
        expect(validate, contains("newData.child('v').val() === 1"));
      });

      test('status write requires caller or callee auth', () {
        final statusWrite =
            _node(rules, ['voiceCalls', r'$callId', 'status'])['.write']
                as String;
        expect(
          statusWrite,
          contains("root.child('voiceCalls/' + \$callId).exists()"),
        );
        expect(
          statusWrite,
          contains(
            "root.child('users/' + root.child('voiceCalls/' + \$callId + '/caller').val() + '/uid').val() === auth.uid",
          ),
        );
        expect(
          statusWrite,
          contains(
            "root.child('users/' + root.child('voiceCalls/' + \$callId + '/callee').val() + '/uid').val() === auth.uid",
          ),
        );
      });

      test('status write enforces valid transitions', () {
        final statusWrite =
            _node(rules, ['voiceCalls', r'$callId', 'status'])['.write']
                as String;
        // Callee accepts from ringing
        expect(
          statusWrite,
          contains(
            "newData.val() === 'accepted' && root.child('voiceCalls/' + \$callId + '/status').val() === 'ringing'",
          ),
        );
        // Either party can end from non-terminal
        expect(
          statusWrite,
          contains(
            "newData.val() === 'ended' && root.child('voiceCalls/' + \$callId + '/status').val() !== 'ended'",
          ),
        );
        // Failed from ringing by callee
        expect(
          statusWrite,
          contains(
            "newData.val() === 'failed' && root.child('voiceCalls/' + \$callId + '/status').val() === 'ringing'",
          ),
        );
        // Negotiating by caller from accepted/negotiating
        expect(statusWrite, contains("newData.val() === 'negotiating'"));
      });

      test('delete requires write permission from either participant', () {
        final write =
            _node(rules, ['voiceCalls', r'$callId'])['.write'] as String;
        expect(write, contains("!newData.exists()"));
        expect(
          write,
          contains(
            "root.child('users/' + data.child('caller').val() + '/uid').val() === auth.uid",
          ),
        );
        expect(
          write,
          contains(
            "root.child('users/' + data.child('callee').val() + '/uid').val() === auth.uid",
          ),
        );
      });

      test('reasonCode and reason have max length validation', () {
        final reasonCodeValidate =
            _node(rules, ['voiceCalls', r'$callId', 'reasonCode'])['.validate']
                as String;
        final reasonValidate =
            _node(rules, ['voiceCalls', r'$callId', 'reason'])['.validate']
                as String;
        expect(reasonCodeValidate, contains("newData.val().length <= 48"));
        expect(reasonValidate, contains("newData.val().length <= 256"));
      });

      test('muted write requires the authenticated user to be the muted user', () {
        final mutedWrite =
            _node(rules, [
                  'voiceCalls',
                  r'$callId',
                  'muted',
                  r'$username',
                ])['.write']
                as String;
        expect(
          mutedWrite,
          contains(
            "root.child('users/' + \$username + '/uid').val() === auth.uid",
          ),
        );
        expect(
          mutedWrite,
          contains(
            "\$username === root.child('voiceCalls/' + \$callId + '/caller').val()",
          ),
        );
        expect(
          mutedWrite,
          contains(
            "\$username === root.child('voiceCalls/' + \$callId + '/callee').val()",
          ),
        );
      });

      test(
        'cameraMuted write requires the authenticated user to be the muted user',
        () {
          final cameraMutedWrite =
              _node(rules, [
                    'voiceCalls',
                    r'$callId',
                    'cameraMuted',
                    r'$username',
                  ])['.write']
                  as String;
          expect(
            cameraMutedWrite,
            contains(
              "root.child('users/' + \$username + '/uid').val() === auth.uid",
            ),
          );
        },
      );

      test('acceptedAt write requires status === ringing and callee auth', () {
        final acceptedAtWrite =
            _node(rules, ['voiceCalls', r'$callId', 'acceptedAt'])['.write']
                as String;
        expect(
          acceptedAtWrite,
          contains(
            "root.child('voiceCalls/' + \$callId + '/status').val() === 'ringing'",
          ),
        );
        expect(
          acceptedAtWrite,
          contains(
            "root.child('users/' + root.child('voiceCalls/' + \$callId + '/callee').val() + '/uid').val() === auth.uid",
          ),
        );
      });

      test('endedAt write requires status not terminal', () {
        final endedAtWrite =
            _node(rules, ['voiceCalls', r'$callId', 'endedAt'])['.write']
                as String;
        expect(
          endedAtWrite,
          contains(
            "root.child('voiceCalls/' + \$callId + '/status').val() !== 'ended'",
          ),
        );
        expect(
          endedAtWrite,
          contains(
            "root.child('voiceCalls/' + \$callId + '/status').val() !== 'failed'",
          ),
        );
        expect(
          endedAtWrite,
          contains(
            "root.child('voiceCalls/' + \$callId + '/status').val() !== 'expired'",
          ),
        );
      });

      test('endedBy write requires the endedBy user to be authenticated', () {
        final endedByWrite =
            _node(rules, ['voiceCalls', r'$callId', 'endedBy'])['.write']
                as String;
        expect(
          endedByWrite,
          contains(
            "root.child('users/' + newData.val() + '/uid').val() === auth.uid",
          ),
        );
        expect(
          endedByWrite,
          contains(
            "newData.val() === root.child('voiceCalls/' + \$callId + '/caller').val()",
          ),
        );
        expect(
          endedByWrite,
          contains(
            "newData.val() === root.child('voiceCalls/' + \$callId + '/callee').val()",
          ),
        );
      });
    });

    group('activeVoicePairs', () {
      test('write requires caller auth, online callee, and friendship', () {
        final write =
            _node(rules, ['activeVoicePairs', r'$pairId'])['.write'] as String;
        expect(
          write,
          contains(
            "root.child('users/' + newData.child('caller').val() + '/uid').val() === auth.uid",
          ),
        );
        expect(
          write,
          contains(
            "root.child('presence/' + newData.child('callee').val() + '/online').val() === true",
          ),
        );
        expect(
          write,
          contains(
            "root.child('friendships/' + newData.child('caller').val() + '/' + newData.child('callee').val()).exists()",
          ),
        );
      });

      test('re-write requires stale expiry (reclaim path)', () {
        final write =
            _node(rules, ['activeVoicePairs', r'$pairId'])['.write'] as String;
        expect(write, contains("data.child('expiresAt').val() <= now"));
      });

      test('delete requires either participant auth', () {
        final write =
            _node(rules, ['activeVoicePairs', r'$pairId'])['.write'] as String;
        expect(write, contains("!newData.exists()"));
        expect(
          write,
          contains(
            "root.child('users/' + data.child('caller').val() + '/uid').val() === auth.uid",
          ),
        );
        expect(
          write,
          contains(
            "root.child('users/' + data.child('callee').val() + '/uid').val() === auth.uid",
          ),
        );
      });

      test('validate requires callId length limit', () {
        final validate =
            _node(rules, ['activeVoicePairs', r'$pairId'])['.validate']
                as String;
        expect(
          validate,
          contains("newData.child('callId').val().length <= 128"),
        );
      });
    });

    group('activeVoiceUsers', () {
      test('write requires caller auth and callee online', () {
        final write =
            _node(rules, ['activeVoiceUsers', r'$username'])['.write']
                as String;
        expect(
          write,
          contains(
            "root.child('users/' + newData.child('caller').val() + '/uid').val() === auth.uid",
          ),
        );
        expect(
          write,
          contains(
            "root.child('presence/' + newData.child('callee').val() + '/online').val() === true",
          ),
        );
      });

      test('write requires the lock to be owned by \$username', () {
        final write =
            _node(rules, ['activeVoiceUsers', r'$username'])['.write']
                as String;
        expect(write, contains("newData.child('caller').val() === \$username"));
        expect(write, contains("newData.child('callee').val() === \$username"));
      });

      test('validate requires callId and pairId', () {
        final validate =
            _node(rules, ['activeVoiceUsers', r'$username'])['.validate']
                as String;
        expect(
          validate,
          contains(
            "newData.hasChildren(['callId', 'pairId', 'caller', 'callee', 'createdAt', 'updatedAt', 'expiresAt'])",
          ),
        );
        expect(
          validate,
          contains("newData.child('callId').val().length <= 128"),
        );
        expect(validate, contains("newData.child('pairId').isString()"));
      });
    });

    group('voiceCallInboxes', () {
      test('write requires from or to to be authenticated', () {
        final write =
            _node(rules, [
                  'voiceCallInboxes',
                  r'$username',
                  r'$callId',
                ])['.write']
                as String;
        expect(
          write,
          contains(
            "root.child('users/' + newData.child('from').val() + '/uid').val() === auth.uid",
          ),
        );
        expect(
          write,
          contains(
            "root.child('users/' + newData.child('to').val() + '/uid').val() === auth.uid",
          ),
        );
      });

      test('validate requires to === \$username for incoming', () {
        final validate =
            _node(rules, [
                  'voiceCallInboxes',
                  r'$username',
                  r'$callId',
                ])['.validate']
                as String;
        expect(validate, contains("newData.child('to').val() === \$username"));
      });

      test('validate restricts status values', () {
        final validate =
            _node(rules, [
                  'voiceCallInboxes',
                  r'$username',
                  r'$callId',
                ])['.validate']
                as String;
        expect(
          validate,
          contains("newData.child('status').val() === 'ringing'"),
        );
        expect(
          validate,
          contains("newData.child('status').val() === 'accepted'"),
        );
        expect(validate, contains("newData.child('status').val() === 'ended'"));
        expect(
          validate,
          contains("newData.child('status').val() === 'failed'"),
        );
      });

      test('validate requires from !== to', () {
        final validate =
            _node(rules, [
                  'voiceCallInboxes',
                  r'$username',
                  r'$callId',
                ])['.validate']
                as String;
        expect(
          validate,
          contains("newData.child('from').val() !== newData.child('to').val()"),
        );
      });
    });

    group('rooms', () {
      test('write requires userA < userB ordering', () {
        final write = _node(rules, ['rooms', r'$roomId'])['.write'] as String;
        expect(
          write,
          contains(
            "newData.child('userA').val() < newData.child('userB').val()",
          ),
        );
      });

      test('write requires roomId === userA:userB', () {
        final write = _node(rules, ['rooms', r'$roomId'])['.write'] as String;
        expect(
          write,
          contains(
            "newData.child('userA').val() + ':' + newData.child('userB').val() === \$roomId",
          ),
        );
      });

      test('callerICE write requires userA auth', () {
        final write =
            _node(rules, [
                  'rooms',
                  r'$roomId',
                  'callerICE',
                  r'$candidateId',
                ])['.write']
                as String;
        expect(
          write,
          contains(
            "root.child('users/' + root.child('rooms/' + \$roomId + '/userA').val() + '/uid').val() === auth.uid",
          ),
        );
      });

      test('calleeICE write requires userB auth', () {
        final write =
            _node(rules, [
                  'rooms',
                  r'$roomId',
                  'calleeICE',
                  r'$candidateId',
                ])['.write']
                as String;
        expect(
          write,
          contains(
            "root.child('users/' + root.child('rooms/' + \$roomId + '/userB').val() + '/uid').val() === auth.uid",
          ),
        );
      });

      test('offer write requires userA auth', () {
        final write =
            _node(rules, ['rooms', r'$roomId', 'offer'])['.write'] as String;
        expect(
          write,
          contains(
            "root.child('users/' + root.child('rooms/' + \$roomId + '/userA').val() + '/uid').val() === auth.uid",
          ),
        );
      });

      test('answer write requires userB auth', () {
        final write =
            _node(rules, ['rooms', r'$roomId', 'answer'])['.write'] as String;
        expect(
          write,
          contains(
            "root.child('users/' + root.child('rooms/' + \$roomId + '/userB').val() + '/uid').val() === auth.uid",
          ),
        );
      });

      test('create disallows answer, callerICE, calleeICE', () {
        final write = _node(rules, ['rooms', r'$roomId'])['.write'] as String;
        expect(write, contains("!newData.child('answer').exists()"));
        expect(write, contains("!newData.child('callerICE').exists()"));
        expect(write, contains("!newData.child('calleeICE').exists()"));
      });

      test('update disallows answer, callerICE, calleeICE', () {
        final write = _node(rules, ['rooms', r'$roomId'])['.write'] as String;
        expect(write, contains("!newData.child('answer').exists()"));
        expect(write, contains("!newData.child('callerICE').exists()"));
        expect(write, contains("!newData.child('calleeICE').exists()"));
      });
    });

    group('presence', () {
      test('write requires matching uid', () {
        final write =
            _node(rules, ['presence', r'$username'])['.write'] as String;
        expect(
          write,
          contains(
            "root.child('users/' + \$username + '/uid').val() === auth.uid",
          ),
        );
        expect(write, contains("newData.child('uid').val() === auth.uid"));
      });

      test('write prevents startedAt from going backwards', () {
        final write =
            _node(rules, ['presence', r'$username'])['.write'] as String;
        expect(
          write,
          contains(
            "newData.child('startedAt').val() >= data.child('startedAt').val()",
          ),
        );
      });

      test('validate requires all mandatory presence fields', () {
        final validate =
            _node(rules, ['presence', r'$username'])['.validate'] as String;
        expect(
          validate,
          contains(
            "newData.hasChildren(['uid', 'online', 'lastHeartbeat', 'lastSeen', 'updatedAt', 'sessionId', 'platform'])",
          ),
        );
      });
    });

    group('users', () {
      test('write requires email match', () {
        final write = _node(rules, ['users', r'$username'])['.write'] as String;
        expect(
          write,
          contains("auth.token.email === \$username + '@rain.local'"),
        );
      });

      test('write requires uid match on existing rows', () {
        final write = _node(rules, ['users', r'$username'])['.write'] as String;
        expect(write, contains("data.child('uid').val() === auth.uid"));
      });

      test('write allows legacy rows without uid to be claimed', () {
        final write = _node(rules, ['users', r'$username'])['.write'] as String;
        expect(write, contains("!data.child('uid').exists()"));
      });

      test('validate restricts extra fields', () {
        final validate = _node(rules, [
          'users',
          r'$username',
          r'$other',
        ])['.validate'];
        expect(validate, isFalse);
      });
    });
  });
}
