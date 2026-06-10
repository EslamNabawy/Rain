import 'package:flutter_test/flutter_test.dart';
import 'package:rain/core/config/app_environment.dart';

void main() {
  test('firebase is the default backend when no define overrides it', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{},
    );

    expect(environment.backend, RainBackend.firebase);
    expect(environment.updateChannel, 'stable');
    expect(environment.signalingEncryptionKey, demoSignalingEncryptionKey);
    expect(environment.signalingEncryptionKeyProvided, isFalse);
  });

  test('runtime environment can configure update channel', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{'RAIN_UPDATE_CHANNEL': 'demo'},
    );

    expect(environment.updateChannel, 'demo');
  });

  test('runtime environment can configure signaling encryption key', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{
        'RAIN_SIGNALING_ENCRYPTION_KEY':
            'rain-project-owned-signaling-key-material',
      },
    );

    expect(
      environment.signalingEncryptionKey,
      'rain-project-owned-signaling-key-material',
    );
    expect(environment.signalingEncryptionKeyProvided, isTrue);
  });

  test('unsupported backend values fall back to local demo mode', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: <String, String>{'RAIN_BACKEND': 'unsupported'},
    );

    expect(environment.backend, RainBackend.noop);
    expect(environment.shouldUseFallbackAdapter, isTrue);
  });

  test('release validation rejects public OpenRelay by default', () {
    final environment = AppEnvironment.fromEnvironment();

    expect(environment.usesPublicOpenRelay, isTrue);
    expect(environment.allowPublicTurn, isFalse);
    expect(environment.validateForRelease, throwsStateError);
  });

  test('release startup sanitizes public OpenRelay instead of crashing', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{
        'RAIN_SIGNALING_ENCRYPTION_KEY':
            'rain-project-owned-signaling-key-material',
      },
    );
    final safeEnvironment = environment.sanitizedForRelease();

    expect(safeEnvironment.usesPublicOpenRelay, isFalse);
    expect(safeEnvironment.releaseRelayIsLimited, isTrue);
    expect(safeEnvironment.validateForRelease, returnsNormally);
  });

  test('release validation rejects demo signaling encryption key', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{
        'RAIN_SIGNALING_ENCRYPTION_KEY': demoSignalingEncryptionKey,
      },
    ).sanitizedForRelease();

    expect(environment.usesDemoSignalingEncryptionKey, isTrue);
    expect(
      environment.validateForRelease,
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.toString(),
          'message',
          contains('demo signaling encryption key'),
        ),
      ),
    );
  });

  test('release validation rejects missing production signaling key', () {
    final environment = AppEnvironment.fromEnvironment().sanitizedForRelease();

    expect(environment.signalingEncryptionKeyProvided, isFalse);
    expect(
      environment.validateForRelease,
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.toString(),
          'message',
          contains('RAIN_SIGNALING_ENCRYPTION_KEY is required'),
        ),
      ),
    );
  });

  test('demo config can explicitly allow public OpenRelay', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{
        'RAIN_ALLOW_PUBLIC_TURN': 'true',
        'RAIN_UPDATE_CHANNEL': 'demo',
        'RAIN_SIGNALING_ENCRYPTION_KEY':
            'rain-project-owned-signaling-key-material',
      },
    );

    expect(environment.usesPublicOpenRelay, isTrue);
    expect(environment.allowPublicTurn, isTrue);
    expect(environment.validateForRelease, returnsNormally);
  });

  test('demo OpenRelay config includes UDP, TCP, and TLS relay paths', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: <String, String>{'RAIN_ALLOW_PUBLIC_TURN': 'true'},
    );

    expect(environment.usesPublicOpenRelay, isTrue);
    expect(environment.hasTurnUdpEndpoint, isTrue);
    expect(environment.hasTurnTcpEndpoint, isTrue);
    expect(environment.hasTurnsTcpEndpoint, isTrue);
    expect(environment.allTurnServersHaveCredentials, isTrue);
  });

  test('default ICE config includes tested public STUN fallbacks', () {
    const expectedStunUrls = <String>[
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
      'stun:stun2.l.google.com:19302',
      'stun:stun3.l.google.com:19302',
      'stun:stun4.l.google.com:19302',
      'stun:stun.voipstunt.com:3478',
      'stun:stun.voipbuster.com:3478',
      'stun:stun.sipgate.net:10000',
      'stun:stun.schlund.de:3478',
      'stun:stun.1und1.de:3478',
    ];

    expect(_iceUrls(testedPublicStunIceServers), expectedStunUrls);
    expect(_iceUrls(releaseDefaultIceServers), expectedStunUrls);
    expect(_iceUrls(defaultIceServers), containsAll(expectedStunUrls));
    expect(
      _iceUrls(defaultIceServers),
      isNot(contains('stun:stun.cloudflare.com:3478')),
    );
  });

  test('explicit demo mode permits bundled demo signaling key', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: <String, String>{
        'RAIN_ALLOW_PUBLIC_TURN': 'true',
        'RAIN_UPDATE_CHANNEL': 'demo',
      },
    );

    expect(environment.usesDemoSignalingEncryptionKey, isTrue);
    expect(environment.validateForRelease, returnsNormally);
  });

  test(
    'release sanitizer keeps OpenRelay when demo mode explicitly allows it',
    () {
      final environment = AppEnvironment.fromEnvironment(
        runtimeEnvironment: const <String, String>{
          'RAIN_ALLOW_PUBLIC_TURN': 'true',
          'RAIN_UPDATE_CHANNEL': 'demo',
          'RAIN_SIGNALING_ENCRYPTION_KEY':
              'rain-project-owned-signaling-key-material',
        },
      );
      final safeEnvironment = environment.sanitizedForRelease();

      expect(safeEnvironment.usesPublicOpenRelay, isTrue);
      expect(safeEnvironment.allowPublicTurn, isTrue);
      expect(safeEnvironment.validateForRelease, returnsNormally);
    },
  );

  test('project-owned TURN passes production ICE validation', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: <String, String>{
        'RAIN_ICE_SERVERS':
            '[{"urls":"stun:turn.rain.example:3478"},'
            '{"urls":["turn:turn.rain.example:3478?transport=udp",'
            '"turn:turn.rain.example:3478?transport=tcp",'
            '"turns:turn.rain.example:5349?transport=tcp"],'
            '"username":"rain","credential":"secret"}]',
        'RAIN_SIGNALING_ENCRYPTION_KEY':
            'rain-project-owned-signaling-key-material',
      },
    );

    expect(environment.usesPublicOpenRelay, isFalse);
    expect(environment.validateForRelease, returnsNormally);
    expect(environment.validateProductionIceConfig, returnsNormally);
    expect(environment.releaseRelayIsLimited, isFalse);
  });

  test(
    'TURN broker passes production ICE validation without static secrets',
    () {
      final environment = AppEnvironment.fromEnvironment(
        runtimeEnvironment: <String, String>{
          'RAIN_ICE_SERVERS': '[{"urls":"stun:stun.l.google.com:19302"}]',
          'RAIN_TURN_BROKER_URL':
              'https://turn-broker.rain.example/credentials',
        },
      );

      expect(environment.hasTurnBroker, isTrue);
      expect(environment.hasProductionTurnCoverage, isTrue);
      expect(environment.validateProductionIceConfig, returnsNormally);
      expect(environment.releaseRelayIsLimited, isFalse);
    },
  );

  test('production ICE validation rejects missing TURNS fallback', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: <String, String>{
        'RAIN_ICE_SERVERS':
            '[{"urls":"stun:turn.rain.example:3478"},'
            '{"urls":["turn:turn.rain.example:3478?transport=udp",'
            '"turn:turn.rain.example:3478?transport=tcp"],'
            '"username":"rain","credential":"secret"}]',
      },
    );

    expect(
      environment.validateProductionIceConfig,
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.toString(),
          'message',
          contains('turns: TCP/TLS'),
        ),
      ),
    );
  });

  test(
    'production ICE validation rejects TURN entries without credentials',
    () {
      final environment = AppEnvironment.fromEnvironment(
        runtimeEnvironment: <String, String>{
          'RAIN_ICE_SERVERS':
              '[{"urls":["turn:turn.rain.example:3478?transport=udp",'
              '"turn:turn.rain.example:3478?transport=tcp",'
              '"turns:turn.rain.example:5349?transport=tcp"]}]',
        },
      );

      expect(
        environment.validateProductionIceConfig,
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.toString(),
            'message',
            contains('username and credential'),
          ),
        ),
      );
    },
  );
}

List<String> _iceUrls(List<Map<String, dynamic>> iceServers) {
  return iceServers
      .expand((server) {
        final urls = server['urls'];
        if (urls is String) {
          return <String>[urls];
        }
        if (urls is Iterable) {
          return urls.whereType<String>();
        }
        return const <String>[];
      })
      .toList(growable: false);
}
