import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/iroh/iroh_bridge_client.dart';

void main() {
  test('Iroh bridge provider stays disabled by default', () {
    final container = ProviderContainer(
      overrides: <Override>[
        appEnvironmentProvider.overrideWithValue(_environment()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(irohBridgeClientProvider), isNull);
  });

  test('Iroh bridge provider is available when fallback is enabled', () {
    final container = ProviderContainer(
      overrides: <Override>[
        appEnvironmentProvider.overrideWithValue(
          _environment(enableIrohFallback: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(irohBridgeClientProvider), isA<IrohBridgeClient>());
  });
}

AppEnvironment _environment({bool enableIrohFallback = false}) {
  return AppEnvironment.fromEnvironment(
    runtimeEnvironment: <String, String>{
      'RAIN_ENABLE_IROH_FALLBACK': enableIrohFallback ? 'true' : 'false',
    },
  );
}
