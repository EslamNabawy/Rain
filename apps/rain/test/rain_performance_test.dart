import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/performance/rain_performance.dart';

void main() {
  test('selects low power tier for ARMv7 ABI', () {
    final profile = RainPerformanceProfile.detect(abiName: 'androidArm');

    expect(profile.tier, RainPerformanceTier.lowPower);
    expect(profile.reason, 'android-armv7');
  });

  test('selects standard tier for ARM64 ABI', () {
    final profile = RainPerformanceProfile.detect(abiName: 'androidArm64');

    expect(profile.tier, RainPerformanceTier.standard);
    expect(profile.reason, 'default');
  });

  test('explicit override can force low power tier', () {
    final profile = RainPerformanceProfile.detect(
      override: 'low_power',
      abiName: 'androidArm64',
    );

    expect(profile.tier, RainPerformanceTier.lowPower);
    expect(profile.reason, 'override:low_power');
  });

  test('explicit override can force standard tier', () {
    final profile = RainPerformanceProfile.detect(
      override: 'standard',
      abiName: 'androidArm',
    );

    expect(profile.tier, RainPerformanceTier.standard);
    expect(profile.reason, 'override:standard');
  });
}
