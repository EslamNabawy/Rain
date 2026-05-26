import 'package:flutter/material.dart';

import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';

class RainCallEndedSurface extends StatelessWidget {
  const RainCallEndedSurface({
    super.key,
    required this.summary,
    required this.onClose,
    required this.onCallAgain,
    this.fullscreen = false,
  });

  final CallEndSummary summary;
  final VoidCallback onClose;
  final VoidCallback onCallAgain;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: fullscreen ? 520 : 430,
          minWidth: 260,
        ),
        child: _EndedCallCard(
          summary: summary,
          onClose: onClose,
          onCallAgain: onCallAgain,
        ),
      ),
    );

    if (fullscreen) {
      return ColoredBox(
        key: const ValueKey<String>('rain-call-ended-fullscreen-surface'),
        color: scheme.surface,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: content,
          ),
        ),
      );
    }

    return IgnorePointer(
      ignoring: false,
      child: Center(
        key: const ValueKey<String>('rain-call-ended-popup-surface'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      ),
    );
  }
}

class _EndedCallCard extends StatelessWidget {
  const _EndedCallCard({
    required this.summary,
    required this.onClose,
    required this.onCallAgain,
  });

  final CallEndSummary summary;
  final VoidCallback onClose;
  final VoidCallback onCallAgain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mediaLabel = summary.isVideo ? 'Video call ended' : 'Voice call ended';
    final initiatorLabel = switch (summary.initiator) {
      CallEndInitiator.local => 'Ended by you',
      CallEndInitiator.remote => 'Ended by ${summary.peerLabel}',
      CallEndInitiator.system => 'Ended by Rain',
    };
    final reason = summary.reason.trim().isEmpty ? 'Call ended.' : summary.reason;
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(
            alpha: scheme.brightness == Brightness.dark ? 0.96 : 0.99,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.28)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              blurRadius: 28,
              offset: const Offset(0, 16),
              color: Colors.black.withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.34 : 0.12,
              ),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const RainPeerCoreMark(size: 58),
              const SizedBox(height: 16),
              Text(
                mediaLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                summary.peerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              _EndedCallInfoRow(
                icon: Icons.timer_outlined,
                label: rainFormatVoiceElapsed(summary.duration),
              ),
              const SizedBox(height: 8),
              _EndedCallInfoRow(
                icon: Icons.call_end_outlined,
                label: initiatorLabel,
              ),
              const SizedBox(height: 8),
              _EndedCallInfoRow(
                icon: Icons.info_outline,
                label: reason,
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onClose,
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onCallAgain,
                      icon: Icon(
                        summary.isVideo
                            ? Icons.videocam_outlined
                            : Icons.call_outlined,
                      ),
                      label: const Text('Call again'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndedCallInfoRow extends StatelessWidget {
  const _EndedCallInfoRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.76),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
