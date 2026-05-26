import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';
import 'package:rain/presentation/widgets/calls/rain_call_stage.dart';
import 'package:rain/presentation/widgets/calls/rain_call_workspace.dart';

void main() {
  testWidgets('fullscreen workspace keeps controls visible inside safe area', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.padding = const FakeViewPadding(top: 36, bottom: 24);
    addTearDown(tester.view.resetPadding);

    await _pumpFullscreenWorkspace(tester);

    expect(find.byKey(const Key('rain-call-status-strip')), findsOneWidget);
    expect(find.byKey(const Key('rain-call-control-dock')), findsOneWidget);

    final statusTop = tester
        .getTopLeft(find.byKey(const Key('rain-call-status-strip')))
        .dy;
    final controlsBottom = tester
        .getBottomLeft(find.byKey(const Key('rain-call-control-dock')))
        .dy;
    expect(statusTop, greaterThanOrEqualTo(36));
    expect(controlsBottom, lessThanOrEqualTo(742));
  });

  testWidgets('desktop workspace shows collapsible side panel', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpFullscreenWorkspace(tester, isDesktop: true);

    expect(
      find.byKey(const Key('rain-call-desktop-side-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('rain-call-fullscreen-friends-panel')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('rain-call-side-panel-collapse')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('rain-call-side-panel-collapsed')),
      findsOneWidget,
    );
  });

  testWidgets('compact video control dock stays short and uses overflow', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 220));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: RainCallControlDock(
                state: _activeVideoCall(),
                onAccept: () {},
                onReject: () {},
                onHangUp: () {},
                onRetry: () {},
                onToggleMute: () {},
                onToggleCamera: () {},
                onSwitchCamera: () {},
                onToggleDeafen: () {},
                trailingControls: <Widget>[
                  IconButton.filledTonal(
                    tooltip: 'Exit fullscreen',
                    onPressed: () {},
                    icon: const Icon(Icons.fullscreen_exit),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('More call controls'), findsOneWidget);
    final dockSize = tester.getSize(
      find.byKey(const ValueKey<String>('rain-call-control-dock')),
    );
    expect(dockSize.height, lessThanOrEqualTo(82));
  });

  testWidgets('mobile workspace hides desktop side panel', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpFullscreenWorkspace(tester);

    expect(find.byKey(const Key('rain-call-desktop-side-panel')), findsNothing);
    expect(find.text('Friends list'), findsNothing);
  });
}

Future<void> _pumpFullscreenWorkspace(
  WidgetTester tester, {
  bool isDesktop = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: _WorkspaceHarness(isDesktop: isDesktop)),
    ),
  );
}

class _WorkspaceHarness extends StatefulWidget {
  const _WorkspaceHarness({required this.isDesktop});

  final bool isDesktop;

  @override
  State<_WorkspaceHarness> createState() => _WorkspaceHarnessState();
}

class _WorkspaceHarnessState extends State<_WorkspaceHarness> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final state = _activeVideoCall();
    return RainCallWorkspace(
      callState: state,
      peerLabel: 'Bob',
      qualityText: 'Direct route',
      stage: RainCallStage(
        state: state,
        accent: Colors.teal,
        layout: RainCallStageLayout.fullscreen,
      ),
      controls: RainCallControlDock(
        state: state,
        onAccept: () {},
        onReject: () {},
        onHangUp: () {},
        onRetry: () {},
        onToggleMute: () {},
      ),
      showDesktopSidePanel: widget.isDesktop,
      onExitFullscreen: () {},
      sidePanel: const Center(child: Text('Friends list')),
      sidePanelCollapsed: _collapsed,
      onToggleSidePanel: () {
        setState(() => _collapsed = !_collapsed);
      },
    );
  }
}

VoiceCallState _activeVideoCall() {
  return VoiceCallState(
    phase: VoiceCallPhase.active,
    peerId: 'bob',
    callId: 'call-1',
    mediaMode: CallMediaMode.video,
    hasLocalVideo: true,
    hasRemoteVideo: true,
    startedAt: DateTime.now()
        .subtract(const Duration(seconds: 7))
        .millisecondsSinceEpoch,
  );
}
