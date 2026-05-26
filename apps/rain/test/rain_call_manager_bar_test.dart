import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/branding/rain_ripple_halo_surface.dart';
import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';
import 'package:rain/presentation/widgets/calls/rain_call_layout_contract.dart';
import 'package:rain/presentation/widgets/calls/rain_call_manager_bar.dart';
import 'package:rain/presentation/widgets/calls/rain_call_overlay.dart';
import 'package:rain/presentation/widgets/calls/rain_call_status_strip.dart';

void main() {
  testWidgets('active call renders top manager identity and controls', (
    WidgetTester tester,
  ) async {
    await _pumpManager(
      tester,
      state: _activeCall(),
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mode: CallSurfaceMode.managerOnly,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-manager-bar')),
      findsOneWidget,
    );
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Voice call'), findsOneWidget);
    expect(find.text('Voice call with Bob'), findsOneWidget);
    expect(find.byTooltip('Mute microphone'), findsOneWidget);
    expect(find.byTooltip('Deafen audio'), findsOneWidget);
    expect(find.byTooltip('Restore call panel'), findsOneWidget);
    expect(find.byTooltip('Hang up'), findsOneWidget);
  });

  testWidgets('manager hides while expanded popup owns controls', (
    WidgetTester tester,
  ) async {
    await _pumpManager(
      tester,
      state: _activeCall(),
      surface: const CallSurfaceState.visible(peerId: 'bob', callId: 'call-1'),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-manager-bar')),
      findsNothing,
    );
    expect(find.byTooltip('Hang up'), findsNothing);
  });

  testWidgets('manager hides while fullscreen video owns the viewport', (
    WidgetTester tester,
  ) async {
    await _pumpManager(
      tester,
      state: _activeCall(mediaMode: CallMediaMode.video),
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mediaMode: CallMediaMode.video,
        mode: CallSurfaceMode.fullscreen,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-manager-bar')),
      findsNothing,
    );
    expect(find.byTooltip('Exit fullscreen'), findsNothing);
  });

  testWidgets('manager remains visible when media panel is hidden', (
    WidgetTester tester,
  ) async {
    await _pumpManager(
      tester,
      state: _activeCall(),
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mode: CallSurfaceMode.managerOnly,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-manager-bar')),
      findsOneWidget,
    );
    expect(find.byTooltip('Restore call panel'), findsOneWidget);
  });

  testWidgets('manager wires hangup, mute, deafen, restore and fullscreen', (
    WidgetTester tester,
  ) async {
    var muted = false;
    var camera = false;
    var deafened = false;
    var restored = false;
    var fullscreen = false;
    var hungUp = false;

    await _pumpManager(
      tester,
      state: _activeCall(mediaMode: CallMediaMode.video),
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mediaMode: CallMediaMode.video,
        mode: CallSurfaceMode.managerOnly,
      ),
      onToggleMute: () => muted = true,
      onToggleCamera: () => camera = true,
      onToggleDeafen: () => deafened = true,
      onRestore: () => restored = true,
      onFullscreen: () => fullscreen = true,
      onHangUp: () => hungUp = true,
    );

    await tester.tap(find.byTooltip('Mute microphone'));
    await tester.tap(find.byTooltip('Turn camera off'));
    await tester.tap(find.byTooltip('Deafen audio'));
    await tester.tap(find.byTooltip('Restore call panel'));
    await tester.tap(find.byTooltip('Fullscreen video'));
    await tester.tap(find.byTooltip('Hang up'));

    expect(muted, isTrue);
    expect(camera, isTrue);
    expect(deafened, isTrue);
    expect(restored, isTrue);
    expect(fullscreen, isTrue);
    expect(hungUp, isTrue);
  });

  testWidgets('manager respects top safe area padding', (
    WidgetTester tester,
  ) async {
    await _pumpManager(
      tester,
      state: _activeCall(),
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mode: CallSurfaceMode.managerOnly,
      ),
      mediaQueryData: const MediaQueryData(
        size: Size(360, 640),
        padding: EdgeInsets.only(top: 32),
      ),
    );

    final top = tester
        .getTopLeft(find.byKey(const ValueKey<String>('rain-call-manager-bar')))
        .dy;

    expect(top, greaterThanOrEqualTo(42));
  });

  testWidgets(
    'call overlay respects top safe area and does not overlap Android status bar',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 36);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      await _pumpOverlay(
        tester,
        state: _activeCall(),
        surface: const CallSurfaceState.visible(
          peerId: 'bob',
          callId: 'call-1',
        ),
      );

      final panelTop = tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('rain-call-panel-surface')),
          )
          .dy;

      expect(panelTop, greaterThanOrEqualTo(48));
    },
  );

  testWidgets('manager stays reachable in compact desktop bounds', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpManager(
      tester,
      state: _activeCall(mediaMode: CallMediaMode.video),
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mediaMode: CallMediaMode.video,
        mode: CallSurfaceMode.managerOnly,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-manager-bar')),
      findsOneWidget,
    );
    expect(find.byTooltip('Fullscreen video'), findsOneWidget);
    expect(find.byTooltip('Hang up'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manager active control icons use the shared call mapping', (
    WidgetTester tester,
  ) async {
    final state = _activeCall(mediaMode: CallMediaMode.video);
    await _pumpManager(
      tester,
      state: state,
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mediaMode: CallMediaMode.video,
        mode: CallSurfaceMode.managerOnly,
      ),
    );

    for (final capability in <CallControlCapability>[
      CallControlCapability.microphone,
      CallControlCapability.camera,
      CallControlCapability.deafen,
      CallControlCapability.hangUp,
    ]) {
      final visual = rainVoiceCallControlVisual(state, capability);
      final control = find.byTooltip(visual.tooltip);
      expect(control, findsOneWidget);
      expect(
        find.descendant(of: control, matching: find.byIcon(visual.icon)),
        findsOneWidget,
      );
    }
  });

  testWidgets('low-power manager bar disables call shadow and animated halo', (
    WidgetTester tester,
  ) async {
    await _pumpManager(
      tester,
      state: _activeCall(),
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mode: CallSurfaceMode.managerOnly,
      ),
      performanceProfile: RainPerformanceProfile.detectForTest(
        abiName: 'armeabi-v7a',
      ),
    );

    final halo = tester.widget<RainRippleHaloSurface>(
      find.byKey(const ValueKey<String>('rain-call-manager-bar')),
    );
    expect(halo.callSurface, isTrue);

    final decoratedBox = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('rain-call-manager-bar')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final decoration = decoratedBox.decoration as BoxDecoration;
    expect(decoration.boxShadow, isEmpty);
  });

  testWidgets(
    'low-power overlay removes panel shadow and transition duration',
    (WidgetTester tester) async {
      await _pumpOverlay(
        tester,
        state: _activeCall(),
        surface: const CallSurfaceState.visible(
          peerId: 'bob',
          callId: 'call-1',
        ),
        performanceProfile: RainPerformanceProfile.detectForTest(
          abiName: 'armeabi-v7a',
        ),
      );

      final halo = tester.widget<RainRippleHaloSurface>(
        find.byKey(const ValueKey<String>('rain-call-panel-surface')),
      );
      expect(halo.callSurface, isTrue);

      final animatedPanel = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('rain-call-panel-surface')),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(animatedPanel.duration, Duration.zero);

      final decoration = animatedPanel.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isEmpty);
    },
  );

  test('layout contract maps call surfaces without duplicated controls', () {
    final popup = RainCallLayoutContract.fromSurface(
      const CallSurfaceState.visible(peerId: 'bob', callId: 'call-1'),
      isDesktop: false,
    );
    expect(popup.surfaceMode, RainCallSurfaceMode.popup);
    expect(popup.showTopManagerBar, isFalse);
    expect(popup.showMediaSurface, isTrue);
    expect(popup.showExpandedControls, isTrue);

    final minimized = RainCallLayoutContract.fromSurface(
      const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mode: CallSurfaceMode.managerOnly,
      ),
      isDesktop: false,
    );
    expect(minimized.surfaceMode, RainCallSurfaceMode.minimized);
    expect(minimized.showTopManagerBar, isTrue);
    expect(minimized.showMediaSurface, isFalse);
    expect(minimized.showExpandedControls, isFalse);

    final pip = RainCallLayoutContract.fromSurface(
      const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mediaMode: CallMediaMode.video,
        mode: CallSurfaceMode.pip,
      ),
      isDesktop: true,
    );
    expect(pip.surfaceMode, RainCallSurfaceMode.pip);
    expect(pip.showTopManagerBar, isTrue);
    expect(pip.showMediaSurface, isTrue);
    expect(pip.showExpandedControls, isFalse);

    final fullscreen = RainCallLayoutContract.fromSurface(
      const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mediaMode: CallMediaMode.video,
        mode: CallSurfaceMode.fullscreen,
      ),
      isDesktop: true,
    );
    expect(fullscreen.surfaceMode, RainCallSurfaceMode.fullscreen);
    expect(fullscreen.showTopManagerBar, isFalse);
    expect(fullscreen.showMediaSurface, isTrue);
    expect(fullscreen.showExpandedControls, isTrue);
    expect(fullscreen.showDesktopSidePanel, isTrue);
  });

  testWidgets('top call manager is hidden while popup is expanded', (
    WidgetTester tester,
  ) async {
    await _pumpCallSurface(
      tester,
      state: _activeCall(),
      surface: const CallSurfaceState.visible(peerId: 'bob', callId: 'call-1'),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-manager-bar')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('rain-call-popup')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('rain-call-control-dock')),
      findsOneWidget,
    );
  });

  testWidgets('top call manager appears only when call is minimized', (
    WidgetTester tester,
  ) async {
    await _pumpCallSurface(
      tester,
      state: _activeCall(),
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mode: CallSurfaceMode.managerOnly,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-manager-bar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('rain-call-popup')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('rain-call-control-dock')),
      findsNothing,
    );
  });

  testWidgets('call status strip presents peer, state, duration, and quality', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RainCallStatusStrip(
            peerLabel: 'Bob',
            statusText: 'Video call with Bob',
            durationText: '0:07',
            qualityText: 'Direct route',
          ),
        ),
      ),
    );

    expect(find.text('Bob'), findsOneWidget);
    expect(
      find.text('Video call with Bob / 0:07 / Direct route'),
      findsOneWidget,
    );
  });

  testWidgets('manager does not block bottom composer taps', (
    WidgetTester tester,
  ) async {
    var composerTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 64,
                  child: TextButton(
                    onPressed: () => composerTapped = true,
                    child: const Text('Message composer'),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: RainCallManagerBar(
                  state: _activeCall(),
                  surface: const CallSurfaceState.visible(
                    peerId: 'bob',
                    callId: 'call-1',
                    mode: CallSurfaceMode.managerOnly,
                  ),
                  displayName: 'Bob',
                  onToggleMute: () {},
                  onRestore: () {},
                  onFullscreen: () {},
                  onHangUp: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Message composer'));

    expect(composerTapped, isTrue);
  });
}

Future<void> _pumpManager(
  WidgetTester tester, {
  required VoiceCallState state,
  required CallSurfaceState surface,
  VoidCallback? onToggleMute,
  VoidCallback? onToggleCamera,
  VoidCallback? onToggleDeafen,
  VoidCallback? onRestore,
  VoidCallback? onFullscreen,
  VoidCallback? onHangUp,
  MediaQueryData? mediaQueryData,
  RainPerformanceProfile? performanceProfile,
}) async {
  Widget home = Scaffold(
    body: RainCallManagerBar(
      state: state,
      surface: surface,
      displayName: 'Bob',
      onToggleMute: onToggleMute ?? () {},
      onToggleCamera: onToggleCamera,
      onToggleDeafen: onToggleDeafen,
      onRestore: onRestore ?? () {},
      onFullscreen: onFullscreen ?? () {},
      onHangUp: onHangUp ?? () {},
    ),
  );
  if (mediaQueryData != null) {
    home = MediaQuery(data: mediaQueryData, child: home);
  }
  if (performanceProfile != null) {
    home = RainPerformanceScope(profile: performanceProfile, child: home);
  }
  await tester.pumpWidget(MaterialApp(home: home));
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required VoiceCallState state,
  required CallSurfaceState surface,
  RainPerformanceProfile? performanceProfile,
}) async {
  Widget home = Scaffold(
    body: Stack(
      children: <Widget>[
        Positioned.fill(
          child: RainCallOverlay(
            state: state,
            surface: surface,
            displayName: 'Bob',
            onAccept: () {},
            onReject: () {},
            onHangUp: () {},
            onRetry: () {},
            onToggleMute: () {},
            onMinimize: () {},
            onExpand: () {},
          ),
        ),
      ],
    ),
  );
  if (performanceProfile != null) {
    home = RainPerformanceScope(profile: performanceProfile, child: home);
  }
  await tester.pumpWidget(MaterialApp(home: home));
}

Future<void> _pumpCallSurface(
  WidgetTester tester, {
  required VoiceCallState state,
  required CallSurfaceState surface,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: RainCallOverlay(
                state: state,
                surface: surface,
                displayName: 'Bob',
                onAccept: () {},
                onReject: () {},
                onHangUp: () {},
                onRetry: () {},
                onToggleMute: () {},
                onMinimize: () {},
                onExpand: () {},
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: RainCallManagerBar(
                state: state,
                surface: surface,
                displayName: 'Bob',
                onToggleMute: () {},
                onRestore: () {},
                onFullscreen: () {},
                onHangUp: () {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

VoiceCallState _activeCall({CallMediaMode mediaMode = CallMediaMode.audio}) {
  return VoiceCallState(
    phase: VoiceCallPhase.active,
    peerId: 'bob',
    callId: 'call-1',
    mediaMode: mediaMode,
    startedAt: DateTime.now()
        .subtract(const Duration(seconds: 7))
        .millisecondsSinceEpoch,
  );
}
