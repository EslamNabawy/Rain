import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rain/application/runtime/video_call_renderers.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_geometry.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/branding/rain_ripple_halo_surface.dart';
import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';
import 'package:rain/presentation/widgets/rain_chat_widgets.dart';

class RainCallOverlay extends StatelessWidget {
  const RainCallOverlay({
    super.key,
    required this.state,
    required this.surface,
    required this.displayName,
    this.gender,
    this.routeSummary,
    this.videoRenderers,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
    this.onToggleDeafen,
    this.onToggleCamera,
    this.onSwitchCamera,
    this.onSelectOutputRoute,
    this.controlCapabilities,
    this.outputRouteOptions,
    required this.onMinimize,
    required this.onExpand,
    this.onToggleVideoPrimaryRole,
    this.onFullscreen,
    this.onExitFullscreen,
    this.friendsPanel,
    this.showFriendsPanel = false,
    this.friendsPanelCollapsed = false,
    this.friendsPanelWidth = 280,
    this.onToggleFriendsPanel,
    this.onResizeFriendsPanel,
    this.onMoveFloating,
    this.onClampFloating,
  });

  final VoiceCallState state;
  final CallSurfaceState surface;
  final String displayName;
  final String? gender;
  final String? routeSummary;
  final VideoCallRenderers? videoRenderers;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onSwitchCamera;
  final ValueChanged<CallAudioOutputTarget>? onSelectOutputRoute;
  final List<CallControlCapability>? controlCapabilities;
  final List<VoiceCallOutputRouteOption>? outputRouteOptions;
  final VoidCallback onMinimize;
  final VoidCallback onExpand;
  final VoidCallback? onToggleVideoPrimaryRole;
  final VoidCallback? onFullscreen;
  final VoidCallback? onExitFullscreen;
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

  @override
  Widget build(BuildContext context) {
    if (!surface.isVisible || state.phase == VoiceCallPhase.idle) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (surface.mode == CallSurfaceMode.managerOnly) {
          return const SizedBox.shrink();
        }

        if (surface.mode == CallSurfaceMode.fullscreen && state.isVideo) {
          return RainFullscreenCallWorkspace(
            state: state,
            displayName: displayName,
            gender: gender,
            routeSummary: routeSummary,
            videoRenderers: videoRenderers,
            primaryRole: surface.videoPrimaryRole,
            onToggleVideoPrimaryRole: onToggleVideoPrimaryRole,
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
            onExitFullscreen: onExitFullscreen ?? onExpand,
            friendsPanel: friendsPanel,
            showFriendsPanel: showFriendsPanel,
            friendsPanelCollapsed: friendsPanelCollapsed,
            friendsPanelWidth: friendsPanelWidth,
            onToggleFriendsPanel: onToggleFriendsPanel,
            onResizeFriendsPanel: onResizeFriendsPanel,
          );
        }

        if (surface.mode == CallSurfaceMode.pip && state.isVideo) {
          return Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 96, 16, 0),
              child: SizedBox(
                key: const ValueKey<String>('rain-call-video-pip-window'),
                width: _pipWidth(constraints.maxWidth),
                child: RainVideoCallStage(
                  state: state,
                  accent: rainVoiceCallAccent(context, state),
                  renderers: videoRenderers,
                  layout: RainVideoCallStageLayout.pip,
                  primaryRole: surface.videoPrimaryRole,
                ),
              ),
            ),
          );
        }

        return _RainFloatingExpandedCallOverlay(
          state: state,
          surface: surface,
          displayName: displayName,
          gender: gender,
          routeSummary: routeSummary,
          panelWidth: _boundedWidth(
            constraints.maxWidth,
            _preferredPanelWidth(constraints.maxWidth, state),
          ),
          maxHeight: _boundedHeight(
            constraints.maxHeight - MediaQuery.paddingOf(context).vertical - 24,
          ),
          videoRenderers: videoRenderers,
          primaryRole: surface.videoPrimaryRole,
          onToggleVideoPrimaryRole: onToggleVideoPrimaryRole,
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
          onFullscreen: onFullscreen,
          onMoveFloating: onMoveFloating,
          onClampFloating: onClampFloating,
        );
      },
    );
  }

  double _boundedWidth(double availableWidth, double preferredWidth) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return preferredWidth;
    }
    return math.max(240, math.min(preferredWidth, availableWidth - 32));
  }

  double _boundedHeight(double availableHeight) {
    if (!availableHeight.isFinite || availableHeight <= 0) {
      return 520;
    }
    return math.max(220, availableHeight - 32);
  }

  double _preferredPanelWidth(double availableWidth, VoiceCallState state) {
    if (!state.isVideo) {
      return availableWidth < 480 ? 360 : 420;
    }
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return 680;
    }
    return availableWidth < 520 ? 380 : 720;
  }

  double _pipWidth(double availableWidth) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return 240;
    }
    return math.max(180, math.min(280, availableWidth * 0.42));
  }
}

class _RainFloatingExpandedCallOverlay extends StatefulWidget {
  const _RainFloatingExpandedCallOverlay({
    required this.state,
    required this.surface,
    required this.displayName,
    required this.panelWidth,
    required this.maxHeight,
    this.videoRenderers,
    required this.primaryRole,
    this.onToggleVideoPrimaryRole,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
    this.onToggleDeafen,
    this.onToggleCamera,
    this.onSwitchCamera,
    this.onSelectOutputRoute,
    this.controlCapabilities,
    this.outputRouteOptions,
    required this.onMinimize,
    this.onFullscreen,
    this.onMoveFloating,
    this.onClampFloating,
    this.gender,
    this.routeSummary,
  });

  final VoiceCallState state;
  final CallSurfaceState surface;
  final String displayName;
  final String? gender;
  final String? routeSummary;
  final double panelWidth;
  final double maxHeight;
  final VideoCallRenderers? videoRenderers;
  final VideoPrimaryRole primaryRole;
  final VoidCallback? onToggleVideoPrimaryRole;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onSwitchCamera;
  final ValueChanged<CallAudioOutputTarget>? onSelectOutputRoute;
  final List<CallControlCapability>? controlCapabilities;
  final List<VoiceCallOutputRouteOption>? outputRouteOptions;
  final VoidCallback onMinimize;
  final VoidCallback? onFullscreen;
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

  @override
  State<_RainFloatingExpandedCallOverlay> createState() =>
      _RainFloatingExpandedCallOverlayState();
}

class _RainFloatingExpandedCallOverlayState
    extends State<_RainFloatingExpandedCallOverlay> {
  final GlobalKey _panelKey = GlobalKey();
  Size? _lastPanelSize;

  @override
  void didUpdateWidget(covariant _RainFloatingExpandedCallOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.surface.callId != widget.surface.callId ||
        oldWidget.maxHeight != widget.maxHeight ||
        oldWidget.panelWidth != widget.panelWidth) {
      _scheduleClamp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final panelSize = _lastPanelSize ?? _estimatedPanelSize();
        final bounds = CallSurfaceBounds(
          viewportSize: viewportSize,
          safePadding: safePadding,
          panelSize: panelSize,
        );
        final offset = widget.surface.floatingOffset == null
            ? centeredCallSurfaceOffset(bounds)
            : clampCallSurfaceOffset(bounds, widget.surface.floatingOffset!);
        _scheduleClamp(
          viewportSize: viewportSize,
          safePadding: safePadding,
          panelSize: panelSize,
        );

        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: offset.dx,
              top: offset.dy,
              child: _RainExpandedCallPanel(
                key: _panelKey,
                state: widget.state,
                displayName: widget.displayName,
                gender: widget.gender,
                routeSummary: widget.routeSummary,
                panelWidth: widget.panelWidth,
                maxHeight: widget.maxHeight,
                videoRenderers: widget.videoRenderers,
                primaryRole: widget.primaryRole,
                onToggleVideoPrimaryRole: widget.onToggleVideoPrimaryRole,
                onAccept: widget.onAccept,
                onReject: widget.onReject,
                onHangUp: widget.onHangUp,
                onRetry: widget.onRetry,
                onToggleMute: widget.onToggleMute,
                onToggleDeafen: widget.onToggleDeafen,
                onToggleCamera: widget.onToggleCamera,
                onSwitchCamera: widget.onSwitchCamera,
                onSelectOutputRoute: widget.onSelectOutputRoute,
                controlCapabilities: widget.controlCapabilities,
                outputRouteOptions: widget.outputRouteOptions,
                onMinimize: widget.onMinimize,
                onFullscreen: widget.onFullscreen,
                onHeaderDragUpdate: (DragUpdateDetails details) {
                  widget.onMoveFloating?.call(
                    details.delta,
                    viewportSize,
                    safePadding,
                    _panelSizeFromRenderBox() ?? panelSize,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Size _estimatedPanelSize() {
    final height = widget.state.isVideo
        ? math.min(widget.maxHeight, math.max(420.0, widget.panelWidth * 0.72))
        : math.min(widget.maxHeight, math.max(420.0, widget.panelWidth));
    return Size(widget.panelWidth, height);
  }

  Size? _panelSizeFromRenderBox() {
    final renderObject = _panelKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final size = renderObject.size;
    if (size.width <= 0 || size.height <= 0) {
      return null;
    }
    return size;
  }

  void _scheduleClamp({
    Size? viewportSize,
    EdgeInsets? safePadding,
    Size? panelSize,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final resolvedPanelSize = _panelSizeFromRenderBox() ?? panelSize;
      if (resolvedPanelSize == null) {
        return;
      }
      final panelSizeChanged = _lastPanelSize != resolvedPanelSize;
      _lastPanelSize = resolvedPanelSize;
      final renderObject = context.findRenderObject();
      final resolvedViewportSize =
          viewportSize ??
          (renderObject is RenderBox && renderObject.hasSize
              ? renderObject.size
              : null);
      if (resolvedViewportSize == null) {
        return;
      }
      widget.onClampFloating?.call(
        resolvedViewportSize,
        safePadding ?? MediaQuery.paddingOf(context),
        resolvedPanelSize,
      );
      if (panelSizeChanged) {
        setState(() {});
      }
    });
  }
}

class RainFullscreenCallWorkspace extends StatelessWidget {
  const RainFullscreenCallWorkspace({
    super.key,
    required this.state,
    required this.displayName,
    this.gender,
    this.routeSummary,
    this.videoRenderers,
    required this.primaryRole,
    this.onToggleVideoPrimaryRole,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
    this.onToggleDeafen,
    this.onToggleCamera,
    this.onSwitchCamera,
    this.onSelectOutputRoute,
    this.controlCapabilities,
    this.outputRouteOptions,
    required this.onExitFullscreen,
    this.friendsPanel,
    this.showFriendsPanel = false,
    this.friendsPanelCollapsed = false,
    this.friendsPanelWidth = 280,
    this.onToggleFriendsPanel,
    this.onResizeFriendsPanel,
  });

  final VoiceCallState state;
  final String displayName;
  final String? gender;
  final String? routeSummary;
  final VideoCallRenderers? videoRenderers;
  final VideoPrimaryRole primaryRole;
  final VoidCallback? onToggleVideoPrimaryRole;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onSwitchCamera;
  final ValueChanged<CallAudioOutputTarget>? onSelectOutputRoute;
  final List<CallControlCapability>? controlCapabilities;
  final List<VoiceCallOutputRouteOption>? outputRouteOptions;
  final VoidCallback onExitFullscreen;
  final Widget? friendsPanel;
  final bool showFriendsPanel;
  final bool friendsPanelCollapsed;
  final double friendsPanelWidth;
  final VoidCallback? onToggleFriendsPanel;
  final ValueChanged<double>? onResizeFriendsPanel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = rainVoiceCallAccent(context, state);
    final hasFriendsPanel = showFriendsPanel && friendsPanel != null;
    return ColoredBox(
      key: const ValueKey<String>('rain-call-video-fullscreen-surface'),
      color: scheme.surface,
      child: Row(
        children: <Widget>[
          if (hasFriendsPanel)
            _RainFullscreenFriendsPanel(
              panel: friendsPanel!,
              collapsed: friendsPanelCollapsed,
              width: friendsPanelWidth,
              onToggle: onToggleFriendsPanel,
              onResize: onResizeFriendsPanel,
            ),
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    RainVideoCallStage(
                      state: state,
                      accent: accent,
                      renderers: videoRenderers,
                      layout: RainVideoCallStageLayout.fullscreen,
                      primaryRole: primaryRole,
                      onTogglePrimaryRole: onToggleVideoPrimaryRole,
                    ),
                    const _RainFullscreenVideoScrim(),
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 16,
                      child: _RainFullscreenStatusStrip(
                        state: state,
                        displayName: displayName,
                        gender: gender,
                        accent: accent,
                        routeSummary: routeSummary,
                        onExitFullscreen: onExitFullscreen,
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: _RainFullscreenControlPanel(
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
                        onExitFullscreen: onExitFullscreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RainFullscreenFriendsPanel extends StatelessWidget {
  const _RainFullscreenFriendsPanel({
    required this.panel,
    required this.collapsed,
    required this.width,
    this.onToggle,
    this.onResize,
  });

  static const double collapsedWidth = 56;

  final Widget panel;
  final bool collapsed;
  final double width;
  final VoidCallback? onToggle;
  final ValueChanged<double>? onResize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final performance = RainPerformanceScope.of(context);
    final targetWidth = collapsed ? collapsedWidth : width.clamp(220, 380);
    return SafeArea(
      right: false,
      child: Row(
        children: <Widget>[
          AnimatedContainer(
            key: const ValueKey<String>('rain-call-fullscreen-friends-panel'),
            duration: performance.allowContinuousCallAnimation
                ? RainMotion.quick
                : Duration.zero,
            curve: Curves.easeOutCubic,
            width: targetWidth.toDouble(),
            margin: const EdgeInsets.fromLTRB(14, 14, 0, 14),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.26),
              ),
              boxShadow: <BoxShadow>[
                if (performance.allowExpensiveCallEffects)
                  BoxShadow(
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                    color: Colors.black.withValues(alpha: 0.22),
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: collapsed
                  ? _RainFullscreenFriendsRail(onToggle: onToggle)
                  : Column(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'Friends',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ),
                              IconButton(
                                key: const ValueKey<String>(
                                  'rain-call-fullscreen-sidebar-toggle',
                                ),
                                tooltip: 'Hide friends',
                                onPressed: onToggle,
                                icon: const Icon(Icons.chevron_left),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(child: panel),
                      ],
                    ),
            ),
          ),
          if (!collapsed)
            MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                key: const ValueKey<String>(
                  'rain-call-fullscreen-friends-resizer',
                ),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (DragUpdateDetails details) =>
                    onResize?.call(details.delta.dx),
                child: SizedBox(
                  width: 14,
                  child: Center(
                    child: Container(
                      width: 3,
                      height: 54,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }
}

class _RainFullscreenFriendsRail extends StatelessWidget {
  const _RainFullscreenFriendsRail({this.onToggle});

  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: 8),
        IconButton(
          key: const ValueKey<String>('rain-call-fullscreen-sidebar-toggle'),
          tooltip: 'Show friends',
          onPressed: onToggle,
          icon: const Icon(Icons.people_outline),
        ),
        const Spacer(),
        RotatedBox(
          quarterTurns: 3,
          child: Text(
            'Friends',
            maxLines: 1,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

class _RainFullscreenVideoScrim extends StatelessWidget {
  const _RainFullscreenVideoScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.black.withValues(alpha: 0.44),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.48),
            ],
            stops: const <double>[0, 0.24, 0.66, 1],
          ),
        ),
      ),
    );
  }
}

class _RainFullscreenStatusStrip extends StatelessWidget {
  const _RainFullscreenStatusStrip({
    required this.state,
    required this.displayName,
    required this.accent,
    required this.onExitFullscreen,
    this.gender,
    this.routeSummary,
  });

  final VoiceCallState state;
  final String displayName;
  final String? gender;
  final Color accent;
  final String? routeSummary;
  final VoidCallback onExitFullscreen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: DecoratedBox(
          key: const ValueKey<String>('rain-call-fullscreen-status-strip'),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.30),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: RainCallTicker(
              state: state,
              builder: (BuildContext context, int now) {
                final detail = rainVoiceCallDetail(state, now);
                final secondary = routeSummary == null || routeSummary!.isEmpty
                    ? detail
                    : '$detail / $routeSummary';
                return Row(
                  children: <Widget>[
                    RainAvatar(
                      name: displayName,
                      size: 38,
                      statusColor: accent,
                      gender: gender,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            rainVoiceCallTitle(state, displayName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          if (secondary.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 2),
                            Text(
                              secondary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.66,
                                    ),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const ValueKey<String>(
                        'rain-call-fullscreen-exit-button',
                      ),
                      tooltip: 'Exit fullscreen',
                      onPressed: onExitFullscreen,
                      icon: const Icon(Icons.fullscreen_exit),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RainFullscreenControlPanel extends StatelessWidget {
  const _RainFullscreenControlPanel({
    required this.state,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
    required this.onExitFullscreen,
    this.onToggleDeafen,
    this.onToggleCamera,
    this.onSwitchCamera,
    this.onSelectOutputRoute,
    this.controlCapabilities,
    this.outputRouteOptions,
  });

  final VoiceCallState state;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback onExitFullscreen;
  final VoidCallback? onToggleDeafen;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onSwitchCamera;
  final ValueChanged<CallAudioOutputTarget>? onSelectOutputRoute;
  final List<CallControlCapability>? controlCapabilities;
  final List<VoiceCallOutputRouteOption>? outputRouteOptions;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: RainCallControlDock(
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
      ),
    );
  }
}

class _RainExpandedCallPanel extends StatelessWidget {
  const _RainExpandedCallPanel({
    super.key,
    required this.state,
    required this.displayName,
    required this.panelWidth,
    required this.maxHeight,
    this.videoRenderers,
    required this.primaryRole,
    this.onToggleVideoPrimaryRole,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
    this.onToggleDeafen,
    this.onToggleCamera,
    this.onSwitchCamera,
    this.onSelectOutputRoute,
    this.controlCapabilities,
    this.outputRouteOptions,
    required this.onMinimize,
    this.onFullscreen,
    this.onHeaderDragUpdate,
    this.gender,
    this.routeSummary,
  });

  final VoiceCallState state;
  final String displayName;
  final String? gender;
  final String? routeSummary;
  final double panelWidth;
  final double maxHeight;
  final VideoCallRenderers? videoRenderers;
  final VideoPrimaryRole primaryRole;
  final VoidCallback? onToggleVideoPrimaryRole;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onSwitchCamera;
  final ValueChanged<CallAudioOutputTarget>? onSelectOutputRoute;
  final List<CallControlCapability>? controlCapabilities;
  final List<VoiceCallOutputRouteOption>? outputRouteOptions;
  final VoidCallback onMinimize;
  final VoidCallback? onFullscreen;
  final GestureDragUpdateCallback? onHeaderDragUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = rainVoiceCallAccent(context, state);
    final haloColor = rainVoiceCallHaloColor(context, state);
    final performance = RainPerformanceScope.of(context);
    final canMinimize =
        state.phase != VoiceCallPhase.incomingRinging &&
        state.phase != VoiceCallPhase.failed;
    final isDark = scheme.brightness == Brightness.dark;
    final panelBorderColor = state.phase == VoiceCallPhase.failed
        ? RainColors.errorCoral.withValues(alpha: 0.42)
        : accent.withValues(alpha: 0.38);
    final panelPadding = state.isVideo && state.phase != VoiceCallPhase.failed
        ? 14.0
        : 18.0;
    final minHeight = _targetMinHeight(state, panelWidth, maxHeight);

    return Material(
      color: Colors.transparent,
      child: RainRippleHaloSurface(
        key: const ValueKey<String>('rain-call-panel-surface'),
        enabled: rainVoiceCallShowsSignalHalo(state),
        borderRadius: BorderRadius.circular(24),
        color: haloColor,
        pulseKey: '${state.callId}:${state.phase}:${state.isVideo}',
        pulseOnMount: rainVoiceCallShowsSignalHalo(state),
        callSurface: true,
        child: AnimatedContainer(
          duration: performance.allowContinuousCallAnimation
              ? RainMotion.callSurface
              : Duration.zero,
          curve: Curves.easeOutCubic,
          width: panelWidth,
          constraints: BoxConstraints(
            minHeight: minHeight,
            maxHeight: maxHeight,
          ),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: isDark ? 0.94 : 0.98),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: panelBorderColor),
            boxShadow: <BoxShadow>[
              if (performance.allowExpensiveCallEffects)
                BoxShadow(
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                  color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.16),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: EdgeInsets.all(panelPadding),
              child: RainCallTicker(
                state: state,
                builder: (BuildContext context, int now) {
                  return Column(
                    key: ValueKey<String>(_popupLayoutKey(state)),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _RainPopupHeader(
                                state: state,
                                displayName: displayName,
                                gender: gender,
                                accent: accent,
                                canMinimize: canMinimize,
                                onMinimize: onMinimize,
                                onFullscreen: onFullscreen,
                                onDragUpdate: onHeaderDragUpdate,
                              ),
                              SizedBox(
                                height: state.phase == VoiceCallPhase.failed
                                    ? 16
                                    : 18,
                              ),
                              if (state.phase == VoiceCallPhase.failed)
                                _RainFailureFocus(state: state, accent: accent)
                              else
                                _RainCallMediaFrame(
                                  state: state,
                                  accent: accent,
                                  videoRenderers: videoRenderers,
                                  primaryRole: primaryRole,
                                  onToggleVideoPrimaryRole:
                                      onToggleVideoPrimaryRole,
                                ),
                              const SizedBox(height: 18),
                              _RainPopupStatusText(
                                state: state,
                                displayName: displayName,
                                now: now,
                              ),
                              if (routeSummary != null &&
                                  routeSummary!.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                _RainRouteSummary(label: routeSummary!),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _RainCallControlDock(
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
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _popupLayoutKey(VoiceCallState state) {
    if (state.phase == VoiceCallPhase.failed) {
      return 'rain-call-failure-popup-layout';
    }
    if (state.isVideo) {
      return 'rain-call-video-popup-layout';
    }
    return 'rain-call-voice-popup-layout';
  }

  double _targetMinHeight(
    VoiceCallState state,
    double panelWidth,
    double maxHeight,
  ) {
    final target = state.phase == VoiceCallPhase.failed
        ? math.min(360.0, panelWidth * 0.78)
        : state.isVideo
        ? math.max(420.0, panelWidth * 0.72)
        : math.max(420.0, panelWidth);
    return math.min(target, maxHeight);
  }
}

class _RainPopupHeader extends StatelessWidget {
  const _RainPopupHeader({
    required this.state,
    required this.displayName,
    required this.accent,
    required this.canMinimize,
    required this.onMinimize,
    this.gender,
    this.onFullscreen,
    this.onDragUpdate,
  });

  final VoiceCallState state;
  final String displayName;
  final String? gender;
  final Color accent;
  final bool canMinimize;
  final VoidCallback onMinimize;
  final VoidCallback? onFullscreen;
  final GestureDragUpdateCallback? onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: const ValueKey<String>('rain-call-popup-drag-handle'),
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onDragUpdate,
      child: Row(
        key: const ValueKey<String>('rain-call-popup-identity'),
        children: <Widget>[
          RainAvatar(
            name: displayName,
            size: 44,
            statusColor: accent,
            gender: gender,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '@${state.peerId ?? displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (state.isVideo && onFullscreen != null)
            IconButton.filledTonal(
              tooltip: 'Fullscreen video',
              onPressed: onFullscreen,
              icon: const Icon(Icons.fullscreen),
            ),
          if (canMinimize) ...[
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'Minimize call',
              onPressed: onMinimize,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ],
        ],
      ),
    );
  }
}

class _RainCallMediaFrame extends StatelessWidget {
  const _RainCallMediaFrame({
    required this.state,
    required this.accent,
    this.videoRenderers,
    required this.primaryRole,
    this.onToggleVideoPrimaryRole,
  });

  final VoiceCallState state;
  final Color accent;
  final VideoCallRenderers? videoRenderers;
  final VideoPrimaryRole primaryRole;
  final VoidCallback? onToggleVideoPrimaryRole;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(state.isVideo ? 20 : 28);
    return Container(
      key: const ValueKey<String>('rain-call-popup-media'),
      padding: EdgeInsets.all(state.isVideo ? 4 : 18),
      decoration: BoxDecoration(
        color: state.isVideo
            ? Colors.black.withValues(alpha: 0.62)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: borderRadius,
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(state.isVideo ? 16 : 22),
        child: state.isVideo
            ? RainVideoCallStage(
                state: state,
                accent: accent,
                renderers: videoRenderers,
                layout: RainVideoCallStageLayout.expanded,
                primaryRole: primaryRole,
                onTogglePrimaryRole: onToggleVideoPrimaryRole,
              )
            : SizedBox(
                height: 172,
                child: _RainCallStatusGlyph(
                  key: const ValueKey<String>('rain-call-audio-stage'),
                  state: state,
                  accent: accent,
                ),
              ),
      ),
    );
  }
}

class _RainFailureFocus extends StatelessWidget {
  const _RainFailureFocus({required this.state, required this.accent});

  final VoiceCallState state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.center,
      child: Container(
        key: const ValueKey<String>('rain-call-failure-focus'),
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.errorContainer.withValues(alpha: 0.42),
          border: Border.all(color: accent.withValues(alpha: 0.42), width: 2),
        ),
        child: Icon(
          rainVoiceCallIcon(state),
          size: 42,
          color: scheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _RainPopupStatusText extends StatelessWidget {
  const _RainPopupStatusText({
    required this.state,
    required this.displayName,
    required this.now,
  });

  final VoiceCallState state;
  final String displayName;
  final int now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Text(
          rainVoiceCallTitle(state, displayName),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          rainVoiceCallDetail(state, now),
          textAlign: TextAlign.center,
          maxLines: state.phase == VoiceCallPhase.failed ? 4 : 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.70),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RainCallControlDock extends StatelessWidget {
  const _RainCallControlDock({
    required this.state,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
    this.onToggleDeafen,
    this.onToggleCamera,
    this.onSwitchCamera,
    this.onSelectOutputRoute,
    this.controlCapabilities,
    this.outputRouteOptions,
  });

  final VoiceCallState state;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onSwitchCamera;
  final ValueChanged<CallAudioOutputTarget>? onSelectOutputRoute;
  final List<CallControlCapability>? controlCapabilities;
  final List<VoiceCallOutputRouteOption>? outputRouteOptions;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: RainCallControlDock(
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
      ),
    );
  }
}

class _RainCallStatusGlyph extends StatelessWidget {
  const _RainCallStatusGlyph({
    super.key,
    required this.state,
    required this.accent,
  });

  final VoiceCallState state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showPeerCoreMark =
        state.phase == VoiceCallPhase.connectingPeer ||
        state.phase == VoiceCallPhase.connectingMedia ||
        state.phase == VoiceCallPhase.incomingRinging ||
        state.phase == VoiceCallPhase.outgoingRinging;
    return Center(
      child: Container(
        width: 116,
        height: 116,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.withValues(alpha: 0.12),
          border: Border.all(color: accent.withValues(alpha: 0.28), width: 2),
        ),
        child: Center(
          child: showPeerCoreMark
              ? RainPeerCoreAnimatedMark(
                  key: const ValueKey<String>('rain-call-peer-core-mark'),
                  size: 64,
                  animate: state.isBusy || state.isRinging,
                )
              : state.isActive && state.audioLevel.isAvailable
              ? _RainCallAudioActivity(
                  level: state.audioLevel.displayLevel,
                  accent: accent,
                )
              : state.isActive
              ? Icon(
                  rainVoiceCallIcon(state),
                  key: const ValueKey<String>('rain-call-audio-unavailable'),
                  size: 42,
                  color: accent.withValues(alpha: 0.72),
                )
              : Icon(
                  rainVoiceCallIcon(state),
                  size: 42,
                  color: state.phase == VoiceCallPhase.idle
                      ? scheme.onSurfaceVariant
                      : accent,
                ),
        ),
      ),
    );
  }
}

class _RainCallAudioActivity extends StatelessWidget {
  const _RainCallAudioActivity({required this.level, required this.accent});

  final double level;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final performance = RainPerformanceScope.read(context);
    final staticOnly =
        MediaQuery.disableAnimationsOf(context) ||
        !performance.allowContinuousCallAnimation;
    return SizedBox(
      key: const ValueKey<String>('rain-call-audio-emitter'),
      width: 86,
      height: 86,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _RainCallAudioEmitterPainter(
                level: level,
                accent: accent,
                staticOnly: staticOnly,
              ),
            ),
          ),
          RainPeerCoreAnimatedMark(
            key: const ValueKey<String>('rain-call-audio-emitter-mark'),
            size: 42,
            animate: false,
          ),
        ],
      ),
    );
  }
}

class _RainCallAudioEmitterPainter extends CustomPainter {
  const _RainCallAudioEmitterPainter({
    required this.level,
    required this.accent,
    required this.staticOnly,
  });

  final double level;
  final Color accent;
  final bool staticOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final clamped = level.isFinite ? level.clamp(0.0, 1.0).toDouble() : 0.0;
    final intensity = staticOnly ? 0.34 : math.max(0.18, clamped);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6;
    final fill = Paint()..style = PaintingStyle.fill;
    final nodes = <Offset>[
      Offset(size.width * 0.35, size.height * 0.55),
      Offset(size.width * 0.51, size.height * 0.35),
      Offset(size.width * 0.61, size.height * 0.62),
    ];

    for (final node in nodes) {
      for (var ring = 0; ring < 3; ring += 1) {
        final radius = 7.0 + (ring * 9.0) + (intensity * 12.0);
        stroke.color = accent.withValues(
          alpha: (0.34 - (ring * 0.08)) * intensity,
        );
        canvas.drawCircle(node, radius, stroke);
      }
      fill.color = accent.withValues(alpha: 0.42 + (0.30 * intensity));
      canvas.drawCircle(node, 3.2 + (2.0 * intensity), fill);
    }

    stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: 0.18 * intensity);
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      31 + (8 * intensity),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RainCallAudioEmitterPainter oldDelegate) {
    if (oldDelegate.accent != accent || oldDelegate.staticOnly != staticOnly) {
      return true;
    }
    if (staticOnly && oldDelegate.staticOnly) {
      return false;
    }
    return oldDelegate.level != level;
  }
}

class _RainRouteSummary extends StatelessWidget {
  const _RainRouteSummary({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.center,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.54),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.alt_route_rounded,
              size: 16,
              color: scheme.onSurface.withValues(alpha: 0.72),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
