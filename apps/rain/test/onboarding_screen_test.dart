/// # onboarding_screen_test.dart
///
/// Widget tests for the onboarding/authentication screen. Verifies username input lowercasing, brand rendering, keyboard avoidance, and auth surface layout.
///
/// **Key types:** OnboardingScreen, RainPeerCoreMark
///
/// **Depends on:** flutter_test, flutter_riverpod, rain onboarding_screen, rain_core
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain/application/audio/sound_event_router.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/application/state/sound_event_providers.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/network_status_service.dart';
import 'package:rain/infrastructure/services/sound_effects_service.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/screens/onboarding_screen.dart';
import 'package:rain_core/rain_core.dart';

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

  testWidgets('pending login completion after disposal does not crash', (
    WidgetTester tester,
  ) async {
    final effects = _RecordingSoundEffectsService();
    final loginGate = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkStatusProvider.overrideWith(
            (Ref ref) => Stream<NetworkStatusState>.value(
              const NetworkStatusState.online(),
            ),
          ),
          identityProvider.overrideWith(
            () => _BlockingLoginIdentityController(loginGate.future),
          ),
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
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldWithLabel('Username'), 'alice');
    await tester.enterText(_textFieldWithLabel('Password'), 'secret1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    loginGate.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(effects.played, isEmpty);
  });

  testWidgets('registration permission denial shows account conflict message', (
    WidgetTester tester,
  ) async {
    final effects = _RecordingSoundEffectsService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          identityProvider.overrideWith(
            () => _FailingRegisterIdentityController(
              Exception(
                '[firebase_database/unknown] Firebase Database error: '
                'Permission denied',
              ),
            ),
          ),
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
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(_textFieldWithLabel('Display name'), 'Alice');
    await tester.enterText(_textFieldWithLabel('Unique Username'), 'alice');
    await tester.enterText(_textFieldWithLabel('Password'), 'secret1');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Rain could not create that account data. The username may already '
        'be taken or locked. Try signing in or choose another username.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('[firebase_database/unknown]'), findsNothing);
    expect(effects.played, contains(RainSoundEffect.error));
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

final class _BlockingLoginIdentityController extends IdentityController {
  _BlockingLoginIdentityController(this._loginFuture);

  final Future<void> _loginFuture;

  @override
  Future<RainIdentity?> build() async => null;

  @override
  Future<void> login({required String username, required String password}) {
    return _loginFuture;
  }
}

final class _FailingRegisterIdentityController extends IdentityController {
  _FailingRegisterIdentityController(this._error);

  final Object _error;

  @override
  Future<RainIdentity?> build() async => null;

  @override
  Future<void> register({
    required String username,
    required String displayName,
    required String password,
    required RainGender gender,
  }) async {
    throw _error;
  }
}
