import 'package:flutter/material.dart';

import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/branding/rain_ripple_halo_surface.dart';
import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';
import 'package:rain/presentation/widgets/calls/rain_call_layout_contract.dart';
import 'package:rain/presentation/widgets/rain_chat_widgets.dart';

class RainCallManagerBar extends StatelessWidget {
  const RainCallManagerBar({
    super.key,
    required this.state,
    required this.surface,
    required this.displayName,
    this.gender,
    required this.onToggleMute,
    this.onToggleCamera,
    this.onToggleDeafen,
    required this.onRestore,
    required this.onFullscreen,
    required this.onHangUp,
  });

  final VoiceCallState state;
  final CallSurfaceState surface;
  final String displayName;
  final String? gender;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onToggleDeafen;
  final VoidCallback onRestore;
  final VoidCallback onFullscreen;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    final contract = RainCallLayoutContract.fromSurface(
      surface,
      isDesktop: false,
    );
    if (!contract.showTopManagerBar || state.phase == VoiceCallPhase.idle) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final accent = rainVoiceCallAccent(context, state);
    final haloColor = rainVoiceCallHaloColor(context, state);
    final performance = RainPerformanceScope.of(context);
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: RainRippleHaloSurface(
              key: const ValueKey<String>('rain-call-manager-bar'),
              enabled: rainVoiceCallShowsSignalHalo(state),
              borderRadius: BorderRadius.circular(22),
              color: haloColor,
              pulseKey: '${state.callId}:${state.phase}:${surface.mode}',
              pulseOnMount: rainVoiceCallShowsSignalHalo(state),
              callSurface: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(
                    alpha: scheme.brightness == Brightness.dark ? 0.96 : 0.98,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: accent.withValues(alpha: 0.34)),
                  boxShadow: <BoxShadow>[
                    if (performance.allowExpensiveCallEffects)
                      BoxShadow(
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                        color: Colors.black.withValues(
                          alpha: scheme.brightness == Brightness.dark
                              ? 0.34
                              : 0.13,
                        ),
                      ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final compact = constraints.maxWidth < 560;
                          return compact
                              ? _CompactCallManagerContent(
                                  state: state,
                                  surface: surface,
                                  displayName: displayName,
                                  gender: gender,
                                  accent: accent,
                                  onToggleMute: onToggleMute,
                                  onToggleCamera: onToggleCamera,
                                  onToggleDeafen: onToggleDeafen,
                                  onRestore: onRestore,
                                  onFullscreen: onFullscreen,
                                  onHangUp: onHangUp,
                                )
                              : _WideCallManagerContent(
                                  state: state,
                                  surface: surface,
                                  displayName: displayName,
                                  gender: gender,
                                  accent: accent,
                                  onToggleMute: onToggleMute,
                                  onToggleCamera: onToggleCamera,
                                  onToggleDeafen: onToggleDeafen,
                                  onRestore: onRestore,
                                  onFullscreen: onFullscreen,
                                  onHangUp: onHangUp,
                                );
                        },
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

class _WideCallManagerContent extends StatelessWidget {
  const _WideCallManagerContent({
    required this.state,
    required this.surface,
    required this.displayName,
    required this.gender,
    required this.accent,
    required this.onToggleMute,
    required this.onToggleCamera,
    required this.onToggleDeafen,
    required this.onRestore,
    required this.onFullscreen,
    required this.onHangUp,
  });

  final VoiceCallState state;
  final CallSurfaceState surface;
  final String displayName;
  final String? gender;
  final Color accent;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onToggleDeafen;
  final VoidCallback onRestore;
  final VoidCallback onFullscreen;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _CallIdentity(
          state: state,
          displayName: displayName,
          gender: gender,
          accent: accent,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _CallStatusText(state: state, displayName: displayName),
        ),
        const SizedBox(width: 10),
        _CallManagerActions(
          state: state,
          surface: surface,
          onToggleMute: onToggleMute,
          onToggleCamera: onToggleCamera,
          onToggleDeafen: onToggleDeafen,
          onRestore: onRestore,
          onFullscreen: onFullscreen,
          onHangUp: onHangUp,
        ),
      ],
    );
  }
}

class _CompactCallManagerContent extends StatelessWidget {
  const _CompactCallManagerContent({
    required this.state,
    required this.surface,
    required this.displayName,
    required this.gender,
    required this.accent,
    required this.onToggleMute,
    required this.onToggleCamera,
    required this.onToggleDeafen,
    required this.onRestore,
    required this.onFullscreen,
    required this.onHangUp,
  });

  final VoiceCallState state;
  final CallSurfaceState surface;
  final String displayName;
  final String? gender;
  final Color accent;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onToggleDeafen;
  final VoidCallback onRestore;
  final VoidCallback onFullscreen;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey<String>('rain-call-manager-compact-row'),
      children: <Widget>[
        Expanded(
          child: _CallIdentity(
            state: state,
            displayName: displayName,
            gender: gender,
            accent: accent,
          ),
        ),
        _CallManagerIconButton(
          visual: rainVoiceCallControlVisual(
            state,
            CallControlCapability.microphone,
          ),
          onPressed: state.isActive ? onToggleMute : null,
        ),
        if (state.isVideo)
          _CallManagerIconButton(
            visual: rainVoiceCallControlVisual(
              state,
              CallControlCapability.camera,
            ),
            onPressed: state.isActive ? onToggleCamera : null,
          ),
        _CallRestoreButton(surface: surface, onRestore: onRestore),
        if (state.isVideo)
          _CallFullscreenButton(
            surface: surface,
            onFullscreen: onFullscreen,
            onRestore: onRestore,
          ),
        _HangUpButton(onHangUp: onHangUp, state: state),
      ],
    );
  }
}

class _CallIdentity extends StatelessWidget {
  const _CallIdentity({
    required this.state,
    required this.displayName,
    required this.gender,
    required this.accent,
  });

  final VoiceCallState state;
  final String displayName;
  final String? gender;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RainAvatar(
          name: displayName,
          size: 38,
          statusColor: accent,
          gender: gender,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                state.isVideo ? 'Video call' : 'Voice call',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CallStatusText extends StatelessWidget {
  const _CallStatusText({required this.state, required this.displayName});

  final VoiceCallState state;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RainCallTicker(
      state: state,
      builder: (BuildContext context, int now) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              rainVoiceCallTitle(state, displayName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              rainVoiceCallDetail(state, now),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.68),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CallManagerActions extends StatelessWidget {
  const _CallManagerActions({
    required this.state,
    required this.surface,
    required this.onToggleMute,
    required this.onToggleCamera,
    required this.onToggleDeafen,
    required this.onRestore,
    required this.onFullscreen,
    required this.onHangUp,
  });

  final VoiceCallState state;
  final CallSurfaceState surface;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onToggleDeafen;
  final VoidCallback onRestore;
  final VoidCallback onFullscreen;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _CallPrimaryToggles(
          state: state,
          onToggleMute: onToggleMute,
          onToggleCamera: onToggleCamera,
          onToggleDeafen: onToggleDeafen,
        ),
        _CallRestoreButton(surface: surface, onRestore: onRestore),
        if (state.isVideo)
          _CallFullscreenButton(
            surface: surface,
            onFullscreen: onFullscreen,
            onRestore: onRestore,
          ),
        _HangUpButton(onHangUp: onHangUp, state: state),
      ],
    );
  }
}

class _CallPrimaryToggles extends StatelessWidget {
  const _CallPrimaryToggles({
    required this.state,
    required this.onToggleMute,
    required this.onToggleCamera,
    required this.onToggleDeafen,
  });

  final VoiceCallState state;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onToggleDeafen;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _CallManagerIconButton(
          visual: rainVoiceCallControlVisual(
            state,
            CallControlCapability.microphone,
          ),
          onPressed: state.isActive ? onToggleMute : null,
        ),
        if (state.isVideo)
          _CallManagerIconButton(
            visual: rainVoiceCallControlVisual(
              state,
              CallControlCapability.camera,
            ),
            onPressed: state.isActive ? onToggleCamera : null,
          ),
        _CallManagerIconButton(
          visual: rainVoiceCallControlVisual(
            state,
            CallControlCapability.deafen,
          ),
          onPressed: state.isActive ? onToggleDeafen : null,
        ),
      ],
    );
  }
}

class _CallRestoreButton extends StatelessWidget {
  const _CallRestoreButton({required this.surface, required this.onRestore});

  final CallSurfaceState surface;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final isExpanded = surface.mode == CallSurfaceMode.expanded;
    return _CallManagerIconButton(
      visual: RainCallControlVisual(
        tooltip: isExpanded ? 'Hide call panel' : 'Restore call panel',
        icon: isExpanded ? Icons.keyboard_arrow_up : Icons.open_in_full,
      ),
      onPressed: onRestore,
    );
  }
}

class _CallFullscreenButton extends StatelessWidget {
  const _CallFullscreenButton({
    required this.surface,
    required this.onFullscreen,
    required this.onRestore,
  });

  final CallSurfaceState surface;
  final VoidCallback onFullscreen;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final isFullscreen = surface.mode == CallSurfaceMode.fullscreen;
    return _CallManagerIconButton(
      visual: RainCallControlVisual(
        tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen video',
        icon: isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
      ),
      onPressed: isFullscreen ? onRestore : onFullscreen,
    );
  }
}

class _HangUpButton extends StatelessWidget {
  const _HangUpButton({required this.onHangUp, required this.state});

  final VoidCallback onHangUp;
  final VoiceCallState state;

  @override
  Widget build(BuildContext context) {
    final visual = rainVoiceCallTerminalActionVisual(state);
    return _CallManagerIconButton(visual: visual, onPressed: onHangUp);
  }
}

class _CallManagerIconButton extends StatelessWidget {
  const _CallManagerIconButton({required this.visual, required this.onPressed});

  final RainCallControlVisual visual;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = visual.danger ? scheme.error : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox.square(
        dimension: 40,
        child: IconButton(
          tooltip: visual.tooltip,
          onPressed: onPressed,
          color: onPressed == null
              ? scheme.onSurface.withValues(alpha: 0.32)
              : foreground,
          style: IconButton.styleFrom(
            backgroundColor: visual.danger
                ? scheme.errorContainer.withValues(alpha: 0.60)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: Icon(visual.icon, size: 21),
        ),
      ),
    );
  }
}
