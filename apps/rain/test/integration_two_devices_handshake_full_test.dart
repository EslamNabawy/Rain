import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'utils/two_device_harness.dart';

const bool runIntegrationTests = bool.fromEnvironment(
  'RUN_RAIN_INTEGRATION_TESTS',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (!runIntegrationTests) return;
    HttpOverrides.global = null;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    if (!runIntegrationTests) return;
    HttpOverrides.global = null;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  test(
    'Two-device handshake full end-to-end over Firebase emulator',
    () async {
      final harness = TwoDeviceHarness();
      final ok = await harness.run();
      expect(ok, isTrue);
    },
    skip: runIntegrationTests ? null : 'Requires Firebase emulators',
  );
}
