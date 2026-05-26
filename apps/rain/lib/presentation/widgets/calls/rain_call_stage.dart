import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rain/application/runtime/video_call_renderers.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';

const rainRemotePrimaryVideoKey = Key('rain-remote-primary-video');
const rainLocalPreviewVideoKey = Key('rain-local-preview-video');
const rainVoiceOnlyStageKey = Key('rain-voice-only-stage');
const rainLocalPrimaryVideoKey = Key('rain-local-primary-video');
const rainRemotePreviewVideoKey = Key('rain-remote-preview-video');

class RainCallStage extends StatelessWidget {
  const RainCallStage({
    super.key,
    required this.state,
    required this.accent,
    this.renderers,
    this.layout = RainCallStageLayout.expanded,
    this.primaryRole = VideoPrimaryRole.remote,
    this.onTogglePrimaryRole,
  });

  final VoiceCallState state;
  final Color accent;
  final VideoCallRenderers? renderers;
  final RainCallStageLayout layout;
  final VideoPrimaryRole primaryRole;
  final VoidCallback? onTogglePrimaryRole;

  @override
  Widget build(BuildContext context) {
    if (!state.isVideo) {
      return _RainVoiceOnlyCallStage(state: state, accent: accent);
    }

    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(layout.borderRadius);
    final stage = Container(
      key: const ValueKey<String>('rain-call-video-stage'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(
          alpha: layout == RainCallStageLayout.fullscreen ? 0.90 : 0.46,
        ),
        borderRadius: radius,
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final previewWidth = _localPreviewWidth(constraints.maxWidth);
            final preview = _previewVideoSurface();
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                layout == RainCallStageLayout.pip
                    ? _primaryVideoSurface(compact: true)
                    : _primaryVideoSurface(compact: false),
                if (layout.showsLocalPreview)
                  Positioned(
                    top: layout == RainCallStageLayout.fullscreen ? 88 : 10,
                    right: layout == RainCallStageLayout.fullscreen ? 18 : 10,
                    width: previewWidth,
                    child: GestureDetector(
                      key: const ValueKey<String>(
                        'rain-call-video-preview-hit-target',
                      ),
                      behavior: HitTestBehavior.opaque,
                      onTap: onTogglePrimaryRole,
                      child: preview,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    if (layout == RainCallStageLayout.fullscreen) {
      return SizedBox.expand(
        child: KeyedSubtree(
          key: const ValueKey<String>('rain-call-video-fullscreen-layout'),
          child: stage,
        ),
      );
    }

    if (layout == RainCallStageLayout.pip) {
      return AspectRatio(
        key: const ValueKey<String>('rain-call-video-pip-layout'),
        aspectRatio: 16 / 9,
        child: stage,
      );
    }

    return AspectRatio(
      key: const ValueKey<String>('rain-call-video-expanded-layout'),
      aspectRatio: 16 / 9,
      child: stage,
    );
  }

  double _localPreviewWidth(double maxWidth) {
    if (layout == RainCallStageLayout.fullscreen) {
      return maxWidth < 520 ? 112 : 156;
    }
    return maxWidth < 320 ? 96 : 124;
  }

  Widget _primaryVideoSurface({required bool compact}) {
    return switch (primaryRole) {
      VideoPrimaryRole.remote => KeyedSubtree(
        key: rainRemotePrimaryVideoKey,
        child: _RainRemoteVideoSurface(
          state: state,
          renderers: renderers,
          accent: accent,
          compact: compact,
        ),
      ),
      VideoPrimaryRole.local => KeyedSubtree(
        key: rainLocalPrimaryVideoKey,
        child: _RainLocalVideoSurface(
          state: state,
          renderers: renderers,
          accent: accent,
          compact: compact,
        ),
      ),
    };
  }

  Widget _previewVideoSurface() {
    return switch (primaryRole) {
      VideoPrimaryRole.remote => KeyedSubtree(
        key: rainLocalPreviewVideoKey,
        child: _RainLocalVideoPreview(
          state: state,
          renderers: renderers,
          accent: accent,
        ),
      ),
      VideoPrimaryRole.local => KeyedSubtree(
        key: rainRemotePreviewVideoKey,
        child: _RainRemoteVideoPreview(
          state: state,
          renderers: renderers,
          accent: accent,
        ),
      ),
    };
  }
}

enum RainCallStageLayout {
  expanded,
  fullscreen,
  pip;

  bool get showsLocalPreview => this != RainCallStageLayout.pip;

  double get borderRadius {
    return switch (this) {
      RainCallStageLayout.fullscreen => 0,
      RainCallStageLayout.pip => 18,
      RainCallStageLayout.expanded => 20,
    };
  }
}

class _RainRemoteVideoSurface extends StatelessWidget {
  const _RainRemoteVideoSurface({
    required this.state,
    required this.renderers,
    required this.accent,
    this.compact = false,
  });

  final VoiceCallState state;
  final VideoCallRenderers? renderers;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final remote = renderers?.remoteRenderer;
    final hasRemoteVideo =
        state.hasRemoteVideo || renderers?.state.hasRemoteStream == true;
    if (remote != null && hasRemoteVideo && !state.isRemoteCameraMuted) {
      return remote.buildView(
        key: const ValueKey<String>('rain-call-remote-video-view'),
      );
    }

    final icon = state.isRemoteCameraMuted
        ? Icons.videocam_off
        : state.videoFirstFrameTimedOut
        ? Icons.visibility_off_outlined
        : Icons.videocam_outlined;
    final label = state.isRemoteCameraMuted
        ? 'Peer camera off'
        : state.videoFirstFrameTimedOut
        ? 'Video stream not visible'
        : 'Waiting for video';
    final key = state.isRemoteCameraMuted
        ? const ValueKey<String>('rain-call-remote-camera-muted')
        : state.videoFirstFrameTimedOut
        ? const ValueKey<String>('rain-call-video-frame-timeout')
        : const ValueKey<String>('rain-call-remote-video-placeholder');
    return _RainVideoPlaceholder(
      key: key,
      icon: icon,
      label: label,
      accent: accent,
      compact: compact,
    );
  }
}

class _RainLocalVideoPreview extends StatelessWidget {
  const _RainLocalVideoPreview({
    required this.state,
    required this.renderers,
    required this.accent,
  });

  final VoiceCallState state;
  final VideoCallRenderers? renderers;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _RainVideoPreviewFrame(
      accent: accent,
      child: _RainLocalVideoSurface(
        state: state,
        renderers: renderers,
        accent: accent,
        compact: true,
      ),
    );
  }
}

class _RainRemoteVideoPreview extends StatelessWidget {
  const _RainRemoteVideoPreview({
    required this.state,
    required this.renderers,
    required this.accent,
  });

  final VoiceCallState state;
  final VideoCallRenderers? renderers;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _RainVideoPreviewFrame(
      accent: accent,
      child: _RainRemoteVideoSurface(
        state: state,
        renderers: renderers,
        accent: accent,
        compact: true,
      ),
    );
  }
}

class _RainLocalVideoSurface extends StatelessWidget {
  const _RainLocalVideoSurface({
    required this.state,
    required this.renderers,
    required this.accent,
    this.compact = false,
  });

  final VoiceCallState state;
  final VideoCallRenderers? renderers;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final local = renderers?.localRenderer;
    final hasLocalVideo =
        state.hasLocalVideo || renderers?.state.hasLocalStream == true;
    if (local != null && hasLocalVideo && !state.isCameraMuted) {
      return local.buildView(
        key: const ValueKey<String>('rain-call-local-video-view'),
        mirror: true,
      );
    }

    return _RainVideoPlaceholder(
      key: state.isCameraMuted
          ? const ValueKey<String>('rain-call-local-camera-muted')
          : const ValueKey<String>('rain-call-local-video-placeholder'),
      icon: state.isCameraMuted ? Icons.videocam_off : Icons.person_outline,
      label: state.isCameraMuted ? 'Camera off' : 'Preview',
      accent: accent,
      compact: compact,
    );
  }
}

class _RainVideoPreviewFrame extends StatelessWidget {
  const _RainVideoPreviewFrame({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.42)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              blurRadius: 16,
              color: Colors.black.withValues(alpha: 0.20),
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(13), child: child),
      ),
    );
  }
}

class _RainVideoPlaceholder extends StatelessWidget {
  const _RainVideoPlaceholder({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!compact)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RainPeerCoreAnimatedMark(
                  key: const ValueKey<String>('rain-call-video-peer-core-mark'),
                  size: 56,
                  animate: true,
                ),
              )
            else
              Icon(
                icon,
                size: compact ? 22 : 42,
                color: accent.withValues(alpha: 0.78),
              ),
            SizedBox(height: compact ? 4 : 10),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 14),
              child: Text(
                label,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style:
                    (compact
                            ? Theme.of(context).textTheme.labelSmall
                            : Theme.of(context).textTheme.labelLarge)
                        ?.copyWith(
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

class _RainVoiceOnlyCallStage extends StatelessWidget {
  const _RainVoiceOnlyCallStage({required this.state, required this.accent});

  final VoiceCallState state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(28);
    return Container(
      key: rainVoiceOnlyStageKey,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: borderRadius,
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          key: const ValueKey<String>('rain-call-audio-stage'),
          height: 172,
          child: Center(
            child: _RainCallStatusGlyph(state: state, accent: accent),
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
    final showPeerCoreMark =
        state.phase == VoiceCallPhase.connectingPeer ||
        state.phase == VoiceCallPhase.connectingMedia ||
        state.phase == VoiceCallPhase.incomingRinging ||
        state.phase == VoiceCallPhase.outgoingRinging;
    return Container(
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
