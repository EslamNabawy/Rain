import 'package:flutter/material.dart';

import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';

enum CallSuiteSurfaceMode {
  hidden,
  incoming,
  outgoing,
  activePopup,
  activeFullscreen,
  minimizedBar,
  videoPip,
  ended,
  failed,
}

enum CallSuiteStageKind { voice, video }

enum CallSuiteControlAction {
  accept,
  decline,
  retry,
  close,
  callAgain,
  microphone,
  camera,
  switchCamera,
  deafen,
  outputRoute,
  hangUp,
  minimize,
  restore,
  fullscreen,
  exitFullscreen,
  more,
}

enum CallSuiteDockDensity { regular, compact, narrow }

final class CallSuiteStageModel {
  const CallSuiteStageModel({
    required this.kind,
    this.videoPrimaryRole = VideoPrimaryRole.remote,
    this.showsLocalPreview = false,
  });

  final CallSuiteStageKind kind;
  final VideoPrimaryRole videoPrimaryRole;
  final bool showsLocalPreview;

  bool get isVideo => kind == CallSuiteStageKind.video;
}

final class CallSuiteControlModel {
  const CallSuiteControlModel({
    required this.action,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.semanticLabel,
    this.enabled = true,
    this.danger = false,
    this.primary = false,
    this.capability,
  });

  final CallSuiteControlAction action;
  final IconData icon;
  final String label;
  final String tooltip;
  final String semanticLabel;
  final bool enabled;
  final bool danger;
  final bool primary;
  final CallControlCapability? capability;
}

final class CallSuiteLayoutSpec {
  const CallSuiteLayoutSpec({
    required this.viewportSize,
    required this.safePadding,
    required this.isDesktop,
    required this.lowPower,
  });

  final Size viewportSize;
  final EdgeInsets safePadding;
  final bool isDesktop;
  final bool lowPower;

  CallSuiteDockDensity get dockDensity {
    if (viewportSize.width < 360) {
      return CallSuiteDockDensity.narrow;
    }
    if (viewportSize.width < 520) {
      return CallSuiteDockDensity.compact;
    }
    return CallSuiteDockDensity.regular;
  }

  double get managerTop => safePadding.top + 8;

  double get managerHorizontalMargin => isDesktop ? 20 : 12;

  double get popupMaxWidth {
    if (viewportSize.width < 420) {
      return (viewportSize.width - 24).clamp(280, 380).toDouble();
    }
    return isDesktop ? 720 : 420;
  }

  double get dockMaxWidth {
    return switch (dockDensity) {
      CallSuiteDockDensity.narrow => 300,
      CallSuiteDockDensity.compact => 380,
      CallSuiteDockDensity.regular => 560,
    };
  }
}

final class CallSuitePresentationState {
  const CallSuitePresentationState({
    required this.surfaceMode,
    required this.stage,
    required this.displayName,
    required this.routeSummary,
    required this.controls,
    required this.overflowControls,
    this.callState,
    this.surface,
    this.endSummary,
  });

  factory CallSuitePresentationState.from({
    required VoiceCallState callState,
    required CallSurfaceState surface,
    required CallEndPresentationState endPresentation,
    required String displayName,
    String? routeSummary,
    required List<CallControlCapability> controlCapabilities,
    required List<VoiceCallOutputRouteOption> outputRouteOptions,
    required CallSuiteLayoutSpec layout,
  }) {
    if (callState.phase == VoiceCallPhase.idle) {
      final summary = endPresentation.summary;
      if (summary == null) {
        return CallSuitePresentationState.hidden(displayName: displayName);
      }
      return CallSuitePresentationState(
        surfaceMode: CallSuiteSurfaceMode.ended,
        stage: CallSuiteStageModel(
          kind: summary.isVideo
              ? CallSuiteStageKind.video
              : CallSuiteStageKind.voice,
          videoPrimaryRole: endPresentation.videoPrimaryRole,
          showsLocalPreview: summary.isVideo && endPresentation.isFullscreen,
        ),
        displayName: displayName,
        routeSummary: routeSummary,
        controls: _endedControls(summary),
        overflowControls: const <CallSuiteControlModel>[],
        endSummary: summary,
      );
    }

    final mode = _surfaceModeFor(callState, surface);
    final stage = CallSuiteStageModel(
      kind: callState.isVideo
          ? CallSuiteStageKind.video
          : CallSuiteStageKind.voice,
      videoPrimaryRole: surface.videoPrimaryRole,
      showsLocalPreview:
          callState.isVideo && surface.mode != CallSurfaceMode.pip,
    );
    final controls = _controlsFor(
      callState: callState,
      surface: surface,
      capabilities: controlCapabilities,
      outputRouteOptions: outputRouteOptions,
      layout: layout,
    );
    return CallSuitePresentationState(
      surfaceMode: mode,
      stage: stage,
      displayName: displayName,
      routeSummary: routeSummary,
      controls: controls.visible,
      overflowControls: controls.overflow,
      callState: callState,
      surface: surface,
    );
  }

  const CallSuitePresentationState.hidden({required this.displayName})
    : surfaceMode = CallSuiteSurfaceMode.hidden,
      stage = const CallSuiteStageModel(kind: CallSuiteStageKind.voice),
      routeSummary = null,
      controls = const <CallSuiteControlModel>[],
      overflowControls = const <CallSuiteControlModel>[],
      callState = null,
      surface = null,
      endSummary = null;

  final CallSuiteSurfaceMode surfaceMode;
  final CallSuiteStageModel stage;
  final String displayName;
  final String? routeSummary;
  final List<CallSuiteControlModel> controls;
  final List<CallSuiteControlModel> overflowControls;
  final VoiceCallState? callState;
  final CallSurfaceState? surface;
  final CallEndSummary? endSummary;

  bool get isVisible => surfaceMode != CallSuiteSurfaceMode.hidden;

  bool get showsManagerBar =>
      surfaceMode == CallSuiteSurfaceMode.minimizedBar ||
      surfaceMode == CallSuiteSurfaceMode.videoPip;

  bool get showsFullscreenWorkspace =>
      surfaceMode == CallSuiteSurfaceMode.activeFullscreen;

  bool get showsFloatingSurface =>
      surfaceMode == CallSuiteSurfaceMode.incoming ||
      surfaceMode == CallSuiteSurfaceMode.outgoing ||
      surfaceMode == CallSuiteSurfaceMode.activePopup ||
      surfaceMode == CallSuiteSurfaceMode.failed ||
      surfaceMode == CallSuiteSurfaceMode.videoPip;

  bool get showsEndedSurface => surfaceMode == CallSuiteSurfaceMode.ended;

  bool get isFullscreenEnded =>
      showsEndedSurface && endSummary?.isVideo == true;
}

final class _SuiteControls {
  const _SuiteControls({required this.visible, required this.overflow});

  final List<CallSuiteControlModel> visible;
  final List<CallSuiteControlModel> overflow;
}

CallSuiteSurfaceMode _surfaceModeFor(
  VoiceCallState callState,
  CallSurfaceState surface,
) {
  return switch (callState.phase) {
    VoiceCallPhase.incomingRinging => CallSuiteSurfaceMode.incoming,
    VoiceCallPhase.outgoingRinging => CallSuiteSurfaceMode.outgoing,
    VoiceCallPhase.connectingPeer when callState.isOutgoing =>
      CallSuiteSurfaceMode.outgoing,
    VoiceCallPhase.connectingMedia when callState.isOutgoing =>
      CallSuiteSurfaceMode.outgoing,
    VoiceCallPhase.failed => CallSuiteSurfaceMode.failed,
    _ => switch (surface.mode) {
      CallSurfaceMode.fullscreen => CallSuiteSurfaceMode.activeFullscreen,
      CallSurfaceMode.managerOnly => CallSuiteSurfaceMode.minimizedBar,
      CallSurfaceMode.pip =>
        callState.isVideo
            ? CallSuiteSurfaceMode.videoPip
            : CallSuiteSurfaceMode.minimizedBar,
      CallSurfaceMode.expanded => CallSuiteSurfaceMode.activePopup,
    },
  };
}

_SuiteControls _controlsFor({
  required VoiceCallState callState,
  required CallSurfaceState surface,
  required List<CallControlCapability> capabilities,
  required List<VoiceCallOutputRouteOption> outputRouteOptions,
  required CallSuiteLayoutSpec layout,
}) {
  if (callState.phase == VoiceCallPhase.incomingRinging) {
    return const _SuiteControls(
      visible: <CallSuiteControlModel>[
        CallSuiteControlModel(
          action: CallSuiteControlAction.decline,
          icon: Icons.phone_disabled,
          label: 'Decline',
          tooltip: 'Decline call',
          semanticLabel: 'Decline call',
          danger: true,
        ),
        CallSuiteControlModel(
          action: CallSuiteControlAction.accept,
          icon: Icons.call,
          label: 'Answer',
          tooltip: 'Answer call',
          semanticLabel: 'Answer call',
          primary: true,
        ),
      ],
      overflow: <CallSuiteControlModel>[],
    );
  }

  if (callState.phase == VoiceCallPhase.failed) {
    final visible = <CallSuiteControlModel>[
      if (rainVoiceCallCanRetry(callState))
        const CallSuiteControlModel(
          action: CallSuiteControlAction.retry,
          icon: Icons.refresh,
          label: 'Retry',
          tooltip: 'Retry call',
          semanticLabel: 'Retry call',
          primary: true,
        ),
      const CallSuiteControlModel(
        action: CallSuiteControlAction.close,
        icon: Icons.close,
        label: 'Close',
        tooltip: 'Dismiss call',
        semanticLabel: 'Dismiss call',
      ),
    ];
    return _SuiteControls(
      visible: visible,
      overflow: const <CallSuiteControlModel>[],
    );
  }

  final orderedCapabilities = capabilities
      .where((CallControlCapability capability) {
        if (capability == CallControlCapability.outputRoute) {
          return outputRouteOptions.length > 1;
        }
        return true;
      })
      .toList(growable: false);
  final capabilityControls = <CallSuiteControlModel>[
    for (final capability in orderedCapabilities)
      _controlForCapability(callState, capability),
  ];
  final surfaceControls = <CallSuiteControlModel>[
    if (surface.mode == CallSurfaceMode.fullscreen)
      const CallSuiteControlModel(
        action: CallSuiteControlAction.exitFullscreen,
        icon: Icons.fullscreen_exit,
        label: 'Exit',
        tooltip: 'Exit fullscreen',
        semanticLabel: 'Exit fullscreen',
      )
    else if (callState.isVideo)
      const CallSuiteControlModel(
        action: CallSuiteControlAction.fullscreen,
        icon: Icons.fullscreen,
        label: 'Full',
        tooltip: 'Fullscreen video',
        semanticLabel: 'Fullscreen video',
      ),
    if (surface.mode != CallSurfaceMode.managerOnly)
      const CallSuiteControlModel(
        action: CallSuiteControlAction.minimize,
        icon: Icons.keyboard_arrow_down,
        label: 'Minimize',
        tooltip: 'Minimize call',
        semanticLabel: 'Minimize call',
      )
    else
      const CallSuiteControlModel(
        action: CallSuiteControlAction.restore,
        icon: Icons.open_in_full,
        label: 'Restore',
        tooltip: 'Restore call',
        semanticLabel: 'Restore call',
      ),
  ];
  final all = <CallSuiteControlModel>[
    ...capabilityControls,
    ...surfaceControls,
  ];
  final maxVisible = switch (layout.dockDensity) {
    CallSuiteDockDensity.narrow => 3,
    CallSuiteDockDensity.compact => 4,
    CallSuiteDockDensity.regular => all.length,
  };
  if (all.length <= maxVisible) {
    return _SuiteControls(
      visible: all,
      overflow: const <CallSuiteControlModel>[],
    );
  }
  final primary = <CallSuiteControlModel>[
    for (final action in <CallSuiteControlAction>[
      CallSuiteControlAction.microphone,
      if (callState.isVideo) CallSuiteControlAction.camera,
      CallSuiteControlAction.hangUp,
    ])
      if (all.any((CallSuiteControlModel control) => control.action == action))
        all.firstWhere(
          (CallSuiteControlModel control) => control.action == action,
        ),
  ];
  final visible = primary.take(maxVisible).toList(growable: false);
  final overflow = all
      .where((CallSuiteControlModel control) => !visible.contains(control))
      .toList(growable: false);
  return _SuiteControls(visible: visible, overflow: overflow);
}

CallSuiteControlModel _controlForCapability(
  VoiceCallState state,
  CallControlCapability capability,
) {
  final visual = rainVoiceCallControlVisual(state, capability);
  final action = switch (capability) {
    CallControlCapability.microphone => CallSuiteControlAction.microphone,
    CallControlCapability.camera => CallSuiteControlAction.camera,
    CallControlCapability.switchCamera => CallSuiteControlAction.switchCamera,
    CallControlCapability.deafen => CallSuiteControlAction.deafen,
    CallControlCapability.outputRoute => CallSuiteControlAction.outputRoute,
    CallControlCapability.hangUp => CallSuiteControlAction.hangUp,
  };
  return CallSuiteControlModel(
    action: action,
    icon: visual.icon,
    label: _shortLabelFor(action),
    tooltip: visual.tooltip,
    semanticLabel: visual.tooltip,
    enabled: state.isActive || capability == CallControlCapability.hangUp,
    danger: visual.danger,
    primary:
        capability == CallControlCapability.microphone ||
        capability == CallControlCapability.hangUp,
    capability: capability,
  );
}

List<CallSuiteControlModel> _endedControls(CallEndSummary summary) {
  return <CallSuiteControlModel>[
    const CallSuiteControlModel(
      action: CallSuiteControlAction.close,
      icon: Icons.close,
      label: 'Close',
      tooltip: 'Close ended call',
      semanticLabel: 'Close ended call',
    ),
    CallSuiteControlModel(
      action: CallSuiteControlAction.callAgain,
      icon: summary.isVideo ? Icons.videocam_outlined : Icons.call_outlined,
      label: 'Call again',
      tooltip: 'Call again',
      semanticLabel: 'Call again',
      primary: true,
    ),
  ];
}

String _shortLabelFor(CallSuiteControlAction action) {
  return switch (action) {
    CallSuiteControlAction.accept => 'Answer',
    CallSuiteControlAction.decline => 'Decline',
    CallSuiteControlAction.retry => 'Retry',
    CallSuiteControlAction.close => 'Close',
    CallSuiteControlAction.callAgain => 'Again',
    CallSuiteControlAction.microphone => 'Mic',
    CallSuiteControlAction.camera => 'Camera',
    CallSuiteControlAction.switchCamera => 'Flip',
    CallSuiteControlAction.deafen => 'Deafen',
    CallSuiteControlAction.outputRoute => 'Output',
    CallSuiteControlAction.hangUp => 'End',
    CallSuiteControlAction.minimize => 'Minimize',
    CallSuiteControlAction.restore => 'Restore',
    CallSuiteControlAction.fullscreen => 'Full',
    CallSuiteControlAction.exitFullscreen => 'Exit',
    CallSuiteControlAction.more => 'More',
  };
}
