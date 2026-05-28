import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spark-safe connection request RTDB rules', () {
    late Map<String, Object?> rules;

    setUpAll(() {
      rules = _rulesRoot();
    });

    test('request row rules contain owner, friendship, and payload checks', () {
      final inbox = _node(rules, [
        'connectionRequests',
        r'$username',
        r'$requestId',
      ]);
      final outbox = _node(rules, [
        'connectionRequestOutboxes',
        r'$username',
        r'$requestId',
      ]);
      final inboxWrite = inbox['.write'] as String;
      final outboxWrite = outbox['.write'] as String;
      final inboxValidate = inbox['.validate'] as String;
      final outboxValidate = outbox['.validate'] as String;

      expect(
        inboxWrite,
        contains(
          "root.child('users/' + newData.child('from').val() + '/uid').val() === auth.uid",
        ),
      );
      expect(
        outboxWrite,
        contains(
          "root.child('users/' + newData.child('from').val() + '/uid').val() === auth.uid",
        ),
      );
      expect(
        inboxWrite,
        contains(
          "root.child('friendships/' + newData.child('from').val() + '/' + newData.child('to').val()).exists()",
        ),
      );
      expect(
        inboxWrite,
        contains(
          "root.child('friendships/' + newData.child('to').val() + '/' + newData.child('from').val()).exists()",
        ),
      );
      expect(
        inboxWrite,
        contains(
          "!root.child('blocks/' + newData.child('from').val() + '/' + newData.child('to').val()).exists()",
        ),
      );
      expect(
        inboxWrite,
        contains("newData.child('requestId').val() === \$requestId"),
      );
      expect(
        outboxWrite,
        contains("newData.child('from').val() === \$username"),
      );
      expect(
        inboxValidate,
        contains(
          "newData.child('pairKey').val() === newData.child('from').val() + ':' + newData.child('to').val()",
        ),
      );
      expect(
        outboxValidate,
        contains(
          "newData.child('expiresAt').val() - newData.child('createdAt').val() <= 90000",
        ),
      );
    });

    test(
      'terminal transitions are actor-scoped and terminal rows cannot be overwritten',
      () {
        final inboxWrite =
            _node(rules, [
                  'connectionRequests',
                  r'$username',
                  r'$requestId',
                ])['.write']
                as String;
        final outboxWrite =
            _node(rules, [
                  'connectionRequestOutboxes',
                  r'$username',
                  r'$requestId',
                ])['.write']
                as String;

        for (final writeRule in <String>[inboxWrite, outboxWrite]) {
          expect(
            writeRule,
            contains("data.child('status').val() !== 'accepted'"),
          );
          expect(
            writeRule,
            contains("data.child('status').val() !== 'rejected'"),
          );
          expect(
            writeRule,
            contains("data.child('status').val() !== 'canceled'"),
          );
          expect(
            writeRule,
            contains("newData.child('status').val() === 'seen'"),
          );
          expect(
            writeRule,
            contains(
              "root.child('users/' + data.child('to').val() + '/uid').val() === auth.uid",
            ),
          );
          expect(
            writeRule,
            contains("newData.child('status').val() === 'canceled'"),
          );
          expect(
            writeRule,
            contains(
              "root.child('users/' + data.child('from').val() + '/uid').val() === auth.uid",
            ),
          );
        }
      },
    );

    test('pair lock writes are narrow and request-id scoped', () {
      final pairLock = _node(rules, [
        'connectionRequestPairLocks',
        r'$pairKey',
      ]);
      final write = pairLock['.write'] as String;
      final validate = pairLock['.validate'] as String;

      expect(
        write,
        contains(
          "root.child('users/' + newData.child('from').val() + '/uid').val() === auth.uid",
        ),
      );
      expect(write, contains("newData.child('pairKey').val() === \$pairKey"));
      expect(write, contains("newData.child('status').val() === 'pending'"));
      expect(
        write,
        contains(
          "data.child('requestId').val() === newData.child('requestId').val()",
        ),
      );
      expect(
        write,
        contains(
          "data.exists() && !newData.exists() && data.child('status').val() === 'pending'",
        ),
      );
      expect(
        validate,
        contains(
          "newData.child('pairKey').val() === newData.child('from').val() + ':' + newData.child('to').val()",
        ),
      );
      expect(
        validate,
        contains(
          "newData.child('expiresAt').val() - newData.child('createdAt').val() <= 90000",
        ),
      );
    });

    test(
      'receiver-owned mute writes are allowed without opening admin paths',
      () {
        final mute = _node(rules, [
          'connectionNotificationMutes',
          r'$receiver',
          r'$sender',
        ]);

        expect(
          mute['.write'],
          contains(
            "root.child('users/' + \$receiver + '/uid').val() === auth.uid",
          ),
        );
        expect(
          mute['.validate'],
          contains("newData.child('muted').val() === true"),
        );
        expect(
          _node(rules, ['connectionNotificationEntitlements'])['.write'],
          isFalse,
        );
        expect(
          _node(rules, ['connectionNotificationReservations'])['.write'],
          isFalse,
        );
        expect(
          _node(rules, ['connectionNotificationAudit'])['.write'],
          isFalse,
        );
        expect(
          _node(rules, ['connectionNotificationAuditSummary'])['.write'],
          isFalse,
        );
        expect(
          _node(rules, [
            'connectionRequestQuotaSummaries',
            r'$username',
          ])['.write'],
          isFalse,
        );
      },
    );
  });
}

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
