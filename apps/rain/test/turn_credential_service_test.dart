import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
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

  test('broker TURN response accepts UDP TCP and TURNS TCP coverage', () {
    final now = DateTime.utc(2026, 5, 19);
    final result = parseTurnCredentialResponse(<String, dynamic>{
      'provider': 'test',
      'ttlSeconds': 1200,
      'iceServers': <Map<String, Object?>>[
        <String, Object?>{
          'urls': <String>[
            'turn:relay.example.com:3478?transport=udp',
            'turn:relay.example.com:3478?transport=tcp',
            'turns:relay.example.com:5349?transport=tcp',
          ],
          'username': 'u',
          'credential': 'p',
        },
      ],
    }, now);

    final urls = _allUrls(result.iceServers);
    expect(result.provider, 'test');
    expect(urls, contains('turn:relay.example.com:3478?transport=udp'));
    expect(urls, contains('turn:relay.example.com:3478?transport=tcp'));
    expect(urls, contains('turns:relay.example.com:5349?transport=tcp'));
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
    expect(
      service.diagnostics.lastError,
      'Relay unavailable. Direct connection only.',
    );
    expect(
      service.diagnostics.errorCode,
      TurnCredentialErrorCode.brokerUnreachable,
    );

    service.dispose();
  });

  test(
    'staged direct attempt is STUN-only even when OpenRelay is configured',
    () async {
      final service = TurnCredentialService(
        brokerUrl: '',
        baseIceServers: const <Map<String, dynamic>>[
          <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
          <String, dynamic>{
            'urls': <String>[
              'turn:openrelay.metered.ca:80?transport=udp',
              'turns:openrelay.metered.ca:443?transport=tcp',
            ],
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
      );

      final iceServers = await service.iceServersForAttempt(
        const IceAttemptDescriptor(
          stage: IceAttemptStage.directStunOnly,
          policy: PeerIceTransportPolicy.all,
          providerTier: IceProviderTier.stunOnly,
          providerId: 'stun-pool',
          timeout: Duration(seconds: 12),
          connectAttemptId: 'attempt-0',
          attemptIndex: 0,
        ),
      );

      final urls = _allUrls(iceServers);
      expect(urls, contains('stun:stun.l.google.com:19302'));
      expect(urls, contains('stun:stun.services.mozilla.com:3478'));
      expect(urls.any((String url) => url.startsWith('turn')), isFalse);

      service.dispose();
    },
  );

  test(
    'primary relay requires broker TURN and never silently returns STUN only',
    () async {
      final service = TurnCredentialService(
        brokerUrl: '',
        baseIceServers: const <Map<String, dynamic>>[
          <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
        ],
      );

      await expectLater(
        service.iceServersForAttempt(
          const IceAttemptDescriptor(
            stage: IceAttemptStage.primaryRelay,
            policy: PeerIceTransportPolicy.relayOnly,
            providerTier: IceProviderTier.primaryRelay,
            providerId: 'primary-relay',
            timeout: Duration(seconds: 30),
            connectAttemptId: 'attempt-1',
            attemptIndex: 1,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'Relay credentials unavailable.',
          ),
        ),
      );

      service.dispose();
    },
  );

  test('backup relay attempt uses OpenRelay only after direct stage', () async {
    final service = TurnCredentialService(
      brokerUrl: '',
      baseIceServers: const <Map<String, dynamic>>[
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
        <String, dynamic>{
          'urls': <String>[
            'turn:openrelay.metered.ca:80?transport=udp',
            'turns:openrelay.metered.ca:443?transport=tcp',
          ],
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
      ],
    );

    final iceServers = await service.iceServersForAttempt(
      const IceAttemptDescriptor(
        stage: IceAttemptStage.backupRelay,
        policy: PeerIceTransportPolicy.relayOnly,
        providerTier: IceProviderTier.backupRelay,
        providerId: 'backup-relay',
        timeout: Duration(seconds: 20),
        connectAttemptId: 'attempt-2',
        attemptIndex: 2,
      ),
    );

    final urls = _allUrls(iceServers);
    expect(urls, contains('turn:openrelay.metered.ca:80?transport=udp'));
    expect(urls, contains('turns:openrelay.metered.ca:443?transport=tcp'));
    expect(service.diagnostics.provider, 'openRelay');

    service.dispose();
  });

  test('experimental relay attempt is disabled by default', () async {
    final service = TurnCredentialService(
      brokerUrl: '',
      baseIceServers: const <Map<String, dynamic>>[
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      ],
    );

    await expectLater(
      service.iceServersForAttempt(
        const IceAttemptDescriptor(
          stage: IceAttemptStage.experimentalRelay,
          policy: PeerIceTransportPolicy.relayOnly,
          providerTier: IceProviderTier.experimentalRelay,
          providerId: 'experimental-relay',
          timeout: Duration(seconds: 20),
          connectAttemptId: 'attempt-3',
          attemptIndex: 3,
        ),
      ),
      throwsA(isA<StateError>()),
    );

    service.dispose();
  });

  test('failed relay provider enters local cooldown', () async {
    final metrics = MemoryIceMetricsStore();
    final now = DateTime.utc(2026, 5, 17, 12);
    final service = TurnCredentialService(
      brokerUrl: '',
      now: () => now,
      metricsStore: metrics,
      baseIceServers: const <Map<String, dynamic>>[
        <String, dynamic>{
          'urls': <String>['turn:openrelay.metered.ca:80?transport=udp'],
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
      ],
    );
    const attempt = IceAttemptDescriptor(
      stage: IceAttemptStage.backupRelay,
      policy: PeerIceTransportPolicy.relayOnly,
      providerTier: IceProviderTier.backupRelay,
      providerId: 'backup-relay',
      timeout: Duration(seconds: 20),
      connectAttemptId: 'attempt-2',
      attemptIndex: 2,
    );

    service.recordAttemptResult(
      IceAttemptResult(
        attempt: attempt,
        succeeded: false,
        completedAt: now,
        failureReason: 'Relay provider timed out.',
      ),
    );

    await expectLater(
      service.iceServersForAttempt(attempt),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          'Relay provider unavailable.',
        ),
      ),
    );

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
            'Relay authorization failed. Sign in again. Relay fallback unavailable.',
          ),
        ),
      );
      expect(
        service.diagnostics.errorCode,
        TurnCredentialErrorCode.brokerAuthFailed,
      );
      expect(service.diagnostics.lastError, isNot(contains('401')));

      service.dispose();
    },
  );

  test('broker 429 maps to rate limit message without raw status', () async {
    final service = TurnCredentialService(
      brokerUrl: 'https://broker.example/rainTurnCredentials',
      baseIceServers: const <Map<String, dynamic>>[
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      ],
      credentialFetcher: () async {
        throw Exception('TURN broker returned 429');
      },
    );

    await expectLater(
      service.iceServers(requireTurn: true),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          'Relay is rate limited. Try again later. Relay fallback unavailable.',
        ),
      ),
    );
    expect(
      service.diagnostics.errorCode,
      TurnCredentialErrorCode.brokerRateLimited,
    );
    expect(service.diagnostics.lastError, isNot(contains('429')));

    service.dispose();
  });

  test('invalid broker response maps to relay configuration error', () async {
    final service = TurnCredentialService(
      brokerUrl: 'https://broker.example/rainTurnCredentials',
      baseIceServers: const <Map<String, dynamic>>[
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      ],
      credentialFetcher: () async {
        throw const FormatException('TURN broker response has no TURN URLs.');
      },
    );

    final iceServers = await service.iceServers();

    expect(iceServers.single['urls'], 'stun:stun.l.google.com:19302');
    expect(
      service.diagnostics.errorCode,
      TurnCredentialErrorCode.invalidBrokerResponse,
    );
    expect(service.diagnostics.lastError, 'Relay configuration is invalid.');

    service.dispose();
  });

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

List<String> _allUrls(List<Map<String, dynamic>> iceServers) {
  return iceServers
      .expand((Map<String, dynamic> server) {
        final urls = server['urls'];
        if (urls is Iterable) {
          return urls.map((Object? url) => url.toString());
        }
        return <String>[urls.toString()];
      })
      .toList(growable: false);
}
