import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rain/application/runtime/video_call_renderers.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/branding/rain_ripple_halo_surface.dart';
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
    required this.onMinimize,
    required this.onExpand,
    this.onFullscreen,
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
  final ValueChanged<VoiceCallOutputRoute>? onSelectOutputRoute;
  final VoidCallback onMinimize;
  final VoidCallback onExpand;
  final VoidCallback? onFullscreen;

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
          return _RainFullscreenVideoSurface(
            state: state,
            accent: rainVoiceCallAccent(context, state),
            videoRenderers: videoRenderers,
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
                ),
              ),
            ),
          );
        }

        return Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: _RainExpandedCallPanel(
              state: state,
              displayName: displayName,
              gender: gender,
              routeSummary: routeSummary,
              panelWidth: _boundedWidth(
                constraints.maxWidth,
                _preferredPanelWidth(constraints.maxWidth, state),
              ),
              maxHeight: _boundedHeight(constraints.maxHeight),
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
              onMinimize: onMinimize,
              onFullscreen: onFullscreen,
            ),
          ),
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

class _RainFullscreenVideoSurface extends StatelessWidget {
  const _RainFullscreenVideoSurface({
    required this.state,
    required this.accent,
    this.videoRenderers,
  });

  final VoiceCallState state;
  final Color accent;
  final VideoCallRenderers? videoRenderers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey<String>('rain-call-video-fullscreen-surface'),
      color: scheme.surface,
      child: RainVideoCallStage(
        state: state,
        accent: accent,
        renderers: videoRenderers,
        layout: RainVideoCallStageLayout.fullscreen,
      ),
    );
  }
}

class _RainExpandedCallPanel extends StatelessWidget {
  const _RainExpandedCallPanel({
    required this.state,
    required this.displayName,
    required this.panelWidth,
    required this.maxHeight,
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
    required this.onMinimize,
    this.onFullscreen,
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
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onSwitchCamera;
  final ValueChanged<VoiceCallOutputRoute>? onSelectOutputRoute;
  final VoidCallback onMinimize;
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = rainVoiceCallAccent(context, state);
    final haloColor = rainVoiceCallHaloColor(context, state);
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
        child: AnimatedContainer(
          duration: RainMotion.callSurface,
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
              BoxShadow(
                blurRadius: 34,
                offset: const Offset(0, 18),
                color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(panelPadding),
              child: StreamBuilder<int>(
                stream: state.isActive
                    ? Stream<int>.periodic(
                        const Duration(seconds: 1),
                        (_) => DateTime.now().millisecondsSinceEpoch,
                      )
                    : null,
                initialData: DateTime.now().millisecondsSinceEpoch,
                builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
                  final now =
                      snapshot.data ?? DateTime.now().millisecondsSinceEpoch;
                  return Column(
                    key: ValueKey<String>(_popupLayoutKey(state)),
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
                      ),
                      SizedBox(
                        height: state.phase == VoiceCallPhase.failed ? 16 : 18,
                      ),
                      if (state.phase == VoiceCallPhase.failed)
                        _RainFailureFocus(state: state, accent: accent)
                      else
                        _RainCallMediaFrame(
                          state: state,
                          accent: accent,
                          videoRenderers: videoRenderers,
                        ),
                      const SizedBox(height: 18),
                      _RainPopupStatusText(
                        state: state,
                        displayName: displayName,
                        now: now,
                      ),
                      if (routeSummary != null && routeSummary!.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _RainRouteSummary(label: routeSummary!),
                      ],
                      const SizedBox(height: 20),
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
  });

  final VoiceCallState state;
  final String displayName;
  final String? gender;
  final Color accent;
  final bool canMinimize;
  final VoidCallback onMinimize;
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
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
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
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
    );
  }
}

class _RainCallMediaFrame extends StatelessWidget {
  const _RainCallMediaFrame({
    required this.state,
    required this.accent,
    this.videoRenderers,
  });

  final VoiceCallState state;
  final Color accent;
  final VideoCallRenderers? videoRenderers;

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
  final ValueChanged<VoiceCallOutputRoute>? onSelectOutputRoute;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('rain-call-control-dock'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Align(
        alignment: Alignment.center,
        child: RainCallControls(
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
        ),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RainPeerCoreAnimatedMark(size: 38, animate: false),
        const SizedBox(height: 4),
        _RainCallAudioWave(level: level, accent: accent),
      ],
    );
  }
}

class _RainCallAudioWave extends StatelessWidget {
  const _RainCallAudioWave({required this.level, required this.accent});

  final double level;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const multipliers = <double>[0.38, 0.68, 1, 0.68, 0.38];
    return SizedBox(
      width: 62,
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (var index = 0; index < multipliers.length; index += 1)
            AnimatedContainer(
              key: ValueKey<String>('rain-call-audio-wave-bar-$index'),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              width: 8,
              height: _barHeight(level, multipliers[index]),
              decoration: BoxDecoration(
                color: accent.withValues(
                  alpha: 0.58 + (0.36 * multipliers[index]),
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }

  double _barHeight(double rawLevel, double multiplier) {
    final clamped = rawLevel.isFinite
        ? rawLevel.clamp(0.0, 1.0).toDouble()
        : 0.0;
    return 12 + (38 * clamped * multiplier);
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
