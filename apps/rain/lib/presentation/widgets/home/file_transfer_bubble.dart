/// # file_transfer_bubble.dart
///
/// Chat bubble for file transfers showing progress, file metadata, and
/// accept/reject/cancel/open/save actions (part of home_screen).
///
/// **Key types:** _FileTransferBubble
///
/// **Depends on:** home_screen (part of), protocol_brain

part of '../../screens/home_screen.dart';

class _FileTransferBubble extends StatelessWidget {
  const _FileTransferBubble({
    required this.transferView,
    required this.timeLabel,
    required this.startsCluster,
    required this.endsCluster,
    required this.maxWidth,
    required this.onAccept,
    required this.onReject,
    required this.onCancel,
    required this.onOpen,
    required this.onSave,
    this.onRetry,
  });

  final FileTransferView transferView;
  final String timeLabel;
  final bool startsCluster;
  final bool endsCluster;
  final double maxWidth;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCancel;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback? onRetry;

  FileTransferRecord get transfer => transferView.record;
  bool get _isOutgoing => transfer.direction == FileTransferDirection.outgoing;
  bool get _isActive => transfer.isActive;
  bool get _canOpen =>
      transfer.state == FileTransferState.completed &&
      transfer.localPath != null &&
      transfer.localPath!.isNotEmpty;
  bool get _canSave =>
      _canOpen && transfer.direction == FileTransferDirection.incoming;

  /// An outgoing offer or any accepted transfer is waiting on the other side.
  bool get _isWaiting =>
      transfer.state == FileTransferState.accepted ||
      (transfer.state == FileTransferState.offered && _isOutgoing);

  bool get _showsProgress =>
      _isWaiting ||
      transfer.state == FileTransferState.sending ||
      transfer.state == FileTransferState.receiving;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final bubbleColor = _isOutgoing
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: isDark ? 0.30 : 0.18),
            scheme.surface,
          )
        : Color.alphaBlend(
            scheme.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.24 : 0.54,
            ),
            scheme.surface,
          );
    final textColor = _isOutgoing
        ? (isDark ? Colors.white : scheme.primary)
        : scheme.onSurface;
    final muted = textColor.withValues(alpha: 0.72);
    final statusColor = _fileTransferStatusColor(transfer.state);
    final borderColor = _isOutgoing
        ? scheme.primary.withValues(alpha: isDark ? 0.42 : 0.30)
        : (isDark
                  ? RainTextureTokens.cardBorderDark
                  : RainTextureTokens.cardBorderLight)
              .withValues(alpha: isDark ? 0.56 : 0.82);
    final tailRadius = const Radius.circular(6);
    final roundRadius = const Radius.circular(20);
    final radius = BorderRadius.only(
      topLeft: roundRadius,
      topRight: roundRadius,
      bottomLeft: _isOutgoing || !endsCluster ? roundRadius : tailRadius,
      bottomRight: _isOutgoing && endsCluster ? tailRadius : roundRadius,
    );

    return Align(
      alignment: _isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.only(
            top: startsCluster ? 8 : 2,
            bottom: endsCluster ? 8 : 1,
          ),
          child: Container(
            key: const ValueKey<String>('rain-file-transfer-surface'),
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: radius,
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _FileTransferHeader(
                  fileName: transfer.fileName,
                  fileSize: transfer.fileSize,
                  textColor: textColor,
                  mutedColor: muted,
                  completed: transfer.state == FileTransferState.completed,
                ),
                if (_showsProgress) ...<Widget>[
                  const SizedBox(height: 10),
                  _FileTransferProgress(
                    value: _isWaiting || transfer.fileSize <= 0
                        ? null
                        : transfer.progress,
                    color: statusColor,
                    trackColor: textColor.withValues(alpha: 0.14),
                  ),
                  if (_isWaiting) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      'Waiting for peer',
                      key: const ValueKey<String>(
                        'rain-file-transfer-waiting-label',
                      ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
                if (transfer.error != null && transfer.error!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    rainUserFacingError(transfer.error, callContext: false),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                _FileTransferMetaRow(
                  timeLabel: timeLabel,
                  statusLabel: _fileTransferStatusLabel(transferView),
                  mutedColor: muted,
                  statusColor: statusColor,
                ),
                if (_hasActions) ...<Widget>[
                  const SizedBox(height: 10),
                  _FileTransferActions(
                    transfer: transfer,
                    isActive: _isActive,
                    canOpen: _canOpen,
                    canSave: _canSave,
                    onAccept: onAccept,
                    onReject: onReject,
                    onCancel: onCancel,
                    onOpen: onOpen,
                    onSave: onSave,
                    onRetry: onRetry,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasActions {
    return (transfer.direction == FileTransferDirection.incoming &&
            transfer.state == FileTransferState.offered) ||
        (_isActive && transfer.state != FileTransferState.offered) ||
        _canOpen ||
        _canSave ||
        onRetry != null;
  }
}

class _FileTransferHeader extends StatelessWidget {
  const _FileTransferHeader({
    required this.fileName,
    required this.fileSize,
    required this.textColor,
    required this.mutedColor,
    required this.completed,
  });

  final String fileName;
  final int fileSize;
  final Color textColor;
  final Color mutedColor;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AnimatedSwitcher(
          duration: RainMotionPolicy.of(context).d(RainMotion.standard),
          child: completed
              ? Icon(
                  Icons.check_circle_rounded,
                  key: const ValueKey<String>('rain-file-transfer-check'),
                  color: RainColors.peerMint,
                )
              : Icon(
                  Icons.insert_drive_file_outlined,
                  key: const ValueKey<String>('rain-file-transfer-file'),
                  color: textColor,
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatFileTransferSize(fileSize),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: mutedColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FileTransferProgress extends StatelessWidget {
  const _FileTransferProgress({
    required this.value,
    required this.color,
    required this.trackColor,
  });

  /// Null renders the indeterminate bar.
  final double? value;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final target = value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: target == null
          ? LinearProgressIndicator(
              key: const ValueKey<String>('rain-file-transfer-progress'),
              minHeight: 5,
              color: color,
              backgroundColor: trackColor,
              value: RainMotionPolicy.of(context).reduced ? 0.0 : null,
            )
          : TweenAnimationBuilder<double>(
              tween: Tween<double>(end: target),
              duration: RainMotionPolicy.of(
                context,
              ).d(RainMotion.progressTween),
              curve: RainMotion.enter,
              builder: (BuildContext context, double animated, Widget? _) {
                return LinearProgressIndicator(
                  key: const ValueKey<String>('rain-file-transfer-progress'),
                  value: animated,
                  minHeight: 5,
                  color: color,
                  backgroundColor: trackColor,
                );
              },
            ),
    );
  }
}

class _FileTransferMetaRow extends StatelessWidget {
  const _FileTransferMetaRow({
    required this.timeLabel,
    required this.statusLabel,
    required this.mutedColor,
    required this.statusColor,
  });

  final String timeLabel;
  final String statusLabel;
  final Color mutedColor;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          timeLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: mutedColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        Text(
          statusLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: statusColor,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _FileTransferActions extends StatelessWidget {
  const _FileTransferActions({
    required this.transfer,
    required this.isActive,
    required this.canOpen,
    required this.canSave,
    required this.onAccept,
    required this.onReject,
    required this.onCancel,
    required this.onOpen,
    required this.onSave,
    required this.onRetry,
  });

  final FileTransferRecord transfer;
  final bool isActive;
  final bool canOpen;
  final bool canSave;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCancel;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        if (transfer.direction == FileTransferDirection.incoming &&
            transfer.state == FileTransferState.offered) ...[
          FilledButton.tonalIcon(
            onPressed: onAccept,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Accept'),
          ),
          TextButton.icon(
            onPressed: onReject,
            icon: const Icon(Icons.close_rounded),
            label: const Text('Reject'),
          ),
        ],
        if (isActive && transfer.state != FileTransferState.offered)
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            label: const Text('Cancel'),
          ),
        if (canOpen)
          FilledButton.tonalIcon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open'),
          ),
        if (canSave)
          TextButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Save'),
          ),
        if (onRetry != null)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
      ],
    );
  }
}

String _fileTransferStatusLabel(FileTransferView transferView) {
  final transfer = transferView.record;
  final progress = transfer.fileSize <= 0
      ? ''
      : ' ${(transfer.progress * 100).clamp(0, 100).toStringAsFixed(0)}%';
  final speed = transferView.speedBytesPerSecond == null
      ? ''
      : ' • ${formatFileTransferSpeed(transferView.speedBytesPerSecond!)}';
  return switch (transfer.state) {
    FileTransferState.offered =>
      transfer.direction == FileTransferDirection.incoming
          ? 'Incoming'
          : 'Offered',
    FileTransferState.accepted => 'Accepted',
    FileTransferState.sending => 'Sending$progress$speed',
    FileTransferState.receiving => 'Receiving$progress$speed',
    FileTransferState.completed => 'Completed',
    FileTransferState.canceled => 'Canceled',
    FileTransferState.failed => 'Failed',
    FileTransferState.rejected => 'Rejected',
  };
}

Color _fileTransferStatusColor(FileTransferState state) {
  return switch (state) {
    FileTransferState.offered ||
    FileTransferState.accepted => RainColors.warning,
    FileTransferState.sending ||
    FileTransferState.receiving => RainColors.mistCyan,
    FileTransferState.completed => RainColors.peerMint,
    FileTransferState.canceled ||
    FileTransferState.failed ||
    FileTransferState.rejected => RainColors.errorCoral,
  };
}

/// Builds the private transfer bubble for widget tests.
@visibleForTesting
Widget buildFileTransferBubbleForTest({
  required FileTransferView transferView,
  String timeLabel = '12:00',
  VoidCallback? onRetry,
}) {
  void noop() {}
  return _FileTransferBubble(
    transferView: transferView,
    timeLabel: timeLabel,
    startsCluster: true,
    endsCluster: true,
    maxWidth: 320,
    onAccept: noop,
    onReject: noop,
    onCancel: noop,
    onOpen: noop,
    onSave: noop,
    onRetry: onRetry,
  );
}
