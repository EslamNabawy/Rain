import 'package:flutter/material.dart';

import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';
import 'package:rain/presentation/widgets/calls/rain_call_status_strip.dart';

class RainCallWorkspace extends StatelessWidget {
  const RainCallWorkspace({
    super.key,
    required this.callState,
    required this.controls,
    required this.stage,
    required this.showDesktopSidePanel,
    required this.onExitFullscreen,
    this.peerLabel,
    this.qualityText,
    this.sidePanel,
    this.sidePanelCollapsed = false,
    this.sidePanelWidth = 280,
    this.onToggleSidePanel,
    this.onResizeSidePanel,
  });

  final VoiceCallState callState;
  final Widget controls;
  final Widget stage;
  final bool showDesktopSidePanel;
  final VoidCallback onExitFullscreen;
  final String? peerLabel;
  final String? qualityText;
  final Widget? sidePanel;
  final bool sidePanelCollapsed;
  final double sidePanelWidth;
  final VoidCallback? onToggleSidePanel;
  final ValueChanged<double>? onResizeSidePanel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSidePanel = showDesktopSidePanel && sidePanel != null;
    final label = peerLabel?.trim().isNotEmpty == true
        ? peerLabel!.trim()
        : callState.peerId ?? 'Call';
    return ColoredBox(
      key: const ValueKey<String>('rain-call-video-fullscreen-surface'),
      color: scheme.surface,
      child: Row(
        children: <Widget>[
          if (hasSidePanel)
            _RainCallWorkspaceSidePanel(
              panel: sidePanel!,
              collapsed: sidePanelCollapsed,
              width: sidePanelWidth,
              onToggle: onToggleSidePanel,
              onResize: onResizeSidePanel,
            ),
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    stage,
                    const _RainCallWorkspaceScrim(),
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 16,
                      child: RainCallTicker(
                        state: callState,
                        builder: (BuildContext context, int now) {
                          return KeyedSubtree(
                            key: const ValueKey<String>(
                              'rain-call-fullscreen-status-strip',
                            ),
                            child: RainCallStatusStrip(
                              key: const ValueKey<String>(
                                'rain-call-status-strip',
                              ),
                              peerLabel: label,
                              statusText: rainVoiceCallTitle(callState, label),
                              durationText: rainVoiceCallDetail(callState, now),
                              qualityText: qualityText ?? '',
                              trailing: IconButton.filledTonal(
                                key: const ValueKey<String>(
                                  'rain-call-fullscreen-exit-button',
                                ),
                                tooltip: 'Exit fullscreen',
                                onPressed: onExitFullscreen,
                                icon: const Icon(Icons.fullscreen_exit),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: controls,
                        ),
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

class _RainCallWorkspaceSidePanel extends StatelessWidget {
  const _RainCallWorkspaceSidePanel({
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
          KeyedSubtree(
            key: const ValueKey<String>('rain-call-desktop-side-panel'),
            child: AnimatedContainer(
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
                    ? _RainCallWorkspaceSideRail(onToggle: onToggle)
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                KeyedSubtree(
                                  key: const ValueKey<String>(
                                    'rain-call-side-panel-collapse',
                                  ),
                                  child: IconButton(
                                    key: const ValueKey<String>(
                                      'rain-call-fullscreen-sidebar-toggle',
                                    ),
                                    tooltip: 'Hide friends',
                                    onPressed: onToggle,
                                    icon: const Icon(Icons.chevron_left),
                                  ),
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

class _RainCallWorkspaceSideRail extends StatelessWidget {
  const _RainCallWorkspaceSideRail({this.onToggle});

  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey<String>('rain-call-side-panel-collapsed'),
      child: Column(
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
      ),
    );
  }
}

class _RainCallWorkspaceScrim extends StatelessWidget {
  const _RainCallWorkspaceScrim();

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
