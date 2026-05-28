import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

void main() {
  group('Connection request contract', () {
    test('normalizes pair keys without path injection', () {
      expect(
        connectionRequestPairKey(' Alice_01 ', 'BOB_02'),
        'alice_01:bob_02',
      );
      expect(
        () => connectionRequestPairKey('alice/../../root', 'bob'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => connectionRequestPairKey('alice', 'Alice'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => validateConnectionRequestId('request/evil'),
        throwsA(isA<FormatException>()),
      );
      expect(validateConnectionRequestId('request-01_ok'), 'request-01_ok');
    });

    test('parses payloads, ignores unknown fields, and detects expiration', () {
      final payload = ConnectionRequestPayload.fromJson(
        requestId: 'request-01',
        json: <Object?, Object?>{
          'v': 1,
          'requestId': 'request-01',
          'from': 'alice_01',
          'to': 'bob_02',
          'pairKey': 'alice_01:bob_02',
          'status': 'pending',
          'createdAt': 1000,
          'updatedAt': 1200,
          'expiresAt': 5000,
          'senderPresenceAt': 950,
          'receiverPresenceAt': 960,
          'unknownFutureField': 'ignored',
        },
      );

      expect(payload.from, 'alice_01');
      expect(payload.to, 'bob_02');
      expect(payload.status, ConnectionRequestStatus.pending);
      expect(payload.isExpiredAt(4999), isFalse);
      expect(payload.isExpiredAt(5000), isTrue);
    });

    test('rejects malformed status and invalid timestamps', () {
      expect(
        () => ConnectionRequestPayload.fromJson(
          requestId: 'request-01',
          json: _payloadJson(status: 'ringing'),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ConnectionRequestPayload.fromJson(
          requestId: 'request-01',
          json: _payloadJson(updatedAt: 999),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ConnectionRequestPayload.fromJson(
          requestId: 'request-01',
          json: _payloadJson(expiresAt: 1000),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects path-injection usernames during payload parse', () {
      expect(
        () => ConnectionRequestPayload.fromJson(
          requestId: 'request-01',
          json: _payloadJson(from: 'Alice'),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ConnectionRequestPayload.fromJson(
          requestId: 'request-01',
          json: _payloadJson(from: 'alice/evil'),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ConnectionRequestPayload.fromJson(
          requestId: 'request-01',
          json: _payloadJson(pairKey: 'alice/evil:bob'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('cleanup-safe parser survives corrupt payloads', () {
      final cleanup = ConnectionRequestPayload.tryParseForCleanup(
        requestId: 'request-01',
        json: <Object?, Object?>{
          'from': 'Alice_01',
          'to': 'Bob_02',
          'pairKey': 'not-used-for-corrupt-payload',
          'status': 'not-real',
          'createdAt': 'bad',
          'updatedAt': 1,
          'expiresAt': 2,
        },
      );

      expect(cleanup, isNotNull);
      expect(cleanup!.pairKey, 'alice_01:bob_02');
      expect(cleanup.status, isNull);

      expect(
        ConnectionRequestPayload.tryParseForCleanup(
          requestId: 'request-01',
          json: <Object?, Object?>{'from': '../alice', 'to': 'bob'},
        ),
        isNull,
      );
    });

    test('maps every reason code to a non-empty user-facing message', () {
      for (final reasonCode in ConnectionRequestReasonCode.values) {
        final message = messageForConnectionRequestReason(
          reasonCode,
          '@bob',
          const Duration(seconds: 12),
        );

        expect(message, isNotEmpty, reason: reasonCode.name);
        expect(message, isNot(contains('null')), reason: reasonCode.name);
      }

      expect(
        messageForConnectionRequestReason(
          ConnectionRequestReasonCode.rateLimited,
          'bob',
          const Duration(seconds: 12),
        ),
        contains('12s'),
      );
    });

    test('allows every server-owned transition from the spec', () {
      const allowed = <ConnectionRequestTransition>[
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.pending,
          to: ConnectionRequestStatus.seen,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.pending,
          to: ConnectionRequestStatus.accepted,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.pending,
          to: ConnectionRequestStatus.rejected,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.pending,
          to: ConnectionRequestStatus.canceled,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.pending,
          to: ConnectionRequestStatus.expired,
          now: 2000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.pending,
          to: ConnectionRequestStatus.failed,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.seen,
          to: ConnectionRequestStatus.accepted,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.seen,
          to: ConnectionRequestStatus.rejected,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.seen,
          to: ConnectionRequestStatus.canceled,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.seen,
          to: ConnectionRequestStatus.expired,
          now: 2000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.seen,
          to: ConnectionRequestStatus.failed,
          now: 1000,
          expiresAt: 2000,
        ),
      ];

      for (final transition in allowed) {
        expect(
          transition.allowed,
          isTrue,
          reason: '${transition.from.name} -> ${transition.to.name}',
        );
      }
    });

    test('rejects forbidden and expired accept transitions', () {
      const forbidden = <ConnectionRequestTransition>[
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.accepted,
          to: ConnectionRequestStatus.pending,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.rejected,
          to: ConnectionRequestStatus.accepted,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.canceled,
          to: ConnectionRequestStatus.accepted,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.expired,
          to: ConnectionRequestStatus.accepted,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.failed,
          to: ConnectionRequestStatus.accepted,
          now: 1000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.pending,
          to: ConnectionRequestStatus.accepted,
          now: 2000,
          expiresAt: 2000,
        ),
        ConnectionRequestTransition(
          from: ConnectionRequestStatus.seen,
          to: ConnectionRequestStatus.pending,
          now: 1000,
          expiresAt: 2000,
        ),
      ];

      for (final transition in forbidden) {
        expect(
          transition.allowed,
          isFalse,
          reason: '${transition.from.name} -> ${transition.to.name}',
        );
      }
    });

    test('terminal helper covers the status enum', () {
      expect(isTerminalStatus(ConnectionRequestStatus.pending), isFalse);
      expect(isTerminalStatus(ConnectionRequestStatus.seen), isFalse);
      expect(isTerminalStatus(ConnectionRequestStatus.accepted), isTrue);
      expect(isTerminalStatus(ConnectionRequestStatus.rejected), isTrue);
      expect(isTerminalStatus(ConnectionRequestStatus.canceled), isTrue);
      expect(isTerminalStatus(ConnectionRequestStatus.expired), isTrue);
      expect(isTerminalStatus(ConnectionRequestStatus.failed), isTrue);
    });
  });
}

Map<Object?, Object?> _payloadJson({
  String from = 'alice',
  String to = 'bob',
  String pairKey = 'alice:bob',
  String status = 'pending',
  int createdAt = 1000,
  int updatedAt = 1200,
  int expiresAt = 5000,
}) {
  return <Object?, Object?>{
    'v': 1,
    'requestId': 'request-01',
    'from': from,
    'to': to,
    'pairKey': pairKey,
    'status': status,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'expiresAt': expiresAt,
  };
}
