import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain/infrastructure/services/turn_credential_service.dart';

void main() {
  test('Twilio native ice_servers response is normalized', () {
    final now = DateTime.utc(2026, 5, 17, 12);
    final result = parseTurnCredentialResponse(<String, dynamic>{
      'provider': 'twilio',
      'ttlSeconds': 1200,
      'ice_servers': <Map<String, Object?>>[
        <String, Object?>{'urls': 'stun:global.stun.twilio.com:3478'},
        <String, Object?>{
          'urls': <String>[
            'turn:global.turn.twilio.com:3478?transport=udp',
            'turn:global.turn.twilio.com:3478?transport=tcp',
            'turns:global.turn.twilio.com:443?transport=tcp',
          ],
          'username': 'temporary-user',
          'credential': 'temporary-secret',
        },
      ],
    }, now);

    expect(result.provider, 'twilio');
    expect(result.expiresAt, now.add(const Duration(minutes: 20)));
    expect(result.iceServers, hasLength(2));
    expect(
      result.iceServers.last['urls'],
      contains('turns:global.turn.twilio.com:443?transport=tcp'),
    );
  });

  test('Cloudflare native iceServers response is normalized', () {
    final now = DateTime.utc(2026, 5, 17, 12);
    final result = parseTurnCredentialResponse(<String, dynamic>{
      'provider': 'cloudflare',
      'ttlSeconds': 1200,
      'iceServers': <Map<String, Object?>>[
        <String, Object?>{
          'urls': <String>[
            'stun:stun.cloudflare.com:3478',
            'stun:stun.cloudflare.com:53',
          ],
        },
        <String, Object?>{
          'urls': <String>[
            'turn:turn.cloudflare.com:3478?transport=udp',
            'turn:turn.cloudflare.com:3478?transport=tcp',
            'turns:turn.cloudflare.com:443?transport=tcp',
          ],
          'username': 'temporary-user',
          'credential': 'temporary-secret',
        },
      ],
    }, now);

    expect(result.provider, 'cloudflare');
    expect(result.expiresAt, now.add(const Duration(minutes: 20)));
    expect(
      result.iceServers.last['urls'],
      contains('turns:turn.cloudflare.com:443?transport=tcp'),
    );
  });

  test('broker response without TURN URLs is rejected', () {
    expect(
      () => parseTurnCredentialResponse(<String, dynamic>{
        'provider': 'twilio',
        'iceServers': <Map<String, Object?>>[
          <String, Object?>{'urls': 'stun:stun.l.google.com:19302'},
        ],
      }, DateTime.utc(2026)),
      throwsFormatException,
    );
  });

  test('direct attempt can fall back to base STUN when broker fails', () async {
    final service = TurnCredentialService(
      brokerUrl: 'https://broker.example/rainTurnCredentials',
      baseIceServers: const <Map<String, dynamic>>[
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      ],
      credentialFetcher: () async {
        throw TimeoutException('broker timeout');
      },
    );

    final iceServers = await service.iceServers();

    expect(iceServers, hasLength(1));
    expect(iceServers.single['urls'], 'stun:stun.l.google.com:19302');
    expect(service.diagnostics.brokerConfigured, isTrue);
    expect(service.diagnostics.lastError, 'TURN broker unreachable.');

    service.dispose();
  });

  test(
    'relay-only fallback fails when broker credentials are unavailable',
    () async {
      final service = TurnCredentialService(
        brokerUrl: 'https://broker.example/rainTurnCredentials',
        baseIceServers: const <Map<String, dynamic>>[
          <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
        ],
        credentialFetcher: () async {
          throw Exception('TURN broker returned 401');
        },
      );

      await expectLater(
        service.iceServers(requireTurn: true),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'TURN broker returned 401. Relay fallback unavailable.',
          ),
        ),
      );

      service.dispose();
    },
  );

  test('static STUN-only builds cannot satisfy relay-only fallback', () async {
    final service = TurnCredentialService(
      brokerUrl: '',
      baseIceServers: const <Map<String, dynamic>>[
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      ],
    );

    await expectLater(
      service.iceServers(requireTurn: true),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          'Direct path blocked. No TURN relay is configured for this build.',
        ),
      ),
    );

    service.dispose();
  });

  test(
    'usable broker credentials are cached and merged after base STUN',
    () async {
      var fetchCount = 0;
      final now = DateTime.utc(2026, 5, 17, 12);
      final service = TurnCredentialService(
        brokerUrl: 'https://broker.example/rainTurnCredentials',
        now: () => now,
        baseIceServers: const <Map<String, dynamic>>[
          <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
        ],
        credentialFetcher: () async {
          fetchCount += 1;
          return TurnCredentialFetchResult(
            provider: 'twilio',
            expiresAt: now.add(const Duration(minutes: 20)),
            iceServers: const <Map<String, dynamic>>[
              <String, dynamic>{
                'urls': <String>[
                  'turn:global.turn.twilio.com:3478?transport=udp',
                  'turns:global.turn.twilio.com:443?transport=tcp',
                ],
                'username': 'temporary-user',
                'credential': 'temporary-secret',
              },
            ],
          );
        },
      );

      final first = await service.iceServers(requireTurn: true);
      final second = await service.iceServers(requireTurn: true);

      expect(fetchCount, 1);
      expect(first.first['urls'], 'stun:stun.l.google.com:19302');
      expect(first.last['username'], 'temporary-user');
      expect(second, first);
      expect(service.diagnostics.provider, 'twilio');
      expect(service.diagnostics.turnUrlCount, 2);

      service.dispose();
    },
  );
}
