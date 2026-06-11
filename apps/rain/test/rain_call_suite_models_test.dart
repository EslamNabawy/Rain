/// # rain_call_suite_models_test.dart
///
/// Tests for call suite model mapping from voice call state to suite surface configuration. Validates incoming/outgoing/active/ended suite modes, stage kinds, control models, and capability filtering.
///
/// **Key types:** CallSuiteSurfaceMode, CallSuiteStageKind, CallSuiteControlModel, CallSuiteControlAction, VideoPrimaryRole, CallControlCapability
///
/// **Depends on:** flutter_test, rain voice_call_state, rain_call_suite_models, rain_call_surface_providers

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

  test('outgoing setup phases stay in outgoing suite mode', () {
    final connectingPeer = _suiteFor(
      _call(phase: VoiceCallPhase.connectingPeer),
    );
    final connectingMedia = _suiteFor(
      _call(phase: VoiceCallPhase.connectingMedia),
    );

    expect(connectingPeer.surfaceMode, CallSuiteSurfaceMode.outgoing);
    expect(connectingMedia.surfaceMode, CallSuiteSurfaceMode.outgoing);
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

  test('failed outgoing video uses failed suite with retry and close only', () {
    final suite = _suiteFor(
      _call(
        phase: VoiceCallPhase.failed,
        mediaMode: CallMediaMode.video,
      ).copyWith(
        failureReason: VoiceCallFailureReason.mediaConnectionFailed,
        detail: 'Unable to RTCRtpTransceiver::setDirection: disposed.',
      ),
      surface: const CallSurfaceState.visible(
        peerId: 'bob',
        callId: 'call-1',
        mediaMode: CallMediaMode.video,
        mode: CallSurfaceMode.managerOnly,
      ),
    );

    expect(suite.surfaceMode, CallSuiteSurfaceMode.failed);
    expect(suite.stage.kind, CallSuiteStageKind.video);
    expect(suite.showsFullscreenWorkspace, isTrue);
    expect(suite.showsManagerBar, isFalse);
    expect(suite.showsFloatingSurface, isFalse);
    expect(
      suite.controls.map((CallSuiteControlModel control) => control.action),
      <CallSuiteControlAction>[
        CallSuiteControlAction.retry,
        CallSuiteControlAction.close,
      ],
    );
    expect(suite.overflowControls, isEmpty);
  });

  test('failed incoming network-loss call is dismiss only, not retry spam', () {
    final suite = _suiteFor(
      _call(
        phase: VoiceCallPhase.failed,
        isOutgoing: false,
      ).copyWith(failureReason: VoiceCallFailureReason.networkLost),
    );

    expect(suite.surfaceMode, CallSuiteSurfaceMode.failed);
    expect(
      suite.controls.map((CallSuiteControlModel control) => control.action),
      <CallSuiteControlAction>[CallSuiteControlAction.close],
    );
  });

  test('narrow video dock keeps mic camera and hangup visible', () {
    final suite = _suiteFor(
      _call(mediaMode: CallMediaMode.video),
      outputRouteOptions: const <VoiceCallOutputRouteOption>[
        VoiceCallOutputRouteOption(
          target: CallAudioOutputTarget.systemDefault(),
          label: 'System default',
          icon: IconData(0),
        ),
        VoiceCallOutputRouteOption(
          target: CallAudioOutputTarget.androidSpeakerphone(),
          label: 'Speaker',
          icon: IconData(1),
        ),
      ],
      layout: const CallSuiteLayoutSpec(
        viewportSize: Size(320, 620),
        safePadding: EdgeInsets.zero,
        isDesktop: false,
        lowPower: false,
      ),
    );

    expect(
      suite.controls.map((CallSuiteControlModel control) => control.action),
      <CallSuiteControlAction>[
        CallSuiteControlAction.microphone,
        CallSuiteControlAction.camera,
        CallSuiteControlAction.hangUp,
      ],
    );
    expect(
      suite.overflowControls.map(
        (CallSuiteControlModel control) => control.action,
      ),
      containsAll(<CallSuiteControlAction>[
        CallSuiteControlAction.deafen,
        CallSuiteControlAction.outputRoute,
        CallSuiteControlAction.exitFullscreen,
        CallSuiteControlAction.minimize,
      ]),
    );
  });
}

CallSuitePresentationState _suiteFor(
  VoiceCallState call, {
  CallSurfaceState? surface,
  CallEndPresentationState endPresentation =
      const CallEndPresentationState.hidden(),
  List<CallControlCapability>? capabilities,
  List<VoiceCallOutputRouteOption> outputRouteOptions =
      const <VoiceCallOutputRouteOption>[],
  CallSuiteLayoutSpec layout = const CallSuiteLayoutSpec(
    viewportSize: Size(390, 720),
    safePadding: EdgeInsets.zero,
    isDesktop: false,
    lowPower: false,
  ),
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
    outputRouteOptions: outputRouteOptions,
    layout: layout,
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
