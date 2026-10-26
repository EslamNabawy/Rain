import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/performance/rain_motion_policy.dart';
import 'package:rain/presentation/performance/rain_performance.dart';

Future<RainMotionPolicy> _policyFor(
  WidgetTester tester, {
  bool disableAnimations = false,
  String? override,
}) async {
  late RainMotionPolicy policy;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: RainPerformanceScope(
        profile: RainPerformanceProfile.detect(
          override: override ?? '',
          abiName: 'x86_64',
        ),
        child: Builder(
          builder: (BuildContext context) {
            policy = RainMotionPolicy.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return policy;
}

void main() {
  testWidgets('disableAnimations makes the policy reduced', (tester) async {
    final policy = await _policyFor(tester, disableAnimations: true);
    expect(policy.reduced, isTrue);
    expect(policy.allowContinuous, isFalse);
    expect(policy.d(const Duration(milliseconds: 150)), Duration.zero);
  });

  testWidgets('low-power tier makes the policy reduced', (tester) async {
    final policy = await _policyFor(tester, override: 'low_power');
    expect(policy.reduced, isTrue);
  });

  testWidgets('default policy animates', (tester) async {
    final policy = await _policyFor(tester);
    expect(policy.reduced, isFalse);
    expect(policy.allowContinuous, isTrue);
    expect(
      policy.d(const Duration(milliseconds: 150)),
      const Duration(milliseconds: 150),
    );
  });
}
