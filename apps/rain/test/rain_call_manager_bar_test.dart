import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/widgets/calls/rain_call_manager_bar.dart';

void main() {
  testWidgets('active call renders top manager identity and controls', (
    WidgetTester tester,
  ) async {
    await _pumpManager(
      tester,
      state: _activeCall(),
      surface: const CallSurfaceState.visible(peerId: 'bob', callId: 'call-1'),
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
    expect(find.byTooltip('Hide call panel'), findsOneWidget);
    expect(find.byTooltip('Hang up'), findsOneWidget);
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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
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
