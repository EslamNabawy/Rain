import 'package:flutter_test/flutter_test.dart';
import 'package:rain/config/app_environment.dart';

void main() {
  test('firebase is the default backend when no define overrides it', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{},
    );

    expect(environment.backend, RainBackend.firebase);
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

  test('project-owned TURN passes release validation', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: <String, String>{
        'RAIN_ICE_SERVERS':
            '[{"urls":"stun:turn.rain.example:3478"},{"urls":"turn:turn.rain.example:3478","username":"rain","credential":"secret"}]',
      },
    );

    expect(environment.usesPublicOpenRelay, isFalse);
    expect(environment.validateForRelease, returnsNormally);
  });
}
