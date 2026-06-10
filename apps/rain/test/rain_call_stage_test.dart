import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_audio_level.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/widgets/calls/rain_call_stage.dart';

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
  required CallMediaMode mediaMode,
  bool hasRemoteVideo = false,
  bool hasLocalVideo = false,
  VoiceAudioLevel audioLevel = const VoiceAudioLevel.unavailable(),
}) {
  return VoiceCallState(
    phase: VoiceCallPhase.active,
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
