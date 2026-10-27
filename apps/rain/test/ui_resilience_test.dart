import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/file_transfer_view.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/presentation/screens/home_screen.dart';
import 'package:rain/presentation/screens/onboarding_screen.dart';
import 'package:rain/presentation/screens/splash_screen.dart';
import 'package:rain/presentation/screens/startup_surface.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/calls/rain_call_ended_surface.dart';
import 'package:rain/presentation/widgets/rain_chat_widgets.dart';
import 'package:rain_core/rain_core.dart';

/// Narrow phone with 130 % text in both themes must never overflow.
Future<void> _expectNoOverflow(
  WidgetTester tester,
  Widget Function() build,
) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 740);
  for (final mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: RainTheme.light(),
          darkTheme: RainTheme.dark(),
          themeMode: mode,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: build(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull, reason: '${mode.name} theme');
  }
}

Widget _framed(Widget child) => Scaffold(
  body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
);

FileTransferView _transfer(FileTransferState state, {int transferred = 0}) {
  return FileTransferView(
    record: FileTransferRecord(
      id: 't1',
      peerId: 'bob',
      messageId: 'm1',
      direction: FileTransferDirection.outgoing,
      fileName: 'a-rather-long-file-name-from-a-phone-camera-2026.jpg',
      fileSize: 4200000,
      bytesTransferred: transferred,
      state: state,
      createdAt: 1,
      updatedAt: 1,
    ),
  );
}

double _contrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background).computeLuminance();
  final bg = background.computeLuminance();
  return (math.max(fg, bg) + 0.05) / (math.min(fg, bg) + 0.05);
}

void main() {
  testWidgets('splash', (tester) async {
    await _expectNoOverflow(
      tester,
      () => const RainSplashScreen(caption: 'Restoring your session'),
    );
  });

  testWidgets('startup failure', (tester) async {
    await _expectNoOverflow(
      tester,
      () => RainStartupFailureScreen(error: StateError('x'), onRetry: () {}),
    );
  });

  testWidgets('force update', (tester) async {
    await _expectNoOverflow(
      tester,
      () => const RainForceUpdateGate(
        result: ForceUpdateResult(
          status: ForceUpdateStatus.updateRequired,
          currentVersion: '1.0.0',
          minVersion: '2.0.0',
          updateUrl: 'https://example.com',
        ),
      ),
    );
  });

  testWidgets('onboarding', (tester) async {
    await _expectNoOverflow(tester, () => const OnboardingScreen());
  });

  testWidgets('message bubbles', (tester) async {
    await _expectNoOverflow(
      tester,
      () => _framed(
        Column(
          children: <Widget>[
            const RainMessageBubble(
              text: 'A fairly long incoming message that has to wrap nicely.',
              timeLabel: '10:42',
              isOutgoing: false,
              startsCluster: true,
              endsCluster: true,
              maxWidth: 300,
            ),
            RainMessageBubble(
              text: 'This one failed to send',
              timeLabel: '10:43',
              isOutgoing: true,
              startsCluster: true,
              endsCluster: true,
              maxWidth: 300,
              deliveryLabel: 'Failed',
              deliveryColor: Colors.redAccent,
              onRetry: () {},
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('file transfer bubble', (tester) async {
    for (final view in <FileTransferView>[
      _transfer(FileTransferState.offered),
      _transfer(FileTransferState.sending, transferred: 1600000),
      _transfer(FileTransferState.completed, transferred: 4200000),
      _transfer(FileTransferState.failed),
    ]) {
      await _expectNoOverflow(
        tester,
        () => _framed(buildFileTransferBubbleForTest(transferView: view)),
      );
    }
  });

  testWidgets('call ended surface', (tester) async {
    await _expectNoOverflow(
      tester,
      () => _framed(
        RainCallEndedSurface(
          summary: CallEndSummary(
            peerId: 'bob',
            peerLabel: 'Bob with a long display name',
            mediaMode: CallMediaMode.video,
            duration: const Duration(hours: 1, minutes: 2, seconds: 8),
            initiator: CallEndInitiator.remote,
            reason: 'Peer ended the call.',
            endedAt: DateTime(2026, 5, 26),
          ),
          onClose: () {},
          onCallAgain: () {},
        ),
      ),
    );
  });

  test('body and muted text stay readable on Rain surfaces', () {
    final cases = <String, (ThemeData, Color)>{
      'dark surface': (RainTheme.dark(), RainColors.surfaceDark),
      'dark background': (RainTheme.dark(), RainColors.backgroundDark),
      'light surface': (RainTheme.light(), RainColors.surfaceLight),
    };
    for (final entry in cases.entries) {
      final (theme, surface) = entry.value;
      final body = theme.colorScheme.onSurface;
      expect(
        _contrast(body, surface),
        greaterThanOrEqualTo(4.5),
        reason: '${entry.key} body',
      );
      // State card body text is onSurface at 0.66; secondary labels use 0.72.
      for (final alpha in <double>[0.66, 0.72]) {
        expect(
          _contrast(body.withValues(alpha: alpha), surface),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} muted $alpha',
        );
      }
    }
    // The splash is always dark: its caption is white at 0.6.
    for (final background in <Color>[
      RainColors.backgroundDark,
      RainColors.surfaceDark,
    ]) {
      expect(
        _contrast(Colors.white.withValues(alpha: 0.6), background),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
