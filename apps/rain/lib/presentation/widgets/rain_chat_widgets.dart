import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rain/application/runtime/media_device_settings.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';

const String _maleAvatarAsset = 'assets/gender avatar/man-avatar.svg';
const String _femaleAvatarAsset = 'assets/gender avatar/woman-avatar.svg';
const String _defaultMicrophoneMenuValue = '__rain_default_microphone__';

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
    this.onToggleDeafen,
    this.onSelectOutputRoute,
  });

  final VoiceCallState state;
  final String displayName;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
  final ValueChanged<VoiceCallOutputRoute>? onSelectOutputRoute;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = rainVoiceCallAccent(context, state);

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
                child: Icon(rainVoiceCallIcon(state), color: accent),
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
                          rainVoiceCallTitle(state, displayName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          rainVoiceCallDetail(state, now),
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
          final actions = RainCallControls(
            state: state,
            onAccept: onAccept,
            onReject: onReject,
            onHangUp: onHangUp,
            onRetry: onRetry,
            onToggleMute: onToggleMute,
            onToggleDeafen: onToggleDeafen,
            onSelectOutputRoute: onSelectOutputRoute,
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

class RainMicrophoneSelector extends StatelessWidget {
  const RainMicrophoneSelector({
    super.key,
    required this.state,
    required this.isBusy,
    required this.onRefresh,
    required this.onSelected,
  });

  final MicrophoneSelectionState state;
  final bool isBusy;
  final VoidCallback onRefresh;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedLabel = _selectedLabel();
    final warning = state.hasMissingSelection
        ? 'Selected microphone unavailable. Using default.'
        : null;
    final subtitle = warning ?? selectedLabel;

    return ListTile(
      leading: Icon(Icons.mic, color: warning == null ? null : scheme.error),
      title: const Text('Microphone'),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'Refresh microphones',
            onPressed: isBusy ? null : onRefresh,
            icon: isBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Choose microphone',
            enabled: !isBusy && state.devices.isNotEmpty,
            onSelected: (String value) =>
                onSelected(value == _defaultMicrophoneMenuValue ? null : value),
            itemBuilder: (BuildContext context) {
              return <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: _defaultMicrophoneMenuValue,
                  child: _RainMicrophoneMenuRow(
                    label: 'Default microphone',
                    selected: state.selectedDeviceId == null,
                  ),
                ),
                for (var index = 0; index < state.devices.length; index += 1)
                  PopupMenuItem<String>(
                    value: state.devices[index].deviceId,
                    child: _RainMicrophoneMenuRow(
                      label: state.devices[index].displayLabel(index),
                      selected:
                          state.selectedDeviceId ==
                          state.devices[index].deviceId,
                    ),
                  ),
              ];
            },
            icon: Icon(
              state.devices.isEmpty
                  ? Icons.mic_none
                  : Icons.arrow_drop_down_circle_outlined,
            ),
          ),
        ],
      ),
    );
  }

  String _selectedLabel() {
    final selected = state.selectedDevice;
    if (selected == null) {
      return state.devices.isEmpty
          ? 'No microphones found.'
          : 'Default microphone. Applies to next call.';
    }
    final index = state.devices.indexOf(selected);
    return '${selected.displayLabel(index)}. Applies to next call.';
  }
}

class _RainMicrophoneMenuRow extends StatelessWidget {
  const _RainMicrophoneMenuRow({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          size: 20,
          color: selected ? Theme.of(context).colorScheme.primary : null,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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
