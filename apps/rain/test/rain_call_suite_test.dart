/// # rain_call_suite_test.dart
///
/// Widget tests for the composite call suite widget. Verifies manager-only rendering, fullscreen video workspace ownership, ended call display, and manager bar visibility rules.
///
/// **Key types:** CallSurfaceState, CallSurfaceMode
///
/// **Depends on:** flutter_test, rain voice_call_state, rain_call_suite, rain_call_surface_providers
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';
import 'package:rain/presentation/widgets/calls/rain_call_suite.dart';

void main() {
  testWidgets('manager-only call renders one top manager and no popup', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _suiteHarness(
        state: _call(),
        surface: const CallSurfaceState.visible(
          peerId: 'bob',
          callId: 'call-1',
          mode: CallSurfaceMode.managerOnly,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-manager-bar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('rain-call-popup')), findsNothing);
  });

  testWidgets('fullscreen video owns workspace and hides manager bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _suiteHarness(
        state: _call(mediaMode: CallMediaMode.video),
        surface: const CallSurfaceState.visible(
          peerId: 'bob',
          callId: 'call-1',
          mediaMode: CallMediaMode.video,
          mode: CallSurfaceMode.fullscreen,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-video-fullscreen-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('rain-call-manager-bar')),
      findsNothing,
    );
  });

  testWidgets('ended call renders inside suite without active manager', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _suiteHarness(
        state: const VoiceCallState.idle(),
        surface: const CallSurfaceState.hidden(),
        endPresentation: CallEndPresentationState(
          summary: CallEndSummary(
            peerId: 'bob',
            peerLabel: 'Bob',
            mediaMode: CallMediaMode.audio,
            duration: Duration(seconds: 12),
            initiator: CallEndInitiator.remote,
            reason: 'Ended by peer.',
            endedAt: DateTime.fromMillisecondsSinceEpoch(1),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-ended-popup-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('rain-call-manager-bar')),
      findsNothing,
    );
  });

  testWidgets('microphone control announces its on/off state', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    Future<void> pumpControls(VoiceCallState state) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RainCallControls(
              state: state,
              onAccept: () {},
              onReject: () {},
              onHangUp: () {},
              onRetry: () {},
              onToggleMute: () {},
              controlCapabilities: const <CallControlCapability>[
                CallControlCapability.microphone,
              ],
            ),
          ),
        ),
      );
    }

    final micSemantics = find.byWidgetPredicate(
      (Widget widget) =>
          widget is Semantics && widget.properties.label == 'Microphone',
    );

    await pumpControls(_call());
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Microphone'))).value,
      'On',
    );
    expect(tester.widget<Semantics>(micSemantics).properties.toggled, isTrue);

    await pumpControls(_call().copyWith(isMuted: true));
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Microphone'))).value,
      'Off',
    );
    expect(tester.widget<Semantics>(micSemantics).properties.toggled, isFalse);
    handle.dispose();
  });
}

Widget _suiteHarness({
  required VoiceCallState state,
  required CallSurfaceState surface,
  CallEndPresentationState endPresentation =
      const CallEndPresentationState.hidden(),
}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(390, 720),
        viewPadding: EdgeInsets.only(top: 28, bottom: 24),
      ),
      child: Scaffold(
        body: RainCallSuiteLayer(
          state: state,
          surface: surface,
          endPresentation: endPresentation,
          displayName: 'Bob',
          contentLeftInset: 0,
          isDesktop: false,
          lowPower: false,
          onAccept: () {},
          onReject: () {},
          onHangUp: () {},
          onRetry: () {},
          onToggleMute: () {},
          onToggleDeafen: () {},
          onToggleCamera: () {},
          onSwitchCamera: () {},
          onSelectOutputRoute: (_) {},
          controlCapabilities: state.controlCapabilities,
          outputRouteOptions: const <VoiceCallOutputRouteOption>[],
          onMinimize: () {},
          onRestore: () {},
          onFullscreen: () {},
          onExitFullscreen: () {},
          onToggleVideoPrimaryRole: () {},
          onCloseEnded: () {},
          onCallAgain: (_) {},
        ),
      ),
    ),
  );
}

VoiceCallState _call({CallMediaMode mediaMode = CallMediaMode.audio}) {
  return VoiceCallState(
    phase: VoiceCallPhase.active,
    peerId: 'bob',
    callId: 'call-1',
    mediaMode: mediaMode,
    startedAt: 1,
    updatedAt: 2,
  );
}
