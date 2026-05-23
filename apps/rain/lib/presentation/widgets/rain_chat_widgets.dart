import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rain/application/runtime/voice_call_state.dart';

const String _maleAvatarAsset = 'assets/gender avatar/man-avatar.svg';
const String _femaleAvatarAsset = 'assets/gender avatar/woman-avatar.svg';

class RainAvatar extends StatelessWidget {
  const RainAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.statusColor,
    this.gender,
  });

  final String name;
  final double size;
  final Color? statusColor;
  final String? gender;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final borderRadius = BorderRadius.circular(size * 0.34);
    final avatarAsset = _avatarAssetForGender(gender);

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: avatarAsset == null
                ? ClipRRect(
                    borderRadius: borderRadius,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.onSurface,
                              ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: SvgPicture.asset(
                      avatarAsset,
                      width: size,
                      height: size,
                      fit: BoxFit.contain,
                    ),
                  ),
          ),
          if (avatarAsset == null)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.42),
                    ),
                  ),
                ),
              ),
            ),
          if (statusColor != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.25,
                height: size * 0.25,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _avatarAssetForGender(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'male' => _maleAvatarAsset,
      'female' => _femaleAvatarAsset,
      _ => null,
    };
  }
}

class RainMiniStatusChip extends StatelessWidget {
  const RainMiniStatusChip({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RainLiveLinkBar extends StatelessWidget {
  const RainLiveLinkBar({
    super.key,
    required this.label,
    required this.detail,
    required this.color,
    required this.icon,
    required this.strength,
    this.isBusy = false,
    this.onTap,
  });

  final String label;
  final String detail;
  final Color color;
  final IconData icon;
  final int strength;
  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final boundedStrength = strength.clamp(0, 4).toInt();

    return Semantics(
      button: onTap != null,
      label: 'Live Link Bar. $label. $detail',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: <Widget>[
                  Container(
                    constraints: const BoxConstraints(maxWidth: 142),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (isBusy)
                          SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: color,
                            ),
                          )
                        else
                          Icon(icon, size: 15, color: color),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.68),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List<Widget>.generate(4, (int index) {
                      final active = index < boundedStrength;
                      return Container(
                        key: ValueKey<String>(
                          'rain-link-meter-${active ? 'on' : 'off'}-$index',
                        ),
                        width: 5,
                        height: 18,
                        margin: EdgeInsets.only(left: index == 0 ? 0 : 4),
                        decoration: BoxDecoration(
                          color: active
                              ? color
                              : scheme.outlineVariant.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RainMessageDayDivider extends StatelessWidget {
  const RainMessageDayDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Divider(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.58),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

class RainMessageBubble extends StatelessWidget {
  const RainMessageBubble({
    super.key,
    required this.text,
    required this.timeLabel,
    required this.isOutgoing,
    required this.startsCluster,
    required this.endsCluster,
    required this.maxWidth,
    this.deliveryLabel,
    this.deliveryColor,
    this.onRetry,
    this.onOpenActions,
  });

  final String text;
  final String timeLabel;
  final bool isOutgoing;
  final bool startsCluster;
  final bool endsCluster;
  final double maxWidth;
  final String? deliveryLabel;
  final Color? deliveryColor;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final bubbleColor = isOutgoing
        ? (isDark ? const Color(0xFF1D7E8E) : scheme.primaryContainer)
        : (isDark ? const Color(0xFF18262E) : scheme.surfaceContainerHighest);
    final textColor = isOutgoing
        ? (isDark ? Colors.white : scheme.onPrimaryContainer)
        : scheme.onSurface;
    final metadataColor = textColor.withValues(alpha: 0.72);
    final tailRadius = const Radius.circular(6);
    final roundRadius = const Radius.circular(20);
    final radius = BorderRadius.only(
      topLeft: roundRadius,
      topRight: roundRadius,
      bottomLeft: isOutgoing || !endsCluster ? roundRadius : tailRadius,
      bottomRight: isOutgoing && endsCluster ? tailRadius : roundRadius,
    );

    return GestureDetector(
      onLongPress: onOpenActions,
      onSecondaryTap: onOpenActions,
      child: Align(
        alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            margin: EdgeInsets.only(
              top: startsCluster ? 8 : 2,
              bottom: endsCluster ? 8 : 1,
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 9),
            decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    height: 1.28,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: metadataColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isOutgoing && deliveryLabel != null) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: deliveryColor ?? metadataColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        deliveryLabel!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: deliveryColor ?? metadataColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (onOpenActions != null) ...<Widget>[
                      const SizedBox(width: 4),
                      SizedBox.square(
                        dimension: 28,
                        child: IconButton(
                          tooltip: 'Message actions',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          onPressed: onOpenActions,
                          icon: Icon(
                            Icons.more_horiz,
                            size: 17,
                            color: metadataColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (onRetry != null) ...<Widget>[
                  const SizedBox(height: 7),
                  TextButton.icon(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: deliveryColor ?? textColor,
                    ),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RainComposerCommandStrip extends StatelessWidget {
  const RainComposerCommandStrip({
    super.key,
    required this.label,
    required this.detail,
    required this.color,
    required this.icon,
    this.isBusy = false,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final String label;
  final String detail;
  final Color color;
  final IconData icon;
  final bool isBusy;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final compact = constraints.maxWidth < 360;

        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isBusy
                      ? SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        )
                      : Icon(icon, color: color, size: 16),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(width: 8),
                compact
                    ? IconButton(
                        tooltip: actionLabel,
                        visualDensity: VisualDensity.compact,
                        onPressed: onAction,
                        icon: Icon(actionIcon ?? Icons.tune, size: 18),
                      )
                    : TextButton.icon(
                        onPressed: onAction,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: color,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        icon: Icon(actionIcon ?? Icons.tune, size: 16),
                        label: Text(actionLabel!),
                      ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class RainVoiceCallButton extends StatelessWidget {
  const RainVoiceCallButton({
    super.key,
    required this.peerId,
    required this.state,
    required this.canStart,
    required this.hasActiveTransfer,
    required this.onStart,
  });

  final String peerId;
  final VoiceCallState state;
  final bool canStart;
  final bool hasActiveTransfer;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final isCurrentCall = state.peerId == peerId && state.hasCall;
    return IconButton(
      tooltip: _voiceCallButtonTooltip(
        peerId: peerId,
        state: state,
        hasActiveTransfer: hasActiveTransfer,
      ),
      onPressed: canStart ? onStart : null,
      icon: Icon(isCurrentCall ? Icons.call : Icons.call_outlined),
    );
  }
}

class RainVoiceCallPanel extends StatelessWidget {
  const RainVoiceCallPanel({
    super.key,
    required this.state,
    required this.displayName,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
  });

  final VoiceCallState state;
  final String displayName;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _voiceCallAccent(context, state);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final status = Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_voiceCallIcon(state), color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _voiceCallTitle(state, displayName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _voiceCallDetail(state, now),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.70),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
          final actions = _RainVoiceCallActions(
            state: state,
            onAccept: onAccept,
            onReject: onReject,
            onHangUp: onHangUp,
            onRetry: onRetry,
            onToggleMute: onToggleMute,
          );
          if (constraints.maxWidth < 430) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                status,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: status),
              const SizedBox(width: 10),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _RainVoiceCallActions extends StatelessWidget {
  const _RainVoiceCallActions({
    required this.state,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
  });

  final VoiceCallState state;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    if (state.phase == VoiceCallPhase.incomingRinging) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: onReject,
            icon: const Icon(Icons.call_end),
            label: const Text('Reject'),
          ),
          FilledButton.icon(
            onPressed: onAccept,
            icon: const Icon(Icons.call),
            label: const Text('Accept'),
          ),
        ],
      );
    }

    if (state.phase == VoiceCallPhase.failed) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: <Widget>[
          if (_voiceCallCanRetry(state))
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          TextButton.icon(
            onPressed: onHangUp,
            icon: const Icon(Icons.close),
            label: const Text('Dismiss'),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: <Widget>[
        IconButton(
          tooltip: state.isMuted ? 'Unmute microphone' : 'Mute microphone',
          onPressed: state.isActive ? onToggleMute : null,
          icon: Icon(state.isMuted ? Icons.mic_off : Icons.mic),
        ),
        IconButton.filled(
          tooltip: 'Hang up',
          onPressed: onHangUp,
          icon: const Icon(Icons.call_end),
        ),
      ],
    );
  }
}

String _voiceCallButtonTooltip({
  required String peerId,
  required VoiceCallState state,
  required bool hasActiveTransfer,
}) {
  if (hasActiveTransfer) {
    return 'Finish the active file transfer first.';
  }
  if (state.hasCall && state.phase != VoiceCallPhase.failed) {
    final activePeerId = state.peerId;
    return activePeerId == peerId
        ? 'Voice call in progress'
        : 'Finish the active call with @$activePeerId first.';
  }
  return 'Start voice call';
}

IconData _voiceCallIcon(VoiceCallState state) {
  return switch (state.phase) {
    VoiceCallPhase.failed => Icons.error_outline,
    VoiceCallPhase.incomingRinging => Icons.call_received,
    VoiceCallPhase.outgoingRinging => Icons.call_made,
    VoiceCallPhase.active => state.isMuted ? Icons.mic_off : Icons.call,
    VoiceCallPhase.connectingPeer ||
    VoiceCallPhase.connectingMedia ||
    VoiceCallPhase.ending ||
    VoiceCallPhase.idle => Icons.call_outlined,
  };
}

Color _voiceCallAccent(BuildContext context, VoiceCallState state) {
  final scheme = Theme.of(context).colorScheme;
  return switch (state.phase) {
    VoiceCallPhase.failed => scheme.error,
    VoiceCallPhase.active => const Color(0xFF2DD4A3),
    VoiceCallPhase.incomingRinging ||
    VoiceCallPhase.outgoingRinging => scheme.tertiary,
    VoiceCallPhase.connectingPeer ||
    VoiceCallPhase.connectingMedia ||
    VoiceCallPhase.ending ||
    VoiceCallPhase.idle => scheme.primary,
  };
}

String _voiceCallTitle(VoiceCallState state, String displayName) {
  return switch (state.phase) {
    VoiceCallPhase.incomingRinging => '$displayName is calling',
    VoiceCallPhase.outgoingRinging => 'Calling $displayName',
    VoiceCallPhase.active => 'Voice call with $displayName',
    VoiceCallPhase.failed => 'Voice call failed',
    VoiceCallPhase.ending => 'Ending voice call',
    VoiceCallPhase.connectingPeer ||
    VoiceCallPhase.connectingMedia => 'Connecting voice call',
    VoiceCallPhase.idle => 'Voice call',
  };
}

String _voiceCallDetail(VoiceCallState state, int nowMs) {
  if (state.phase == VoiceCallPhase.active && state.startedAt != null) {
    final elapsed = Duration(milliseconds: nowMs - state.startedAt!);
    final labels = <String>[_formatVoiceElapsed(elapsed)];
    if (state.isMuted) {
      labels.add('Muted');
    }
    if (state.isRemoteMuted) {
      labels.add('Peer muted');
    }
    return labels.join(' / ');
  }
  return switch (state.phase) {
    VoiceCallPhase.connectingPeer => 'Connecting peer link.',
    VoiceCallPhase.outgoingRinging => 'Ringing.',
    VoiceCallPhase.incomingRinging => 'Incoming voice call.',
    VoiceCallPhase.connectingMedia => 'Connecting microphone audio.',
    VoiceCallPhase.ending => 'Closing microphone audio.',
    VoiceCallPhase.failed => _voiceCallFailureDetail(state),
    VoiceCallPhase.idle => '',
    VoiceCallPhase.active => 'Connected.',
  };
}

String _voiceCallFailureDetail(VoiceCallState state) {
  return switch (state.failureReason) {
    VoiceCallFailureReason.microphoneDenied =>
      'Microphone permission required.',
    VoiceCallFailureReason.remoteMicrophoneDenied =>
      'Peer microphone permission required.',
    VoiceCallFailureReason.peerBusy => 'Peer is busy.',
    VoiceCallFailureReason.fileTransferActive =>
      'Finish the active file transfer first.',
    VoiceCallFailureReason.rejected => 'Call declined.',
    VoiceCallFailureReason.networkLost =>
      'Network connection lost. Call ended.',
    VoiceCallFailureReason.signalingFailed => 'Call setup failed. Try again.',
    VoiceCallFailureReason.expired ||
    VoiceCallFailureReason.ringingTimeout => 'Call timed out.',
    VoiceCallFailureReason.mediaIceTimeout ||
    VoiceCallFailureReason.mediaNoRemoteAudio ||
    VoiceCallFailureReason.mediaConnectionFailed =>
      'Call media could not connect. Try again.',
    null => _sanitizeVoiceCallFailureDetail(state.detail),
  };
}

bool _voiceCallCanRetry(VoiceCallState state) {
  return switch (state.failureReason) {
    VoiceCallFailureReason.microphoneDenied ||
    VoiceCallFailureReason.peerBusy ||
    VoiceCallFailureReason.signalingFailed ||
    VoiceCallFailureReason.expired ||
    VoiceCallFailureReason.ringingTimeout ||
    VoiceCallFailureReason.mediaConnectionFailed ||
    VoiceCallFailureReason.mediaIceTimeout ||
    VoiceCallFailureReason.mediaNoRemoteAudio => true,
    VoiceCallFailureReason.remoteMicrophoneDenied ||
    VoiceCallFailureReason.fileTransferActive ||
    VoiceCallFailureReason.rejected ||
    VoiceCallFailureReason.networkLost ||
    null => false,
  };
}

String _sanitizeVoiceCallFailureDetail(String? detail) {
  final raw = detail?.trim();
  if (raw == null || raw.isEmpty) {
    return 'Call failed.';
  }
  const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
  var message = raw;
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      message = raw.substring(prefix.length).trim();
      break;
    }
  }
  final normalized = message.toLowerCase();
  if (normalized.contains('microphone') &&
      (normalized.contains('permission') || normalized.contains('denied'))) {
    return 'Microphone permission required.';
  }
  if (normalized.contains('peer is busy') ||
      normalized == 'busy.' ||
      normalized.contains('active voice call already exists') ||
      normalized.contains('activevoicepairs') ||
      normalized.contains('active voice pair')) {
    return 'Peer is busy.';
  }
  if (normalized.contains('active file transfer')) {
    return 'Finish the active file transfer first.';
  }
  if (normalized.contains('finish the call before') ||
      normalized == 'finish the call first.') {
    return 'Finish the call first.';
  }
  if (normalized == 'rejected.' ||
      normalized.contains('call declined') ||
      normalized.contains('call rejected')) {
    return 'Call declined.';
  }
  if (normalized.contains('network connection lost') ||
      normalized.contains('network lost') ||
      normalized.contains('internet connection') ||
      normalized.contains('network is unavailable') ||
      normalized.contains('network unavailable')) {
    return 'Network connection lost. Call ended.';
  }
  if (normalized.contains('timed out') ||
      normalized.contains('voice call expired') ||
      normalized.contains('call room expired')) {
    return 'Call timed out.';
  }
  if (normalized.contains('voice signaling') ||
      normalized.contains('firebase') ||
      normalized.contains('unknown voice call') ||
      normalized.contains('voice call already exists') ||
      normalized.contains('already ended') ||
      normalized.contains('permission-denied') ||
      normalized.contains('database')) {
    return 'Call setup failed. Try again.';
  }
  if (normalized.contains('ice timeout')) {
    return 'Call media could not connect. Try again.';
  }
  if (normalized.contains('no remote audio')) {
    return 'Call media could not connect. Try again.';
  }
  if (normalized.contains('rtcrtptransceiver') ||
      normalized.contains('setdirection') ||
      normalized.contains('setremotedescription') ||
      normalized.contains('peerconnectionsetremotedescription') ||
      normalized.contains('m-line') ||
      normalized.contains('peer connection changed while')) {
    return 'Call media could not connect. Try again.';
  }
  return message;
}

String _formatVoiceElapsed(Duration elapsed) {
  final seconds = elapsed.inSeconds.clamp(0, 86400).toInt();
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final remainingSeconds = seconds % 60;
  final secondsLabel = remainingSeconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$secondsLabel';
  }
  return '$minutes:$secondsLabel';
}
