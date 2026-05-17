import 'package:flutter_test/flutter_test.dart';
import 'package:rain/core/config/app_environment.dart';

void main() {
  test('firebase is the default backend when no define overrides it', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{},
    );

    expect(environment.backend, RainBackend.firebase);
    expect(environment.signalingEncryptionKey, demoSignalingEncryptionKey);
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
  });

  test('runtime environment can configure Supabase on desktop launches', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: <String, String>{
        'RAIN_BACKEND': 'supabase',
        'SUPABASE_URL': 'https://example.supabase.co',
        'SUPABASE_ANON_KEY': 'anon-key',
      },
    );

    expect(environment.backend, RainBackend.supabase);
    expect(environment.supabaseUrl, 'https://example.supabase.co');
    expect(environment.supabaseAnonKey, 'anon-key');
    expect(environment.shouldUseFallbackAdapter, isFalse);
  });

  test('release validation rejects public OpenRelay by default', () {
    final environment = AppEnvironment.fromEnvironment();

    expect(environment.usesPublicOpenRelay, isTrue);
    expect(environment.allowPublicTurn, isFalse);
    expect(environment.validateForRelease, throwsStateError);
  });

  test('release startup sanitizes public OpenRelay instead of crashing', () {
    final environment = AppEnvironment.fromEnvironment();
    final safeEnvironment = environment.sanitizedForRelease();

    expect(safeEnvironment.usesPublicOpenRelay, isFalse);
    expect(safeEnvironment.releaseRelayIsLimited, isTrue);
    expect(safeEnvironment.validateForRelease, returnsNormally);
  });

  test('local config can explicitly allow public OpenRelay', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: <String, String>{'RAIN_ALLOW_PUBLIC_TURN': 'true'},
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

  test(
    'release sanitizer keeps OpenRelay when demo mode explicitly allows it',
    () {
      final environment = AppEnvironment.fromEnvironment(
        runtimeEnvironment: <String, String>{'RAIN_ALLOW_PUBLIC_TURN': 'true'},
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
      },
    );

    expect(environment.usesPublicOpenRelay, isFalse);
    expect(environment.validateForRelease, returnsNormally);
    expect(environment.validateProductionIceConfig, returnsNormally);
    expect(environment.releaseRelayIsLimited, isFalse);
  });

  test('TURN broker passes production ICE validation without static secrets', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: <String, String>{
        'RAIN_ICE_SERVERS': '[{"urls":"stun:stun.l.google.com:19302"}]',
        'RAIN_TURN_BROKER_URL':
            'https://us-central1-rain.example.cloudfunctions.net/rainTurnCredentials',
      },
    );

    expect(environment.hasTurnBroker, isTrue);
    expect(environment.hasProductionTurnCoverage, isTrue);
    expect(environment.validateProductionIceConfig, returnsNormally);
    expect(environment.releaseRelayIsLimited, isFalse);
  });

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
