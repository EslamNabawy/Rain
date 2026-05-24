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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final bubbleColor = _isOutgoing
        ? (isDark ? const Color(0xFF1D7E8E) : scheme.primaryContainer)
        : (isDark ? const Color(0xFF18262E) : scheme.surfaceContainerHighest);
    final textColor = _isOutgoing
        ? (isDark ? Colors.white : scheme.onPrimaryContainer)
        : scheme.onSurface;
    final muted = textColor.withValues(alpha: 0.72);
    final statusColor = _fileTransferStatusColor(transfer.state);
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
        child: Container(
          margin: EdgeInsets.only(
            top: startsCluster ? 8 : 2,
            bottom: endsCluster ? 8 : 1,
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
          decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.insert_drive_file_outlined, color: textColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          transfer.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w900,
                                height: 1.18,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatFileTransferSize(transfer.fileSize),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_isActive) ...<Widget>[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: transfer.fileSize <= 0 ? null : transfer.progress,
                    minHeight: 5,
                    color: statusColor,
                    backgroundColor: textColor.withValues(alpha: 0.14),
                  ),
                ),
              ],
              if (transfer.error != null && transfer.error!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  transfer.error!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    timeLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    _fileTransferStatusLabel(transferView),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              if (_hasActions) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
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
                    if (_isActive &&
                        transfer.state != FileTransferState.offered)
                      TextButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancel'),
                      ),
                    if (_canOpen)
                      FilledButton.tonalIcon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Open'),
                      ),
                    if (_canSave)
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
                ),
              ],
            ],
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
