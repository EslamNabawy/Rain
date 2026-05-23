import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/media_device_settings.dart';
import 'package:rain/application/runtime/voice_audio_level.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/widgets/calls/rain_call_overlay.dart';
import 'package:rain/presentation/widgets/rain_chat_widgets.dart';

void main() {
  testWidgets('RainLiveLinkBar renders link state and strength', (
    WidgetTester tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainLiveLinkBar(
            label: 'Linked',
            detail: 'Encrypted peer lane is open.',
            color: const Color(0xFF2DD4A3),
            icon: Icons.hub_outlined,
            strength: 3,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Linked'), findsOneWidget);
    expect(find.text('Encrypted peer lane is open.'), findsOneWidget);
    expect(_findMeterCells('rain-link-meter-on-'), findsNWidgets(3));
    expect(_findMeterCells('rain-link-meter-off-'), findsOneWidget);

    await tester.tap(find.text('Linked'));
    expect(tapped, isTrue);
  });

  testWidgets('RainAvatar uses first display-name letter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RainAvatar(name: 'nora voss', statusColor: Color(0xFF2DD4A3)),
        ),
      ),
    );

    expect(find.text('N'), findsOneWidget);
  });

  testWidgets('RainAvatar uses gender assets when gender is known', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              RainAvatar(name: 'Nora', gender: 'female'),
              RainAvatar(name: 'Omar', gender: 'male'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsNWidgets(2));
    for (final widget in tester.widgetList<SvgPicture>(
      find.byType(SvgPicture),
    )) {
      expect(widget.fit, BoxFit.contain);
    }
    expect(find.text('N'), findsNothing);
    expect(find.text('O'), findsNothing);
  });

  testWidgets('RainMessageBubble renders delivery state and retry action', (
    WidgetTester tester,
  ) async {
    var retryTapped = false;
    var actionsOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainMessageBubble(
            text: 'Peer lane dropped during send',
            timeLabel: '10:42',
            isOutgoing: true,
            startsCluster: true,
            endsCluster: true,
            maxWidth: 320,
            deliveryLabel: 'Failed',
            deliveryColor: const Color(0xFFFF6B6B),
            onRetry: () => retryTapped = true,
            onOpenActions: () => actionsOpened = true,
          ),
        ),
      ),
    );

    expect(find.text('Peer lane dropped during send'), findsOneWidget);
    expect(find.text('10:42'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Message actions'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retryTapped, isTrue);

    await tester.tap(find.byTooltip('Message actions'));
    expect(actionsOpened, isTrue);
  });

  testWidgets('RainMessageDayDivider labels grouped days', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RainMessageDayDivider(label: 'Today')),
      ),
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('RainComposerCommandStrip shows link action', (
    WidgetTester tester,
  ) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainComposerCommandStrip(
            label: 'Ready',
            detail: 'Peer online; open link',
            color: const Color(0xFF7DD3FC),
            icon: Icons.wifi_tethering,
            actionLabel: 'Open',
            actionIcon: Icons.hub_outlined,
            onAction: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Peer online; open link'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    await tester.tap(find.text('Open'));
    expect(opened, isTrue);
  });

  testWidgets('voice call button disables during active transfer', (
    WidgetTester tester,
  ) async {
    var started = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallButton(
            peerId: 'bob',
            state: const VoiceCallState.idle(),
            canStart: false,
            hasActiveTransfer: true,
            onStart: () => started = true,
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
    expect(button.tooltip, 'Finish the active file transfer first.');
    await tester.tap(find.byType(IconButton));
    expect(started, isFalse);
  });

  testWidgets('voice call button disables during another call', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallButton(
            peerId: 'bob',
            state: const VoiceCallState(
              phase: VoiceCallPhase.active,
              peerId: 'alice',
              callId: 'call-1',
            ),
            canStart: false,
            hasActiveTransfer: false,
            onStart: () {},
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
    expect(button.tooltip, 'Finish the active call with @alice first.');
  });

  testWidgets('voice call incoming ring actions are wired', (
    WidgetTester tester,
  ) async {
    var accepted = false;
    var rejected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallPanel(
            state: const VoiceCallState(
              phase: VoiceCallPhase.incomingRinging,
              peerId: 'bob',
              callId: 'call-1',
            ),
            displayName: 'Bob',
            onAccept: () => accepted = true,
            onReject: () => rejected = true,
            onHangUp: () {},
            onRetry: () {},
            onToggleMute: () {},
          ),
        ),
      ),
    );

    expect(find.text('Bob is calling'), findsOneWidget);
    expect(find.text('Incoming voice call.'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    expect(accepted, isTrue);

    await tester.tap(find.text('Reject'));
    expect(rejected, isTrue);
  });

  testWidgets('voice call active mute and hangup actions are wired', (
    WidgetTester tester,
  ) async {
    var muted = false;
    var hungUp = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallPanel(
            state: VoiceCallState(
              phase: VoiceCallPhase.active,
              peerId: 'bob',
              callId: 'call-1',
              startedAt: DateTime.now()
                  .subtract(const Duration(seconds: 7))
                  .millisecondsSinceEpoch,
            ),
            displayName: 'Bob',
            onAccept: () {},
            onReject: () {},
            onHangUp: () => hungUp = true,
            onRetry: () {},
            onToggleMute: () => muted = true,
          ),
        ),
      ),
    );

    expect(find.text('Voice call with Bob'), findsOneWidget);
    await tester.tap(find.byTooltip('Mute microphone'));
    expect(muted, isTrue);

    await tester.tap(find.byTooltip('Hang up'));
    expect(hungUp, isTrue);
  });

  testWidgets('voice call deafen and output route actions are wired', (
    WidgetTester tester,
  ) async {
    var deafened = false;
    VoiceCallOutputRoute? route;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallPanel(
            state: VoiceCallState(
              phase: VoiceCallPhase.active,
              peerId: 'bob',
              callId: 'call-1',
              isDeafened: true,
              outputRoute: VoiceCallOutputRoute.speaker,
              outputRouteWarning: 'Audio route unavailable.',
              startedAt: DateTime.now()
                  .subtract(const Duration(seconds: 7))
                  .millisecondsSinceEpoch,
            ),
            displayName: 'Bob',
            onAccept: () {},
            onReject: () {},
            onHangUp: () {},
            onRetry: () {},
            onToggleMute: () {},
            onToggleDeafen: () => deafened = true,
            onSelectOutputRoute: (VoiceCallOutputRoute value) => route = value,
          ),
        ),
      ),
    );

    expect(find.textContaining('Deafened'), findsOneWidget);
    expect(find.textContaining('Speaker'), findsOneWidget);
    expect(find.textContaining('Audio route unavailable.'), findsOneWidget);

    await tester.tap(find.byTooltip('Undeafen audio'));
    expect(deafened, isTrue);

    await tester.tap(find.byTooltip('Choose audio output'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bluetooth').last);

    expect(route, VoiceCallOutputRoute.bluetooth);
  });

  testWidgets('voice call mic permission failure offers retry', (
    WidgetTester tester,
  ) async {
    var retried = false;
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallPanel(
            state: const VoiceCallState(
              phase: VoiceCallPhase.failed,
              peerId: 'bob',
              callId: 'call-1',
              failureReason: VoiceCallFailureReason.microphoneDenied,
              detail: 'NotAllowedError: Permission denied',
            ),
            displayName: 'Bob',
            onAccept: () {},
            onReject: () {},
            onHangUp: () => dismissed = true,
            onRetry: () => retried = true,
            onToggleMute: () {},
          ),
        ),
      ),
    );

    expect(find.text('Voice call failed'), findsOneWidget);
    expect(find.text('Microphone permission required.'), findsOneWidget);
    expect(find.textContaining('NotAllowedError'), findsNothing);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);

    await tester.tap(find.text('Dismiss'));
    expect(dismissed, isTrue);
  });

  testWidgets('voice call failed dismiss hides raw native errors', (
    WidgetTester tester,
  ) async {
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallPanel(
            state: const VoiceCallState(
              phase: VoiceCallPhase.failed,
              peerId: 'bob',
              callId: 'call-1',
              failureReason: VoiceCallFailureReason.mediaConnectionFailed,
              detail:
                  'Unable to RTCRtpTransceiver::setDirection: RtpTransceiver has been disposed.',
            ),
            displayName: 'Bob',
            onAccept: () {},
            onReject: () {},
            onHangUp: () => dismissed = true,
            onRetry: () {},
            onToggleMute: () {},
          ),
        ),
      ),
    );

    expect(
      find.text('Call media could not connect. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('RTCRtpTransceiver'), findsNothing);

    await tester.tap(find.text('Dismiss'));
    expect(dismissed, isTrue);
  });

  testWidgets('voice call failure maps signaling errors to typed UI', (
    WidgetTester tester,
  ) async {
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallPanel(
            state: const VoiceCallState(
              phase: VoiceCallPhase.failed,
              peerId: 'bob',
              callId: 'call-1',
              failureReason: VoiceCallFailureReason.signalingFailed,
              detail:
                  'VoiceSignalingException: Firebase permission-denied at voiceCalls/call-1',
            ),
            displayName: 'Bob',
            onAccept: () {},
            onReject: () {},
            onHangUp: () {},
            onRetry: () => retried = true,
            onToggleMute: () {},
          ),
        ),
      ),
    );

    expect(find.text('Call setup failed. Try again.'), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
    expect(find.textContaining('voiceCalls'), findsNothing);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('voice call busy raw room lock is shown as peer busy', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallPanel(
            state: const VoiceCallState(
              phase: VoiceCallPhase.failed,
              peerId: 'bob',
              callId: 'call-1',
              detail:
                  'VoiceSignalingException: Active voice call already exists for pair alice:bob.',
            ),
            displayName: 'Bob',
            onAccept: () {},
            onReject: () {},
            onHangUp: () {},
            onRetry: () {},
            onToggleMute: () {},
          ),
        ),
      ),
    );

    expect(find.text('Peer is busy.'), findsOneWidget);
    expect(find.textContaining('Active voice call'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('microphone selector handles empty device list', (
    WidgetTester tester,
  ) async {
    var refreshed = false;
    String? selected = 'unchanged';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainMicrophoneSelector(
            state: const MicrophoneSelectionState(devices: []),
            isBusy: false,
            onRefresh: () => refreshed = true,
            onSelected: (String? value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('No microphones found.'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh microphones'));
    expect(refreshed, isTrue);

    await tester.tap(find.byTooltip('Choose microphone'));
    expect(selected, 'unchanged');
  });

  testWidgets('microphone selector emits selected device', (
    WidgetTester tester,
  ) async {
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainMicrophoneSelector(
            state: const MicrophoneSelectionState(
              devices: <RainMediaDevice>[
                RainMediaDevice(
                  deviceId: 'mic-1',
                  label: 'Desk mic',
                  kind: audioInputDeviceKind,
                ),
              ],
            ),
            isBusy: false,
            onRefresh: () {},
            onSelected: (String? value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Choose microphone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desk mic').last);

    expect(selected, 'mic-1');
  });

  testWidgets('call overlay expands and minimizes active calls', (
    WidgetTester tester,
  ) async {
    var minimized = false;
    var muted = false;
    var hungUp = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: RainCallOverlay(
                  state: _activeVoiceCall(),
                  surface: const CallSurfaceState.visible(
                    peerId: 'bob',
                    callId: 'call-1',
                  ),
                  displayName: 'Bob',
                  onAccept: () {},
                  onReject: () {},
                  onHangUp: () => hungUp = true,
                  onRetry: () {},
                  onToggleMute: () => muted = true,
                  onMinimize: () => minimized = true,
                  onExpand: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Voice call with Bob'), findsOneWidget);
    expect(find.byTooltip('Minimize call'), findsOneWidget);

    await tester.tap(find.byTooltip('Mute microphone'));
    expect(muted, isTrue);

    await tester.tap(find.byTooltip('Minimize call'));
    expect(minimized, isTrue);

    await tester.tap(find.byTooltip('Hang up'));
    expect(hungUp, isTrue);
  });

  testWidgets('call overlay wave amplitude follows real audio level', (
    WidgetTester tester,
  ) async {
    await _pumpCallOverlay(
      tester,
      _activeVoiceCall(
        audioLevel: VoiceAudioLevel.available(
          remoteLevel: 0.08,
          localLevel: 0,
          updatedAt: 1,
          source: VoiceAudioLevelSource.audioLevel,
        ),
      ),
    );
    final lowHeight = tester
        .getSize(
          find.byKey(const ValueKey<String>('rain-call-audio-wave-bar-2')),
        )
        .height;

    await _pumpCallOverlay(
      tester,
      _activeVoiceCall(
        audioLevel: VoiceAudioLevel.available(
          remoteLevel: 0.86,
          localLevel: 0,
          updatedAt: 2,
          source: VoiceAudioLevelSource.audioLevel,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final highHeight = tester
        .getSize(
          find.byKey(const ValueKey<String>('rain-call-audio-wave-bar-2')),
        )
        .height;

    expect(highHeight, greaterThan(lowHeight));
  });

  testWidgets('call overlay shows idle audio glyph when meter unavailable', (
    WidgetTester tester,
  ) async {
    await _pumpCallOverlay(tester, _activeVoiceCall());

    expect(
      find.byKey(const ValueKey<String>('rain-call-audio-unavailable')),
      findsOneWidget,
    );
    expect(_findMeterCells('rain-call-audio-wave-bar-'), findsNothing);
  });

  testWidgets(
    'call overlay minimized chip restores without blocking composer',
    (WidgetTester tester) async {
      var restored = false;
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
                Positioned.fill(
                  child: RainCallOverlay(
                    state: _activeVoiceCall(),
                    surface: const CallSurfaceState.visible(
                      peerId: 'bob',
                      callId: 'call-1',
                      mode: CallSurfaceMode.minimized,
                      dock: CallSurfaceDock.bottomSafe,
                    ),
                    displayName: 'Bob',
                    onAccept: () {},
                    onReject: () {},
                    onHangUp: () {},
                    onRetry: () {},
                    onToggleMute: () {},
                    onMinimize: () {},
                    onExpand: () => restored = true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byTooltip('Restore call'), findsOneWidget);

      await tester.tap(find.byTooltip('Restore call'));
      expect(restored, isTrue);

      await tester.tap(find.text('Message composer'));
      expect(composerTapped, isTrue);
    },
  );

  testWidgets('call overlay incoming controls are wired', (
    WidgetTester tester,
  ) async {
    var accepted = false;
    var rejected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: RainCallOverlay(
                  state: const VoiceCallState(
                    phase: VoiceCallPhase.incomingRinging,
                    peerId: 'bob',
                    callId: 'call-1',
                  ),
                  surface: const CallSurfaceState.visible(
                    peerId: 'bob',
                    callId: 'call-1',
                  ),
                  displayName: 'Bob',
                  onAccept: () => accepted = true,
                  onReject: () => rejected = true,
                  onHangUp: () {},
                  onRetry: () {},
                  onToggleMute: () {},
                  onMinimize: () {},
                  onExpand: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Bob is calling'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    expect(accepted, isTrue);

    await tester.tap(find.text('Reject'));
    expect(rejected, isTrue);
  });

  testWidgets('call overlay failure shows retry and sanitized detail', (
    WidgetTester tester,
  ) async {
    var retried = false;
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: RainCallOverlay(
                  state: const VoiceCallState(
                    phase: VoiceCallPhase.failed,
                    peerId: 'bob',
                    callId: 'call-1',
                    failureReason: VoiceCallFailureReason.mediaConnectionFailed,
                    detail:
                        'Unable to RTCRtpTransceiver::setDirection: disposed.',
                  ),
                  surface: const CallSurfaceState.visible(
                    peerId: 'bob',
                    callId: 'call-1',
                  ),
                  displayName: 'Bob',
                  onAccept: () {},
                  onReject: () {},
                  onHangUp: () => dismissed = true,
                  onRetry: () => retried = true,
                  onToggleMute: () {},
                  onMinimize: () {},
                  onExpand: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.text('Call media could not connect. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('RTCRtpTransceiver'), findsNothing);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);

    await tester.tap(find.text('Dismiss'));
    expect(dismissed, isTrue);
  });

  testWidgets('call overlay fits narrow mobile layout', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: RainCallOverlay(
                  state: _activeVoiceCall(),
                  surface: const CallSurfaceState.visible(
                    peerId: 'bob',
                    callId: 'call-1',
                  ),
                  displayName: 'Bob With A Very Long Display Name',
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
        ),
      ),
    );

    expect(find.textContaining('Bob With'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Finder _findMeterCells(String prefix) {
  return find.byWidgetPredicate((Widget widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith(prefix);
  });
}

VoiceCallState _activeVoiceCall({
  VoiceAudioLevel audioLevel = const VoiceAudioLevel.unavailable(),
}) {
  return VoiceCallState(
    phase: VoiceCallPhase.active,
    peerId: 'bob',
    callId: 'call-1',
    startedAt: DateTime.now()
        .subtract(const Duration(seconds: 7))
        .millisecondsSinceEpoch,
    audioLevel: audioLevel,
  );
}

Future<void> _pumpCallOverlay(WidgetTester tester, VoiceCallState state) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: RainCallOverlay(
                state: state,
                surface: CallSurfaceState.visible(
                  peerId: state.peerId ?? 'bob',
                  callId: state.callId ?? 'call-1',
                ),
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
      ),
    ),
  );
}
