import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/widgets/calls/rain_call_suite_models.dart';

void main() {
  test('incoming call maps to incoming suite surface with answer actions', () {
    final suite = _suiteFor(
      _call(phase: VoiceCallPhase.incomingRinging, isOutgoing: false),
    );

    expect(suite.surfaceMode, CallSuiteSurfaceMode.incoming);
    expect(suite.stage.kind, CallSuiteStageKind.voice);
    expect(
      suite.controls.map((CallSuiteControlModel control) => control.action),
      <CallSuiteControlAction>[
        CallSuiteControlAction.decline,
        CallSuiteControlAction.accept,
      ],
    );
  });

  test('active video fullscreen uses video stage and hides manager mode', () {
    final suite = _suiteFor(
      _call(mediaMode: CallMediaMode.video),
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mediaMode: CallMediaMode.video,
        mode: CallSurfaceMode.fullscreen,
      ),
    );

    expect(suite.surfaceMode, CallSuiteSurfaceMode.activeFullscreen);
    expect(suite.stage.kind, CallSuiteStageKind.video);
    expect(suite.stage.videoPrimaryRole, VideoPrimaryRole.remote);
    expect(suite.showsFullscreenWorkspace, isTrue);
    expect(suite.showsManagerBar, isFalse);
  });

  test(
    'capability-filtered controls hide unsupported output and camera switch',
    () {
      final suite = _suiteFor(
        _call(mediaMode: CallMediaMode.video),
        capabilities: const <CallControlCapability>[
          CallControlCapability.microphone,
          CallControlCapability.camera,
          CallControlCapability.hangUp,
        ],
      );

      final actions = suite.controls
          .map((CallSuiteControlModel control) => control.action)
          .toSet();
      expect(actions, contains(CallSuiteControlAction.microphone));
      expect(actions, contains(CallSuiteControlAction.camera));
      expect(actions, contains(CallSuiteControlAction.hangUp));
      expect(actions, isNot(contains(CallSuiteControlAction.outputRoute)));
      expect(actions, isNot(contains(CallSuiteControlAction.switchCamera)));
    },
  );

  test('idle runtime can still show ended call presentation', () {
    final summary = CallEndSummary(
      peerId: 'bob',
      peerLabel: 'Bob',
      mediaMode: CallMediaMode.audio,
      duration: const Duration(seconds: 42),
      initiator: CallEndInitiator.remote,
      reason: 'Ended by peer.',
      endedAt: DateTime.fromMillisecondsSinceEpoch(1),
    );
    final suite = _suiteFor(
      const VoiceCallState.idle(),
      endPresentation: CallEndPresentationState(summary: summary),
    );

    expect(suite.surfaceMode, CallSuiteSurfaceMode.ended);
    expect(suite.endSummary, summary);
    expect(
      suite.controls.map((CallSuiteControlModel control) => control.action),
      <CallSuiteControlAction>[
        CallSuiteControlAction.close,
        CallSuiteControlAction.callAgain,
      ],
    );
  });

  test('video pip exposes manager bar and floating video surface together', () {
    final suite = _suiteFor(
      _call(mediaMode: CallMediaMode.video),
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mediaMode: CallMediaMode.video,
        mode: CallSurfaceMode.pip,
        restoreMode: CallSurfaceMode.pip,
      ),
    );

    expect(suite.surfaceMode, CallSuiteSurfaceMode.videoPip);
    expect(suite.showsManagerBar, isTrue);
    expect(suite.showsFloatingSurface, isTrue);
  });
}

CallSuitePresentationState _suiteFor(
  VoiceCallState call, {
  CallSurfaceState? surface,
  CallEndPresentationState endPresentation =
      const CallEndPresentationState.hidden(),
  List<CallControlCapability>? capabilities,
}) {
  return CallSuitePresentationState.from(
    callState: call,
    surface:
        surface ??
        CallSurfaceState.visible(
          peerId: call.peerId,
          callId: call.callId,
          mediaMode: call.mediaMode,
        ),
    endPresentation: endPresentation,
    displayName: 'Bob',
    controlCapabilities: capabilities ?? call.controlCapabilities,
    outputRouteOptions: const <VoiceCallOutputRouteOption>[],
    layout: const CallSuiteLayoutSpec(
      viewportSize: Size(390, 720),
      safePadding: EdgeInsets.zero,
      isDesktop: false,
      lowPower: false,
    ),
  );
}

VoiceCallState _call({
  VoiceCallPhase phase = VoiceCallPhase.active,
  CallMediaMode mediaMode = CallMediaMode.audio,
  bool isOutgoing = true,
}) {
  return VoiceCallState(
    phase: phase,
    peerId: 'bob',
    callId: 'call-1',
    mediaMode: mediaMode,
    isOutgoing: isOutgoing,
    startedAt: 1,
    updatedAt: 2,
  );
}
