import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';
import 'package:rain/presentation/widgets/calls/rain_call_manager_bar.dart';

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
    (WidgetTester tester) async {},
    skip: true,
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
  await tester.pumpWidget(MaterialApp(home: home));
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
