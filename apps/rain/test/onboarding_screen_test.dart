import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain/application/audio/sound_event_router.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/sound_event_providers.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/sound_effects_service.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/branding/rain_streak_surface.dart';
import 'package:rain/presentation/screens/onboarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('username input lowercases capital letters before filtering', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: OnboardingScreen())),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'ALICE_1');

    final editable = tester.widget<EditableText>(
      find.byType(EditableText).first,
    );
    expect(editable.controller.text, 'alice_1');
  });

  testWidgets('auth surface uses Rain Peer Core brand treatment', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: OnboardingScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('rain-auth-card-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('rain-auth-peer-core-mark')),
      findsOneWidget,
    );
    expect(find.byType(RainPeerCoreMark), findsWidgets);
    expect(find.byType(RainStreakSurface), findsWidgets);
  });

  testWidgets('focused credential field stays above the mobile keyboard', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: true,
            body: OnboardingScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final passwordField = _textFieldWithLabel('Password');
    await tester.tap(passwordField);
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    final keyboardTop =
        tester.view.physicalSize.height - tester.view.viewInsets.bottom;
    expect(tester.getRect(passwordField).bottom, lessThan(keyboardTop - 64));
    expect(tester.getRect(passwordField).top, lessThan(220));
  });

  testWidgets('focused credential field clears OEM overlay keyboard in login', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: OnboardingScreen())),
    );
    await tester.pumpAndSettle();

    final passwordField = _textFieldWithLabel('Password');
    await tester.tap(passwordField);
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final keyboardTop =
        tester.view.physicalSize.height - tester.view.viewInsets.bottom;
    final passwordRect = tester.getRect(passwordField);
    expect(passwordRect.bottom, lessThanOrEqualTo(keyboardTop - 48));
    expect(passwordRect.top, greaterThanOrEqualTo(0));
  });

  testWidgets(
    'focused credential field clears keyboard on short Android size',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: OnboardingScreen())),
      );
      await tester.pumpAndSettle();

      final passwordField = _textFieldWithLabel('Password');
      await tester.tap(passwordField);
      await tester.pump();

      tester.view.viewInsets = const FakeViewPadding(bottom: 330);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      final keyboardTop =
          tester.view.physicalSize.height - tester.view.viewInsets.bottom;
      final passwordRect = tester.getRect(passwordField);
      expect(passwordRect.bottom, lessThanOrEqualTo(keyboardTop - 40));
      expect(passwordRect.top, greaterThanOrEqualTo(0));
    },
  );

  testWidgets('login credential fields use matching geometry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: OnboardingScreen())),
      ),
    );
    await tester.pumpAndSettle();

    final usernameRect = tester.getRect(_textFieldWithLabel('Username'));
    final passwordRect = tester.getRect(_textFieldWithLabel('Password'));

    expect(usernameRect.height, moreOrLessEquals(passwordRect.height));
    expect(usernameRect.left, moreOrLessEquals(passwordRect.left));
    expect(usernameRect.right, moreOrLessEquals(passwordRect.right));
  });

  testWidgets('validation failure emits warning sound through router', (
    WidgetTester tester,
  ) async {
    final effects = _RecordingSoundEffectsService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          soundEventRouterProvider.overrideWithValue(
            SoundEventRouter(
              effects: effects,
              settingsLoader: () => const AppAudioSettings(),
              callStateReader: () => const VoiceCallState.idle(),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: OnboardingScreen())),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(effects.played, <RainSoundEffect>[RainSoundEffect.error]);
  });

  testWidgets('validation warning respects disabled sound settings', (
    WidgetTester tester,
  ) async {
    final effects = _RecordingSoundEffectsService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          soundEventRouterProvider.overrideWithValue(
            SoundEventRouter(
              effects: effects,
              settingsLoader: () =>
                  const AppAudioSettings(soundEffectsEnabled: false),
              callStateReader: () => const VoiceCallState.idle(),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: OnboardingScreen())),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(effects.played, isEmpty);
  });
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (Widget widget) =>
        widget is TextField && widget.decoration?.labelText == label,
  );
}

final class _RecordingSoundEffectsService extends SoundEffectsService {
  _RecordingSoundEffectsService() : super();

  final List<RainSoundEffect> played = <RainSoundEffect>[];

  @override
  Future<void> play(
    RainSoundEffect effect, {
    bool voiceCallActive = false,
    bool allowDuringCall = false,
    double volumeScale = 1.0,
  }) async {
    played.add(effect);
  }
}
