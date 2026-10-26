/// # integration_two_devices_handshake_full_test
///
/// Integration test for full two-device handshake flow over Firebase emulator, covering signaling and connection establishment.
///
/// **Key types:** TwoDeviceHarness.
///
/// **Depends on:** Firebase emulator, two-device test harness, and full signaling stack.
library;

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
