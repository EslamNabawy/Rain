import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/state/feedback_settings_providers.dart';
import 'package:rain/presentation/feedback/rain_haptics.dart';

void main() {
  late List<String> hapticCalls;

  setUp(() {
    hapticCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          if (call.method == 'HapticFeedback.vibrate') {
            hapticCalls.add(call.arguments as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<BuildContext> pumpWithSetting(
    WidgetTester tester, {
    required bool enabled,
  }) async {
    late BuildContext captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hapticFeedbackEnabledProvider.overrideWith(
            () => _FixedHapticSetting(enabled),
          ),
        ],
        child: Builder(
          builder: (BuildContext context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await ProviderScope.containerOf(
      captured,
      listen: false,
    ).read(hapticFeedbackEnabledProvider.future);
    await tester.pump();
    return captured;
  }

  testWidgets('plays each kind on Android when the setting is on', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final context = await pumpWithSetting(tester, enabled: true);

    RainHaptics.selection(context);
    RainHaptics.light(context);
    RainHaptics.medium(context);

    debugDefaultTargetPlatformOverride = null;
    expect(hapticCalls, <String>[
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
  });

  testWidgets('stays silent on Android when the setting is off', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final context = await pumpWithSetting(tester, enabled: false);

    RainHaptics.light(context);

    debugDefaultTargetPlatformOverride = null;
    expect(hapticCalls, isEmpty);
  });

  testWidgets('stays silent on Windows', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final context = await pumpWithSetting(tester, enabled: true);

    RainHaptics.medium(context);

    debugDefaultTargetPlatformOverride = null;
    expect(hapticCalls, isEmpty);
  });

  testWidgets('wrap keeps null callbacks null and runs the callback', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final context = await pumpWithSetting(tester, enabled: true);
    var taps = 0;

    expect(RainHaptics.wrap(context, null, RainHapticKind.light), isNull);
    RainHaptics.wrap(context, () => taps += 1, RainHapticKind.light)!();

    debugDefaultTargetPlatformOverride = null;
    expect(taps, 1);
    expect(hapticCalls, <String>['HapticFeedbackType.lightImpact']);
  });
}

class _FixedHapticSetting extends HapticFeedbackSettingsController {
  _FixedHapticSetting(this._enabled);

  final bool _enabled;

  @override
  Future<bool> build() async => _enabled;
}
