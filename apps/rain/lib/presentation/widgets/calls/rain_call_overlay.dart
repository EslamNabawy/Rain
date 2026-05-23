import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
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
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
    this.onToggleDeafen,
    this.onSelectOutputRoute,
    required this.onMinimize,
    required this.onExpand,
  });

  final VoiceCallState state;
  final CallSurfaceState surface;
  final String displayName;
  final String? gender;
  final String? routeSummary;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
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
        if (surface.mode == CallSurfaceMode.minimized) {
          return _RainMinimizedCallChip(
            state: state,
            displayName: displayName,
            onExpand: onExpand,
            onHangUp: onHangUp,
            maxWidth: _boundedWidth(constraints.maxWidth, 420),
          );
        }

        return Align(
          alignment: _expandedAlignment(surface.dock),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              surface.dock == CallSurfaceDock.chatTop ? 16 : 24,
              16,
              24,
            ),
            child: _RainExpandedCallPanel(
              state: state,
              displayName: displayName,
              gender: gender,
              routeSummary: routeSummary,
              panelWidth: _boundedWidth(
                constraints.maxWidth,
                constraints.maxWidth < 480 ? 360 : 420,
              ),
              maxHeight: _boundedHeight(constraints.maxHeight),
              onAccept: onAccept,
              onReject: onReject,
              onHangUp: onHangUp,
              onRetry: onRetry,
              onToggleMute: onToggleMute,
              onToggleDeafen: onToggleDeafen,
              onSelectOutputRoute: onSelectOutputRoute,
              onMinimize: onMinimize,
            ),
          ),
        );
      },
    );
  }

  Alignment _expandedAlignment(CallSurfaceDock dock) {
    return switch (dock) {
      CallSurfaceDock.chatTop => Alignment.topCenter,
      CallSurfaceDock.chatCenter ||
      CallSurfaceDock.bottomSafe => Alignment.center,
    };
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
}

class _RainExpandedCallPanel extends StatelessWidget {
  const _RainExpandedCallPanel({
    required this.state,
    required this.displayName,
    required this.panelWidth,
    required this.maxHeight,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
    this.onToggleDeafen,
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
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
  final ValueChanged<VoiceCallOutputRoute>? onSelectOutputRoute;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = rainVoiceCallAccent(context, state);
    final canMinimize =
        state.phase != VoiceCallPhase.incomingRinging &&
        state.phase != VoiceCallPhase.failed;

    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: panelWidth,
        constraints: BoxConstraints(
          minHeight: math.min(panelWidth, maxHeight),
          maxHeight: maxHeight,
        ),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withValues(alpha: 0.38)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              blurRadius: 34,
              offset: const Offset(0, 18),
              color: Colors.black.withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.38 : 0.16,
              ),
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
                    _RainCallStatusGlyph(state: state, accent: accent),
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
    );
  }
}

class _RainCallStatusGlyph extends StatelessWidget {
  const _RainCallStatusGlyph({required this.state, required this.accent});

  final VoiceCallState state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          child: state.isBusy
              ? SizedBox.square(
                  dimension: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: accent,
                  ),
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

class _RainMinimizedCallChip extends StatelessWidget {
  const _RainMinimizedCallChip({
    required this.state,
    required this.displayName,
    required this.onExpand,
    required this.onHangUp,
    required this.maxWidth,
  });

  final VoiceCallState state;
  final String displayName;
  final VoidCallback onExpand;
  final VoidCallback onHangUp;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = rainVoiceCallAccent(context, state);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 92),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Material(
            color: Colors.transparent,
            child: Tooltip(
              message: 'Restore call',
              child: InkWell(
                onTap: onExpand,
                borderRadius: BorderRadius.circular(24),
                child: Ink(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.98),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: accent.withValues(alpha: 0.36)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                        color: Colors.black.withValues(
                          alpha: scheme.brightness == Brightness.dark
                              ? 0.34
                              : 0.14,
                        ),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(rainVoiceCallIcon(state), color: accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StreamBuilder<int>(
                          stream: state.isActive
                              ? Stream<int>.periodic(
                                  const Duration(seconds: 1),
                                  (_) => DateTime.now().millisecondsSinceEpoch,
                                )
                              : null,
                          initialData: DateTime.now().millisecondsSinceEpoch,
                          builder:
                              (
                                BuildContext context,
                                AsyncSnapshot<int> snapshot,
                              ) {
                                final now =
                                    snapshot.data ??
                                    DateTime.now().millisecondsSinceEpoch;
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      rainVoiceCallTitle(state, displayName),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    Text(
                                      rainVoiceCallDetail(state, now),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurface.withValues(
                                              alpha: 0.64,
                                            ),
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                );
                              },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Hang up',
                        onPressed: onHangUp,
                        icon: const Icon(Icons.call_end),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
