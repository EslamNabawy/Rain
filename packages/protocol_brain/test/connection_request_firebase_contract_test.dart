import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('connection request Firebase security boundaries', () {
    late Map<String, Object?> rules;

    setUpAll(() {
      rules = _rulesRoot();
    });

    test('clients can read only their own request inbox and outbox', () {
      final inboxUser = _node(rules, ['connectionRequests', r'$username']);
      final outboxUser = _node(rules, [
        'connectionRequestOutboxes',
        r'$username',
      ]);

      expect(inboxUser['.read'], _ownUserReadRule(r'$username'));
      expect(outboxUser['.read'], _ownUserReadRule(r'$username'));
      expect(inboxUser['.read'], isNot('auth != null'));
      expect(outboxUser['.read'], isNot('auth != null'));
      expect(inboxUser['.write'], isFalse);
      expect(outboxUser['.write'], isFalse);
      expect(
        inboxUser['.indexOn'],
        containsAll(<String>['expiresAt', 'status']),
      );
      expect(
        outboxUser['.indexOn'],
        containsAll(<String>['expiresAt', 'status']),
      );
    });

    test('authenticated users can only write guarded request rows', () {
      final inboxWrite = _node(rules, [
        'connectionRequests',
        r'$username',
        r'$requestId',
      ])['.write'];
      final outboxWrite = _node(rules, [
        'connectionRequestOutboxes',
        r'$username',
        r'$requestId',
      ])['.write'];

      expect(
        _node(rules, ['connectionRequests', r'$username'])['.write'],
        isFalse,
      );
      expect(
        _node(rules, ['connectionRequestOutboxes', r'$username'])['.write'],
        isFalse,
      );
      expect(inboxWrite, isA<String>());
      expect(outboxWrite, isA<String>());
      expect(
        inboxWrite,
        contains(
          "root.child('users/' + newData.child('from').val() + '/uid').val() === auth.uid",
        ),
      );
      expect(
        outboxWrite,
        contains("newData.child('from').val() === \$username"),
      );
      expect(
        inboxWrite,
        contains(
          "root.child('friendships/' + newData.child('from').val() + '/' + newData.child('to').val()).exists()",
        ),
      );
      expect(
        outboxWrite,
        contains(
          "root.child('connectionRequestPairLocks/' + newData.child('pairKey').val() + '/requestId').val() === \$requestId",
        ),
      );
    });

    test('authenticated users cannot grant themselves credits', () {
      expect(
        _node(rules, ['connectionNotificationEntitlements'])['.write'],
        isFalse,
      );
      expect(
        _node(rules, ['connectionNotificationEntitlements'])['.read'],
        isFalse,
      );
      expect(_node(rules, ['connectionNotificationConfig'])['.write'], isFalse);
    });

    test('authenticated users cannot reset usage counters', () {
      expect(_node(rules, ['connectionNotificationUsage'])['.write'], isFalse);
      expect(
        _node(rules, ['connectionNotificationTargetUsage'])['.write'],
        isFalse,
      );
      expect(_node(rules, ['connectionNotificationUsage'])['.read'], isFalse);
      expect(
        _node(rules, ['connectionNotificationTargetUsage'])['.read'],
        isFalse,
      );
    });

    test('pair locks are guarded and reservations stay denied', () {
      expect(_node(rules, ['connectionRequestPairLocks'])['.write'], isFalse);
      expect(
        _node(rules, ['connectionRequestPairLocks', r'$pairKey'])['.write'],
        isA<String>(),
      );
      expect(
        _node(rules, ['connectionNotificationReservations'])['.write'],
        isFalse,
      );
      expect(
        _node(rules, ['connectionRequestPairLocks'])['.indexOn'],
        containsAll(<String>['expiresAt', 'status']),
      );
      expect(
        _node(rules, ['connectionNotificationReservations'])['.indexOn'],
        containsAll(<String>['expiresAt', 'finalized']),
      );
    });

    test('users can read sanitized quota summary only for themselves', () {
      final summary = _node(rules, [
        'connectionRequestQuotaSummaries',
        r'$username',
      ]);

      expect(summary['.read'], _ownUserReadRule(r'$username'));
      expect(summary['.write'], isFalse);
    });

    test('connection notification mutes are receiver-owned', () {
      final receiver = _node(rules, [
        'connectionNotificationMutes',
        r'$receiver',
      ]);
      final sender = _node(rules, [
        'connectionNotificationMutes',
        r'$receiver',
        r'$sender',
      ]);

      expect(receiver['.read'], _ownUserReadRule(r'$receiver'));
      expect(receiver['.write'], isFalse);
      expect(sender['.write'], isA<String>());
      expect(
        sender['.write'],
        contains(
          "root.child('users/' + \$receiver + '/uid').val() === auth.uid",
        ),
      );
    });

    test(
      'audit and global config are not client-readable mutation surfaces',
      () {
        for (final path in <String>[
          'connectionNotificationAudit',
          'connectionNotificationAuditSummary',
          'connectionNotificationConfig',
        ]) {
          final node = _node(rules, [path]);
          expect(node['.read'], isFalse, reason: path);
          expect(node['.write'], isFalse, reason: path);
        }
      },
    );

    test('README documents the Spark-safe connection request paths', () {
      final readme = _repoFile('backend/firebase/README.md');

      for (final path in <String>[
        'connectionRequests/<username>/<requestId>',
        'connectionRequestOutboxes/<username>/<requestId>',
        'connectionRequestQuotaSummaries/<username>',
        'connectionRequestPairLocks/<pairKey>',
        'connectionNotificationEntitlements/<username>',
        'connectionNotificationUsage/<username>/<yyyyMMddUtc>',
        'connectionNotificationTargetUsage/<from>/<to>/<yyyyMMddUtc>',
        'connectionNotificationMutes/<receiver>/<sender>',
        'connectionNotificationAudit/<yyyyMMddUtc>/<eventId>',
        'connectionNotificationAuditSummary/<yyyyMMddUtc>',
        'connectionNotificationReservations/<requestId>',
      ]) {
        expect(readme, contains(path), reason: path);
      }
    });
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

String _ownUserReadRule(String variableName) {
  return "auth != null && root.child('users/' + $variableName + '/uid').val() === auth.uid";
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
