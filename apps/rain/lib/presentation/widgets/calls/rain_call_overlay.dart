import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rain/application/runtime/video_call_renderers.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/branding/rain_streak_surface.dart';
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

  @override
  Widget build(BuildContext context) {
    if (!surface.isVisible || state.phase == VoiceCallPhase.idle) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (surface.mode == CallSurfaceMode.managerOnly ||
            surface.mode == CallSurfaceMode.pip) {
          return const SizedBox.shrink();
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = rainVoiceCallAccent(context, state);
    final canMinimize =
        state.phase != VoiceCallPhase.incomingRinging &&
        state.phase != VoiceCallPhase.failed;
    final isDark = scheme.brightness == Brightness.dark;
    final panelBorderColor = state.phase == VoiceCallPhase.failed
        ? RainColors.errorCoral.withValues(alpha: 0.42)
        : accent.withValues(alpha: 0.38);

    return Material(
      color: Colors.transparent,
      child: RainStreakSurface(
        key: const ValueKey<String>('rain-call-panel-surface'),
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: RainMotion.callSurface,
          curve: Curves.easeOutCubic,
          width: panelWidth,
          constraints: BoxConstraints(
            minHeight: math.min(panelWidth, maxHeight),
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
              padding: const EdgeInsets.all(18),
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
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          RainAvatar(
                            name: displayName,
                            size: 42,
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
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                Text(
                                  '@${state.peerId ?? displayName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurface.withValues(
                                          alpha: 0.62,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (canMinimize)
                            IconButton(
                              tooltip: 'Minimize call',
                              onPressed: onMinimize,
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _RainCallMediaStage(
                        state: state,
                        accent: accent,
                        videoRenderers: videoRenderers,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        rainVoiceCallTitle(state, displayName),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        rainVoiceCallDetail(state, now),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.70),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (routeSummary != null && routeSummary!.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _RainRouteSummary(label: routeSummary!),
                      ],
                      const SizedBox(height: 24),
                      Align(
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
}

class _RainCallMediaStage extends StatelessWidget {
  const _RainCallMediaStage({
    required this.state,
    required this.accent,
    this.videoRenderers,
  });

  final VoiceCallState state;
  final Color accent;
  final VideoCallRenderers? videoRenderers;

  @override
  Widget build(BuildContext context) {
    if (!state.isVideo) {
      return _RainCallStatusGlyph(
        key: const ValueKey<String>('rain-call-audio-stage'),
        state: state,
        accent: accent,
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: RainVideoCallStage(
          state: state,
          accent: accent,
          renderers: videoRenderers,
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
              ? _RainCallAudioWave(
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
