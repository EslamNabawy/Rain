import 'package:flutter_test/flutter_test.dart';
import 'package:rain_core/rain_core.dart';

import '../lib/services/rain_runtime_controller.dart';
import 'utils/two_device_harness.dart';

// This test wires two RainRuntimeController instances (Alice & Bob) using
// Firebase emulator-backed signaling adapters and two in-memory Drift DBs.
// It validates a full two-device handshake: register/login, connect, and a
// minimal message exchange over the established WebRTC data channel.

import 'package:flutter_test/flutter_test.dart';
import 'utils/two_device_harness.dart';

void main() {
  test('Two-device handshake full end-to-end over Firebase emulator', () async {
    final harness = TwoDeviceHarness();
    final ok = await harness.run();
    expect(ok, isTrue);
  });
}
