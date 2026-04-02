import 'package:flutter_test/flutter_test.dart';

import 'utils/two_device_harness.dart';

const bool runIntegrationTests =
    bool.fromEnvironment('RUN_RAIN_INTEGRATION_TESTS');

void main() {
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
