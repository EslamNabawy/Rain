import 'package:flutter/material.dart';

import 'package:rain/application/runtime/video_call_renderers.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/widgets/calls/rain_call_ended_surface.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';
import 'package:rain/presentation/widgets/calls/rain_call_manager_bar.dart';
import 'package:rain/presentation/widgets/calls/rain_call_overlay.dart';
import 'package:rain/presentation/widgets/calls/rain_call_stage.dart';
import 'package:rain/presentation/widgets/calls/rain_call_suite_models.dart';
import 'package:rain/presentation/widgets/calls/rain_call_workspace.dart';

class RainCallSuiteLayer extends StatelessWidget {
  const RainCallSuiteLayer({
    super.key,
    required this.state,
    required this.surface,
    required this.endPresentation,
    required this.displayName,
    this.gender,
    this.routeSummary,
    this.videoRenderers,
    required this.contentLeftInset,
    required this.isDesktop,
    required this.lowPower,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
    this.onToggleDeafen,
    this.onToggleCamera,
    this.onSwitchCamera,
    this.onSelectOutputRoute,
    required this.controlCapabilities,
    required this.outputRouteOptions,
    required this.onMinimize,
    required this.onRestore,
    required this.onFullscreen,
    required this.onExitFullscreen,
    this.onToggleVideoPrimaryRole,
    this.friendsPanel,
    this.showFriendsPanel = false,
    this.friendsPanelCollapsed = false,
    this.friendsPanelWidth = 280,
    this.onToggleFriendsPanel,
    this.onResizeFriendsPanel,
    this.onMoveFloating,
    this.onClampFloating,
    required this.onCloseEnded,
    required this.onCallAgain,
  });

  final VoiceCallState state;
  final CallSurfaceState surface;
  final CallEndPresentationState endPresentation;
  final String displayName;
  final String? gender;
  final String? routeSummary;
  final VideoCallRenderers? videoRenderers;
  final double contentLeftInset;
  final bool isDesktop;
  final bool lowPower;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onSwitchCamera;
  final ValueChanged<CallAudioOutputTarget>? onSelectOutputRoute;
  final List<CallControlCapability> controlCapabilities;
  final List<VoiceCallOutputRouteOption> outputRouteOptions;
  final VoidCallback onMinimize;
  final VoidCallback onRestore;
  final VoidCallback onFullscreen;
  final VoidCallback onExitFullscreen;
  final VoidCallback? onToggleVideoPrimaryRole;
  final Widget? friendsPanel;
  final bool showFriendsPanel;
  final bool friendsPanelCollapsed;
  final double friendsPanelWidth;
  final VoidCallback? onToggleFriendsPanel;
  final ValueChanged<double>? onResizeFriendsPanel;
  final void Function(
    Offset delta,
    Size viewportSize,
    EdgeInsets safePadding,
    Size panelSize,
  )?
  onMoveFloating;
  final void Function(
    Size viewportSize,
    EdgeInsets safePadding,
    Size panelSize,
  )?
  onClampFloating;
  final VoidCallback onCloseEnded;
  final ValueChanged<CallEndSummary> onCallAgain;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final layout = CallSuiteLayoutSpec(
          viewportSize: Size(constraints.maxWidth, constraints.maxHeight),
          safePadding: MediaQuery.viewPaddingOf(context),
          isDesktop: isDesktop,
          lowPower: lowPower,
        );
        final suite = CallSuitePresentationState.from(
          callState: state,
          surface: surface,
          endPresentation: endPresentation,
          displayName: displayName,
          routeSummary: routeSummary,
          controlCapabilities: controlCapabilities,
          outputRouteOptions: outputRouteOptions,
          layout: layout,
        );
        if (!suite.isVisible) {
          return const SizedBox.shrink();
        }

        final contentInset = contentLeftInset.clamp(0, constraints.maxWidth);
        return Stack(
          key: const ValueKey<String>('rain-call-suite-layer'),
          children: <Widget>[
            if (suite.showsFullscreenWorkspace)
              Positioned.fill(child: _buildFullscreenWorkspace(context)),
            if (suite.showsFloatingSurface &&
                !suite.showsFullscreenWorkspace &&
                state.phase != VoiceCallPhase.idle)
              Positioned.fill(
                left: contentInset.toDouble(),
                child: _buildFloatingSurface(),
              ),
            if (suite.showsManagerBar && state.phase != VoiceCallPhase.idle)
              Positioned(
                left: contentInset.toDouble(),
                right: 0,
                top: layout.managerTop,
                child: RainCallManagerBar(
                  state: state,
                  surface: surface,
                  displayName: displayName,
                  gender: gender,
                  onToggleMute: onToggleMute,
                  onToggleCamera: onToggleCamera,
                  onToggleDeafen: onToggleDeafen,
                  onRestore: onRestore,
                  onFullscreen: onFullscreen,
                  onHangUp: state.phase == VoiceCallPhase.incomingRinging
                      ? onReject
                      : onHangUp,
                ),
              ),
            if (suite.showsEndedSurface && suite.endSummary != null)
              Positioned.fill(
                left: suite.isFullscreenEnded ? 0 : contentInset.toDouble(),
                child: RainCallEndedSurface(
                  summary: suite.endSummary!,
                  fullscreen: suite.isFullscreenEnded,
                  onClose: onCloseEnded,
                  onCallAgain: () => onCallAgain(suite.endSummary!),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFullscreenWorkspace(BuildContext context) {
    return RainCallWorkspace(
      callState: state,
      peerLabel: displayName,
      qualityText: routeSummary,
      stage: RainCallStage(
        state: state,
        accent: rainVoiceCallAccent(context, state),
        renderers: videoRenderers,
        layout: RainCallStageLayout.fullscreen,
        primaryRole: surface.videoPrimaryRole,
        onTogglePrimaryRole: onToggleVideoPrimaryRole,
      ),
      controls: RainCallControlDock(
        dockKey: const ValueKey<String>('rain-call-fullscreen-controls'),
        state: state,
        onAccept: onAccept,
        onReject: onReject,
        onHangUp: onHangUp,
        onRetry: onRetry,
        onToggleMute: onToggleMute,
        onToggleDeafen: onToggleDeafen,
        onToggleCamera: onToggleCamera,
        onSwitchCamera: onSwitchCamera,
        onSelectOutputRoute: onSelectOutputRoute,
        controlCapabilities: controlCapabilities,
        outputRouteOptions: outputRouteOptions,
        trailingControls: <Widget>[
          IconButton.filledTonal(
            tooltip: 'Exit fullscreen',
            onPressed: onExitFullscreen,
            icon: const Icon(Icons.fullscreen_exit),
          ),
        ],
      ),
      showDesktopSidePanel: showFriendsPanel && isDesktop,
      onExitFullscreen: onExitFullscreen,
      sidePanel: friendsPanel,
      sidePanelCollapsed: friendsPanelCollapsed,
      sidePanelWidth: friendsPanelWidth,
      onToggleSidePanel: onToggleFriendsPanel,
      onResizeSidePanel: onResizeFriendsPanel,
    );
  }

  Widget _buildFloatingSurface() {
    return RainCallOverlay(
      state: state,
      surface: surface,
      displayName: displayName,
      gender: gender,
      routeSummary: routeSummary,
      videoRenderers: videoRenderers,
      onAccept: onAccept,
      onReject: onReject,
      onHangUp: onHangUp,
      onRetry: onRetry,
      onToggleMute: onToggleMute,
      onToggleDeafen: onToggleDeafen,
      onToggleCamera: onToggleCamera,
      onSwitchCamera: onSwitchCamera,
      onSelectOutputRoute: onSelectOutputRoute,
      controlCapabilities: controlCapabilities,
      outputRouteOptions: outputRouteOptions,
      onMinimize: onMinimize,
      onExpand: onRestore,
      onToggleVideoPrimaryRole: onToggleVideoPrimaryRole,
      onFullscreen: onFullscreen,
      onExitFullscreen: onExitFullscreen,
      onMoveFloating: onMoveFloating,
      onClampFloating: onClampFloating,
    );
  }
}
