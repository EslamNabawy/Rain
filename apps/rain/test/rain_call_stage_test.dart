import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_audio_level.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/widgets/calls/rain_call_stage.dart';
import 'package:rain/presentation/widgets/calls/rain_connecting_pulse.dart';

void main() {
  testWidgets('video call renders remote as primary and local as preview', (
    WidgetTester tester,
  ) async {
    await _pumpVideoCallStage(
      tester,
      hasRemoteVideo: true,
      hasLocalVideo: true,
    );

    expect(find.byKey(rainRemotePrimaryVideoKey), findsOneWidget);
    expect(find.byKey(rainLocalPreviewVideoKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('rain-call-remote-video-placeholder')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('rain-call-local-video-placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('tapping local preview swaps primary role', (
    WidgetTester tester,
  ) async {
    await _pumpVideoCallStage(
      tester,
      hasRemoteVideo: true,
      hasLocalVideo: true,
    );

    await tester.tap(find.byKey(rainLocalPreviewVideoKey));
    await tester.pumpAndSettle();

    expect(find.byKey(rainLocalPrimaryVideoKey), findsOneWidget);
    expect(find.byKey(rainRemotePreviewVideoKey), findsOneWidget);
  });

  testWidgets('missing remote video shows waiting state', (
    WidgetTester tester,
  ) async {
    await _pumpVideoCallStage(
      tester,
      hasRemoteVideo: false,
      hasLocalVideo: true,
    );

    expect(find.text('Waiting for video'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('rain-call-remote-video-placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('voice-only call renders Peer Core audio stage', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainCallStage(
            state: _callState(mediaMode: CallMediaMode.audio),
            accent: Colors.teal,
          ),
        ),
      ),
    );

    expect(find.byKey(rainVoiceOnlyStageKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('rain-call-audio-stage')),
      findsOneWidget,
    );
  });

  testWidgets('voice stage emits waves from Peer Core mark', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainCallStage(
            state: _callState(
              mediaMode: CallMediaMode.audio,
              audioLevel: VoiceAudioLevel.available(
                remoteLevel: 0.8,
                localLevel: 0,
                updatedAt: 1,
                source: VoiceAudioLevelSource.audioLevel,
              ),
            ),
            accent: Colors.teal,
          ),
        ),
      ),
    );

    expect(find.byKey(rainCallAudioEmitterKey), findsOneWidget);
    expect(find.byKey(rainCallAudioEmitterMarkKey), findsOneWidget);
    expect(find.byKey(const Key('rain-detached-equalizer-bars')), findsNothing);
  });

  for (final phase in <VoiceCallPhase>[
    VoiceCallPhase.connectingPeer,
    VoiceCallPhase.outgoingRinging,
    VoiceCallPhase.connectingMedia,
  ]) {
    testWidgets('connecting pulse animates during ${phase.name}', (
      WidgetTester tester,
    ) async {
      await _pumpVoiceStage(tester, _callState(phase: phase));

      expect(find.byKey(rainConnectingPulseAnimatedKey), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
    });
  }

  testWidgets('connecting pulse animates while media reconnects', (
    WidgetTester tester,
  ) async {
    await _pumpVoiceStage(tester, _callState(mediaReconnecting: true));

    expect(find.byKey(rainConnectingPulseAnimatedKey), findsOneWidget);
  });

  testWidgets('connecting pulse is gone once the call is connected', (
    WidgetTester tester,
  ) async {
    await _pumpVoiceStage(tester, _callState());

    expect(find.byKey(rainConnectingPulseAnimatedKey), findsNothing);
    expect(find.byKey(rainConnectingPulseStaticKey), findsNothing);
  });

  testWidgets('connecting pulse is static on the low-power tier', (
    WidgetTester tester,
  ) async {
    await _pumpVoiceStage(
      tester,
      _callState(phase: VoiceCallPhase.connectingPeer),
      profile: const RainPerformanceProfile(
        tier: RainPerformanceTier.lowPower,
        reason: 'test',
        abiName: 'armeabi-v7a',
      ),
    );

    expect(find.byKey(rainConnectingPulseStaticKey), findsOneWidget);
    expect(find.byKey(rainConnectingPulseAnimatedKey), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('connecting pulse keeps the glyph layout size', (
    WidgetTester tester,
  ) async {
    await _pumpVoiceStage(
      tester,
      _callState(phase: VoiceCallPhase.connectingPeer),
    );

    expect(
      tester.getSize(find.byType(RainConnectingPulse)),
      const Size.square(116),
    );
  });
}

Future<void> _pumpVoiceStage(
  WidgetTester tester,
  VoiceCallState state, {
  RainPerformanceProfile profile = const RainPerformanceProfile(
    tier: RainPerformanceTier.standard,
    reason: 'test',
    abiName: 'x86_64',
  ),
}) async {
  await tester.pumpWidget(
    RainPerformanceScope(
      profile: profile,
      child: MaterialApp(
        home: Scaffold(
          body: RainCallStage(state: state, accent: Colors.teal),
        ),
      ),
    ),
  );
}

Future<void> _pumpVideoCallStage(
  WidgetTester tester, {
  required bool hasRemoteVideo,
  required bool hasLocalVideo,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: _VideoStageHarness(
          state: _callState(
            mediaMode: CallMediaMode.video,
            hasRemoteVideo: hasRemoteVideo,
            hasLocalVideo: hasLocalVideo,
          ),
        ),
      ),
    ),
  );
}

class _VideoStageHarness extends StatefulWidget {
  const _VideoStageHarness({required this.state});

  final VoiceCallState state;

  @override
  State<_VideoStageHarness> createState() => _VideoStageHarnessState();
}

class _VideoStageHarnessState extends State<_VideoStageHarness> {
  VideoPrimaryRole _role = VideoPrimaryRole.remote;

  @override
  Widget build(BuildContext context) {
    return RainCallStage(
      state: widget.state,
      accent: Colors.teal,
      primaryRole: _role,
      onTogglePrimaryRole: () {
        setState(() {
          _role = _role == VideoPrimaryRole.remote
              ? VideoPrimaryRole.local
              : VideoPrimaryRole.remote;
        });
      },
    );
  }
}

VoiceCallState _callState({
  CallMediaMode mediaMode = CallMediaMode.audio,
  VoiceCallPhase phase = VoiceCallPhase.active,
  bool mediaReconnecting = false,
  bool hasRemoteVideo = false,
  bool hasLocalVideo = false,
  VoiceAudioLevel audioLevel = const VoiceAudioLevel.unavailable(),
}) {
  return VoiceCallState(
    phase: phase,
    mediaReconnecting: mediaReconnecting,
    peerId: 'bob',
    callId: 'call-1',
    mediaMode: mediaMode,
    hasRemoteVideo: hasRemoteVideo,
    hasLocalVideo: hasLocalVideo,
    audioLevel: audioLevel,
    startedAt: DateTime.now()
        .subtract(const Duration(seconds: 7))
        .millisecondsSinceEpoch,
  );
}
