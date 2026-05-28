import 'package:flutter/material.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'package:rain/presentation/branding/rain_ripple_halo_surface.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

typedef ConnectionRequestActionCallback =
    Future<void> Function(
      ConnectionRequestSurfaceModel surface,
      ConnectionRequestActionModel action,
    );

class ConnectionRequestStatusChip extends StatelessWidget {
  const ConnectionRequestStatusChip({
    super.key,
    required this.surface,
    this.onAction,
    this.compact = false,
  });

  final ConnectionRequestSurfaceModel surface;
  final ConnectionRequestActionCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = _toneFor(surface.status, scheme);
    final action = _primaryActionFor(surface);
    final feedback = surface.feedback;
    final quotaText = _quotaText(surface);
    final feedbackText = _feedbackText(feedback);
    final semantic = StringBuffer()
      ..write('${surface.title}. ')
      ..write('${surface.subtitle}. ')
      ..write('Status ${_statusLabel(surface.status)}.');
    if (feedbackText != null) {
      semantic.write(' $feedbackText');
    }

    return Semantics(
      container: true,
      label: semantic.toString(),
      child: RainRippleHaloSurface(
        enabled: !surface.status.isTerminal,
        color: tone,
        borderRadius: BorderRadius.circular(16),
        pulseKey:
            '${surface.requestId}:${surface.direction.name}:${surface.status.name}',
        pulseOnMount: !surface.status.isTerminal,
        child: DecoratedBox(
          key: ValueKey<String>(
            'connection-request-status-${surface.requestId}',
          ),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              tone.withValues(alpha: 0.08),
              scheme.surfaceContainerHighest.withValues(alpha: 0.58),
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tone.withValues(alpha: 0.34)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, compact ? 8 : 10, 10, 10),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final stackActions = compact || constraints.maxWidth < 340;
                final content = _ConnectionRequestChipContent(
                  surface: surface,
                  tone: tone,
                  feedbackText: feedbackText,
                  quotaText: quotaText,
                );
                final actionButton = action == null
                    ? null
                    : _ConnectionRequestChipAction(
                        surface: surface,
                        action: action,
                        tone: tone,
                        onAction: onAction,
                      );
                if (actionButton == null) {
                  return content;
                }
                if (stackActions) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      content,
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: actionButton,
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(child: content),
                    const SizedBox(width: 10),
                    actionButton,
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

ConnectionRequestActionModel? _primaryActionFor(
  ConnectionRequestSurfaceModel surface,
) {
  if (surface.actions.isEmpty) {
    return null;
  }
  final action = surface.actions.first;
  if (surface.direction == ConnectionRequestDirection.outbound &&
      surface.status.isTerminal &&
      action.kind == ConnectionRequestActionKind.dismiss) {
    return null;
  }
  return action;
}

class _ConnectionRequestChipContent extends StatelessWidget {
  const _ConnectionRequestChipContent({
    required this.surface,
    required this.tone,
    required this.feedbackText,
    required this.quotaText,
  });

  final ConnectionRequestSurfaceModel surface;
  final Color tone;
  final String? feedbackText;
  final String? quotaText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox.square(
          dimension: 34,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconFor(surface.status), color: tone, size: 18),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    surface.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  _StatusPill(label: _statusLabel(surface.status), color: tone),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                surface.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (feedbackText != null) ...<Widget>[
                const SizedBox(height: 5),
                Text(
                  feedbackText!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ] else if (quotaText != null) ...<Widget>[
                const SizedBox(height: 5),
                Text(
                  quotaText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.58),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectionRequestChipAction extends StatelessWidget {
  const _ConnectionRequestChipAction({
    required this.surface,
    required this.action,
    required this.tone,
    this.onAction,
  });

  final ConnectionRequestSurfaceModel surface;
  final ConnectionRequestActionModel action;
  final Color tone;
  final ConnectionRequestActionCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tooltip =
        action.tooltip ??
        (action.enabled
            ? action.semanticLabel
            : _disabledActionMessage(action, surface));
    return Semantics(
      container: true,
      button: true,
      enabled: action.enabled,
      label: action.enabled ? action.semanticLabel : tooltip,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton.icon(
          key: ValueKey<String>(
            'connection-request-action-${surface.requestId}-${action.kind.name}',
          ),
          onPressed: action.enabled && onAction != null
              ? () => onAction!(surface, action)
              : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: tone,
            side: BorderSide(color: tone.withValues(alpha: 0.44)),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(44, 36),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          icon: Icon(_actionIcon(action.kind), size: 16),
          label: Text(action.label),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

String? _feedbackText(ConnectionRequestFeedbackModel? feedback) {
  if (feedback == null) {
    return null;
  }
  final retryAfter = feedback.retryAfter;
  if (retryAfter == null || retryAfter <= Duration.zero) {
    return feedback.message;
  }
  return '${feedback.message} Try again in ${_durationLabel(retryAfter)}.';
}

String? _quotaText(ConnectionRequestSurfaceModel surface) {
  final quota = surface.quota;
  if (quota == null || !surface.status.isTerminal) {
    return null;
  }
  final remaining =
      (quota.dailyLimit + quota.extraCreditsRemaining - quota.usedToday)
          .clamp(0, 1 << 31)
          .toInt();
  return '$remaining connection request${remaining == 1 ? '' : 's'} left today.';
}

String _durationLabel(Duration duration) {
  if (duration.inMinutes >= 1) {
    final minutes = duration.inMinutes;
    return '$minutes minute${minutes == 1 ? '' : 's'}';
  }
  final seconds = duration.inSeconds <= 0 ? 1 : duration.inSeconds;
  return '$seconds second${seconds == 1 ? '' : 's'}';
}

String _disabledActionMessage(
  ConnectionRequestActionModel action,
  ConnectionRequestSurfaceModel surface,
) {
  if (action.reasonCode != null) {
    return messageForConnectionRequestReason(
      action.reasonCode!,
      surface.peerLabel,
    );
  }
  return '${action.label} is unavailable for this connection request.';
}

String _statusLabel(ConnectionRequestStatus status) {
  return switch (status) {
    ConnectionRequestStatus.pending => 'Pending',
    ConnectionRequestStatus.seen => 'Seen',
    ConnectionRequestStatus.accepted => 'Accepted',
    ConnectionRequestStatus.rejected => 'Declined',
    ConnectionRequestStatus.canceled => 'Canceled',
    ConnectionRequestStatus.expired => 'Expired',
    ConnectionRequestStatus.failed => 'Failed',
  };
}

IconData _iconFor(ConnectionRequestStatus status) {
  return switch (status) {
    ConnectionRequestStatus.pending => Icons.schedule_send_outlined,
    ConnectionRequestStatus.seen => Icons.visibility_outlined,
    ConnectionRequestStatus.accepted => Icons.check_circle_outline,
    ConnectionRequestStatus.rejected => Icons.do_not_disturb_on_outlined,
    ConnectionRequestStatus.canceled => Icons.cancel_outlined,
    ConnectionRequestStatus.expired => Icons.timer_off_outlined,
    ConnectionRequestStatus.failed => Icons.error_outline,
  };
}

IconData _actionIcon(ConnectionRequestActionKind kind) {
  return switch (kind) {
    ConnectionRequestActionKind.cancel => Icons.close,
    ConnectionRequestActionKind.connect => Icons.hub_outlined,
    ConnectionRequestActionKind.ignore => Icons.visibility_off_outlined,
    ConnectionRequestActionKind.reject => Icons.do_not_disturb_on_outlined,
    ConnectionRequestActionKind.mute => Icons.notifications_off_outlined,
    ConnectionRequestActionKind.unmute => Icons.notifications_active_outlined,
    ConnectionRequestActionKind.dismiss => Icons.check,
  };
}

Color _toneFor(ConnectionRequestStatus status, ColorScheme scheme) {
  return switch (status) {
    ConnectionRequestStatus.pending => RainColors.mistCyan,
    ConnectionRequestStatus.seen => scheme.tertiary,
    ConnectionRequestStatus.accepted => RainColors.peerMint,
    ConnectionRequestStatus.rejected => scheme.error,
    ConnectionRequestStatus.canceled => scheme.outline,
    ConnectionRequestStatus.expired => RainColors.warning,
    ConnectionRequestStatus.failed => scheme.error,
  };
}
