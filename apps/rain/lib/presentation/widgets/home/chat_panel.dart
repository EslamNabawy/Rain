part of '../../screens/home_screen.dart';

class _ChatPanel extends ConsumerStatefulWidget {
  const _ChatPanel({required this.peerId, this.isCompact = false, this.onBack});

  final String peerId;
  final bool isCompact;
  final VoidCallback? onBack;

  @override
  ConsumerState<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<_ChatPanel> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();
  bool _isSending = false;
  bool _isPickingFile = false;
  bool _isConnecting = false;
  bool _showJumpToLatest = false;

  @override
  void initState() {
    super.initState();
    _messageScrollController.addListener(_handleMessageScroll);
  }

  @override
  void didUpdateWidget(covariant _ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peerId != widget.peerId) {
      _composerController.clear();
      _setJumpToLatestVisible(false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest());
    }
  }

  @override
  void dispose() {
    _messageScrollController.removeListener(_handleMessageScroll);
    _messageScrollController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final runtime = ref.watch(runtimeControllerProvider).value;
    final friend = _currentFriend(friends);
    final canChat = friend?.state == FriendState.friend;
    final isPeerOnline = canChat ? friend?.isOnline ?? false : false;
    final connection = ref.watch(connectionsProvider).peer(widget.peerId);
    final diagnostics = ConnectionDiagnostics.fromConnection(
      canChat: canChat,
      isPeerOnline: isPeerOnline,
      connection: connection,
      coordinator: runtime?.connectionCoordinatorSnapshotFor(widget.peerId),
    );
    final connectionStatus = _connectionStatusForDiagnostics(diagnostics);
    final canConnectNow =
        runtime != null &&
        canChat &&
        !connectionStatus.isBusy &&
        !connectionStatus.isConnected;
    final canDisconnectNow =
        runtime != null && canChat && connectionStatus.canDisconnect;
    final messages = ref.watch(messagesProvider(widget.peerId));
    final transfers = ref.watch(fileTransferViewsProvider(widget.peerId));
    ref.listen<AsyncValue<List<StoredMessage>>>(
      messagesProvider(widget.peerId),
      _handleMessageSound,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isNarrow = constraints.maxWidth < 560;
        final horizontalPadding = widget.isCompact ? 12.0 : 24.0;
        final headerTopPadding = widget.isCompact ? 8.0 : 24.0;
        final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

        return Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                headerTopPadding,
                horizontalPadding,
                widget.isCompact ? 8 : 16,
              ),
              child: _buildCommandHeader(
                friend: friend,
                canChat: canChat,
                diagnostics: diagnostics,
                connectionStatus: connectionStatus,
                canConnectNow: canConnectNow,
                canDisconnectNow: canDisconnectNow,
              ),
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: friend == null
                        ? AppStateMessage(
                            icon: Icons.person_off_outlined,
                            title: 'Conversation unavailable',
                            message:
                                'This relationship is no longer available in your friends list.',
                          )
                        : canChat
                        ? _buildMessages(
                            messages,
                            transfers,
                            constraints,
                            horizontalPadding,
                            isNarrow,
                          )
                        : _buildRelationshipState(friend, horizontalPadding),
                  ),
                  if (canChat && _showJumpToLatest)
                    Positioned(
                      right: horizontalPadding,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'jump-to-latest-${widget.peerId}',
                        tooltip: 'Jump to latest message',
                        onPressed: _jumpToLatest,
                        child: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ),
                ],
              ),
            ),
            if (canChat)
              AnimatedPadding(
                duration: RainMotion.quick,
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  keyboardOpen ? 10 : (widget.isCompact ? 16 : 24),
                ),
                child: ChatComposer(
                  controller: _composerController,
                  enabled: runtime != null && canChat,
                  isSending: _isSending,
                  isAttaching: _isPickingFile,
                  maxLength: InputValidator.messageMaxLength,
                  onSend: () => _sendMessage(runtime),
                  onAttach: () => _pickAndSendFile(runtime, connectionStatus),
                ),
              ),
          ],
        );
      },
    );
  }

  void _handleMessageScroll() {
    if (!_messageScrollController.hasClients) {
      return;
    }
    _setJumpToLatestVisible(_messageScrollController.offset > 220);
  }

  void _setJumpToLatestVisible(bool visible) {
    if (_showJumpToLatest == visible || !mounted) {
      return;
    }
    setState(() => _showJumpToLatest = visible);
  }

  void _jumpToLatest() {
    if (!_messageScrollController.hasClients) {
      return;
    }
    _messageScrollController.animateTo(
      0,
      duration: RainMotion.standard,
      curve: Curves.easeOutCubic,
    );
  }

  void _handleMessageSound(
    AsyncValue<List<StoredMessage>>? previous,
    AsyncValue<List<StoredMessage>> next,
  ) {
    final previousMessages = previous?.value;
    final nextMessages = next.value;
    if (previousMessages == null || nextMessages == null) {
      return;
    }

    final previousLatestIncoming = _latestIncomingMessageId(previousMessages);
    final nextLatestIncoming = _latestIncomingMessageId(nextMessages);
    if (nextLatestIncoming != null &&
        nextLatestIncoming != previousLatestIncoming &&
        nextMessages.length >= previousMessages.length) {
      _playSound(RainSoundEffect.receive);
    }
  }

  String? _latestIncomingMessageId(List<StoredMessage> messages) {
    for (final message in messages.reversed) {
      if (!message.isOutgoing) {
        return message.id;
      }
    }
    return null;
  }

  void _playSound(RainSoundEffect effect) {
    unawaited(ref.read(soundEffectsProvider).play(effect));
  }

  Widget _buildCommandHeader({
    required FriendRecord? friend,
    required bool canChat,
    required ConnectionDiagnostics diagnostics,
    required _ConnectionStatus connectionStatus,
    required bool canConnectNow,
    required bool canDisconnectNow,
  }) {
    final displayName = friend?.displayName ?? widget.peerId;
    final scheme = Theme.of(context).colorScheme;
    final handle = '@${friend?.username ?? widget.peerId}';
    void openLinkDialog() {
      _showLinkCommandDialog(
        diagnostics: diagnostics,
        connectionStatus: connectionStatus,
        canConnectNow: canConnectNow,
        canDisconnectNow: canDisconnectNow,
      );
    }

    if (widget.isCompact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (widget.onBack != null)
                IconButton(
                  tooltip: 'Back',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
              RainAvatar(
                name: displayName,
                size: 36,
                statusColor: canChat ? connectionStatus.color : null,
                gender: friend?.gender?.name,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (friend != null)
                IconButton(
                  tooltip: 'Open peer profile',
                  onPressed: () => AppRoutes.openFriendProfile(context, friend),
                  icon: const Icon(Icons.person_outline),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _MobileLinkStatusBar(
            status: connectionStatus,
            diagnostics: diagnostics,
            canConnectNow: canConnectNow,
            canDisconnectNow: canDisconnectNow,
            onConnect: _connectToPeer,
            onDisconnect: _disconnectPeer,
            onTap: openLinkDialog,
            enabled: canChat,
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        if (widget.onBack != null)
          IconButton(
            tooltip: widget.isCompact ? 'Back' : 'Back to control deck',
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
          ),
        if (!widget.isCompact) ...<Widget>[
          RainAvatar(
            name: displayName,
            size: 42,
            statusColor: canChat ? connectionStatus.color : null,
            gender: friend?.gender?.name,
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.isCompact ? handle : displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (widget.isCompact
                            ? Theme.of(context).textTheme.titleLarge
                            : Theme.of(context).textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (!widget.isCompact) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _MobileLinkStatusBar(
                status: connectionStatus,
                diagnostics: diagnostics,
                canConnectNow: canConnectNow,
                canDisconnectNow: canDisconnectNow,
                onConnect: _connectToPeer,
                onDisconnect: _disconnectPeer,
                onTap: openLinkDialog,
                enabled: canChat,
              ),
            ),
          ),
        ),
        if (!widget.isCompact && friend != null) ...<Widget>[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Open peer profile',
            onPressed: () => AppRoutes.openFriendProfile(context, friend),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ],
    );
  }

  Future<void> _showLinkCommandDialog({
    required ConnectionDiagnostics diagnostics,
    required _ConnectionStatus connectionStatus,
    required bool canConnectNow,
    required bool canDisconnectNow,
  }) {
    final route = diagnostics.route;
    final updatedAt = diagnostics.updatedAt;
    final primaryStats = <_LinkStat>[
      _LinkStat(label: 'Phase', value: _phaseLabel(diagnostics.phase)),
      _LinkStat(label: 'Route', value: diagnostics.label),
      _LinkStat(
        label: 'Local',
        value: _candidateLabel(route.localCandidateType),
      ),
      _LinkStat(
        label: 'Remote',
        value: _candidateLabel(route.remoteCandidateType),
      ),
      _LinkStat(label: 'IP', value: _routeAddressFamilyLabel(route)),
      _LinkStat(label: 'Next', value: _nextRetryLabel(diagnostics.nextRetryAt)),
    ];
    final advancedStats = <_LinkStat>[
      _LinkStat(
        label: 'Pair',
        value: diagnostics.selectedCandidatePairId ?? 'Unknown',
      ),
      _LinkStat(label: 'Protocol', value: _protocolLabel(route)),
      _LinkStat(label: 'RTT', value: _rttLabel(route.rtt)),
      _LinkStat(label: 'Bitrate', value: _bitrateLabel(route.bitrate)),
      _LinkStat(label: 'Room', value: diagnostics.roomId ?? 'Not opened'),
      _LinkStat(
        label: 'Role',
        value: diagnostics.isOfferOwner == null
            ? 'None'
            : diagnostics.isOfferOwner!
            ? 'Offer'
            : 'Answer',
      ),
      _LinkStat(label: 'Retries', value: '${diagnostics.retryAttempt}'),
      _LinkStat(
        label: 'Backoff',
        value: diagnostics.connectionRetryAttempt == 0
            ? '0'
            : '${diagnostics.connectionRetryAttempt}',
      ),
      _LinkStat(
        label: 'Passive',
        value:
            '${diagnostics.passiveListenerCount}/${diagnostics.passiveListenerLimit}',
      ),
      _LinkStat(
        label: 'Net Retry',
        value:
            '${diagnostics.networkRecoveryRuns}/${diagnostics.networkRecoveryRequests}',
      ),
      _LinkStat(
        label: 'Inbound',
        value: diagnostics.lastInboundOfferPeer ?? 'None',
      ),
      _LinkStat(
        label: 'Rejected',
        value: diagnostics.lastRejectedOfferPeer ?? 'None',
      ),
      _LinkStat(
        label: 'Updated',
        value: updatedAt == null ? 'Never' : _formatMessageTime(updatedAt),
      ),
    ];
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        final size = MediaQuery.sizeOf(dialogContext);
        final maxDialogHeight = size.height * (size.width < 600 ? 0.82 : 0.70);

        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          title: Row(
            children: <Widget>[
              Icon(connectionStatus.icon, color: connectionStatus.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Live Link',
                  style: Theme.of(
                    dialogContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: maxDialogHeight,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  RainMiniStatusChip(
                    label: connectionStatus.label,
                    color: connectionStatus.color,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    connectionStatus.detail,
                    style: Theme.of(dialogContext).textTheme.bodyMedium
                        ?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.72),
                        ),
                  ),
                  const SizedBox(height: 14),
                  _LinkStatGrid(stats: primaryStats),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: const Text('Advanced diagnostics'),
                    children: <Widget>[_LinkStatGrid(stats: advancedStats)],
                  ),
                  if (diagnostics.lastRejectedOfferReason != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Text(
                      diagnostics.lastRejectedOfferReason!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                  if (diagnostics.lastError != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Text(
                      diagnostics.lastError!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            OutlinedButton.icon(
              onPressed: canDisconnectNow
                  ? () {
                      Navigator.of(dialogContext).pop();
                      _disconnectPeer();
                    }
                  : null,
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
            ),
            FilledButton.icon(
              onPressed: canConnectNow
                  ? () {
                      Navigator.of(dialogContext).pop();
                      _connectToPeer();
                    }
                  : null,
              icon: Icon(
                connectionStatus.label == 'Failed'
                    ? Icons.refresh
                    : Icons.hub_outlined,
              ),
              label: Text(
                connectionStatus.label == 'Failed' ? 'Retry' : 'Connect',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMessages(
    AsyncValue<List<StoredMessage>> messages,
    AsyncValue<List<FileTransferView>> transfers,
    BoxConstraints constraints,
    double horizontalPadding,
    bool isNarrow,
  ) {
    return RefreshIndicator(
      onRefresh: _refreshChat,
      child: messages.when(
        data: (List<StoredMessage> items) {
          final transferByMessageId = <String, FileTransferView>{
            for (final transferView
                in transfers.value ?? const <FileTransferView>[])
              transferView.record.messageId: transferView,
          };
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                80,
                horizontalPadding,
                24,
              ),
              children: const <Widget>[
                AppStateMessage(
                  icon: Icons.water_drop_outlined,
                  title: 'No messages yet',
                  message:
                      'Messages will appear here once the conversation starts.',
                ),
              ],
            );
          }

          return ListView.builder(
            controller: _messageScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            scrollCacheExtent: const ScrollCacheExtent.pixels(900),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              8,
              horizontalPadding,
              14,
            ),
            reverse: true,
            itemCount: items.length,
            itemBuilder: (BuildContext context, int index) {
              final messageIndex = items.length - index - 1;
              final message = items[messageIndex];
              final maxBubbleWidth = isNarrow
                  ? constraints.maxWidth * 0.84
                  : 440.0;
              final startsCluster = _startsMessageCluster(items, messageIndex);
              final endsCluster = _endsMessageCluster(items, messageIndex);
              final showDayDivider = _startsMessageDay(items, messageIndex);
              final deliveryLabel = message.isOutgoing
                  ? _deliveryLabel(message.status)
                  : null;
              final deliveryColor = message.isOutgoing
                  ? _deliveryColor(message.status)
                  : null;
              final transferView = message.type == MessageType.file
                  ? transferByMessageId[message.id]
                  : null;

              return Column(
                key: ValueKey<String>('message-row-${message.id}'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (showDayDivider)
                    RainMessageDayDivider(
                      label: _formatMessageDay(message.sentAt),
                    ),
                  if (transferView != null)
                    Builder(
                      builder: (BuildContext context) {
                        final transfer = transferView.record;
                        return _FileTransferBubble(
                          transferView: transferView,
                          timeLabel: _formatMessageTime(message.sentAt),
                          startsCluster: startsCluster,
                          endsCluster: endsCluster,
                          maxWidth: maxBubbleWidth,
                          onAccept: () =>
                              unawaited(_acceptFileTransfer(transfer)),
                          onReject: () =>
                              unawaited(_rejectFileTransfer(transfer)),
                          onCancel: () =>
                              unawaited(_cancelFileTransfer(transfer)),
                          onOpen: () => unawaited(_openFileTransfer(transfer)),
                          onSave: () => unawaited(_saveFileTransfer(transfer)),
                          onRetry: _canRetryFileTransfer(transfer)
                              ? () => unawaited(_retryFileTransfer(transfer))
                              : null,
                        );
                      },
                    )
                  else
                    RainMessageBubble(
                      text: message.content,
                      timeLabel: _formatMessageTime(message.sentAt),
                      isOutgoing: message.isOutgoing,
                      startsCluster: startsCluster,
                      endsCluster: endsCluster,
                      maxWidth: maxBubbleWidth,
                      deliveryLabel: deliveryLabel,
                      deliveryColor: deliveryColor,
                      onRetry:
                          message.isOutgoing &&
                              message.status == MessageStatus.failed
                          ? () => unawaited(_resendMessage(message))
                          : null,
                      onOpenActions: () =>
                          unawaited(_showMessageActions(message)),
                    ),
                ],
              );
            },
          );
        },
        error: (Object error, StackTrace stackTrace) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            80,
            horizontalPadding,
            24,
          ),
          children: <Widget>[Center(child: Text(error.toString()))],
        ),
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const <Widget>[
            SizedBox(height: 180),
            Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshChat() async {
    final networkError = _networkActionError();
    if (networkError != null) {
      _showErrorSnack(networkError);
      return;
    }
    await ref.read(friendsProvider.notifier).refreshPeer(widget.peerId);
    await ref.read(messagesProvider(widget.peerId).notifier).markRead();
  }

  bool _startsMessageCluster(List<StoredMessage> items, int index) {
    if (index == 0) {
      return true;
    }
    return !_isClusterNeighbor(items[index - 1], items[index]);
  }

  bool _endsMessageCluster(List<StoredMessage> items, int index) {
    if (index == items.length - 1) {
      return true;
    }
    return !_isClusterNeighbor(items[index], items[index + 1]);
  }

  bool _isClusterNeighbor(StoredMessage first, StoredMessage second) {
    if (first.isOutgoing != second.isOutgoing) {
      return false;
    }
    if (!_sameMessageDay(first.sentAt, second.sentAt)) {
      return false;
    }
    final gap = (second.sentAt - first.sentAt).abs();
    return gap <= const Duration(minutes: 3).inMilliseconds;
  }

  bool _startsMessageDay(List<StoredMessage> items, int index) {
    if (index == 0) {
      return true;
    }
    return !_sameMessageDay(items[index - 1].sentAt, items[index].sentAt);
  }

  bool _sameMessageDay(int firstMs, int secondMs) {
    final first = DateTime.fromMillisecondsSinceEpoch(firstMs);
    final second = DateTime.fromMillisecondsSinceEpoch(secondMs);
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  String _deliveryLabel(MessageStatus status) {
    return switch (status) {
      MessageStatus.queued => 'Queued',
      MessageStatus.sending => 'Sending',
      MessageStatus.sent => 'Sent',
      MessageStatus.pendingAck => 'Ack',
      MessageStatus.delivered => 'Delivered',
      MessageStatus.failed => 'Failed',
    };
  }

  Color _deliveryColor(MessageStatus status) {
    return switch (status) {
      MessageStatus.queued || MessageStatus.sending => const Color(0xFFFBBF24),
      MessageStatus.sent || MessageStatus.pendingAck => const Color(0xFF7DD3FC),
      MessageStatus.delivered => const Color(0xFF2DD4A3),
      MessageStatus.failed => const Color(0xFFFF6B6B),
    };
  }

  Future<void> _showMessageActions(StoredMessage message) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final isFailedOutgoing =
            message.isOutgoing && message.status == MessageStatus.failed;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      message.isOutgoing
                          ? Icons.north_east_rounded
                          : Icons.south_west_rounded,
                      color: message.isOutgoing
                          ? _deliveryColor(message.status)
                          : scheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            message.isOutgoing
                                ? 'Outgoing message'
                                : 'Incoming message',
                            style: Theme.of(sheetContext).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            '${_formatMessageDay(message.sentAt)} at ${_formatMessageTime(message.sentAt)}',
                            style: Theme.of(sheetContext).textTheme.bodySmall
                                ?.copyWith(
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.62,
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (message.isOutgoing)
                      RainMiniStatusChip(
                        label: _deliveryLabel(message.status),
                        color: _deliveryColor(message.status),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 128),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.50,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      message.content,
                      style: Theme.of(sheetContext).textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_copyMessage(message.content));
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy'),
                    ),
                    if (isFailedOutgoing)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          unawaited(_resendMessage(message));
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry send'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyMessage(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Message copied.')));
  }

  Future<void> _resendMessage(StoredMessage message) async {
    try {
      await ref
          .read(messagesProvider(widget.peerId).notifier)
          .resend(message.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_formatUiError(error)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _pickAndSendFile(
    RainRuntimeController? runtime,
    _ConnectionStatus connectionStatus,
  ) async {
    if (_isPickingFile) {
      return;
    }
    final networkError = _networkActionError();
    if (networkError != null) {
      _playSound(RainSoundEffect.error);
      _showErrorSnack(networkError);
      return;
    }
    if (runtime == null || !connectionStatus.isConnected) {
      _playSound(RainSoundEffect.error);
      _showErrorSnack('Connect first.');
      return;
    }

    setState(() => _isPickingFile = true);
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        withData: false,
        withReadStream: true,
      );
      final picked = result == null || result.files.isEmpty
          ? null
          : result.files.first;
      if (picked == null) {
        return;
      }
      if (picked.size > maxFileTransferBytes) {
        throw StateError(
          'Files are limited to ${formatFileTransferSize(maxFileTransferBytes)}.',
        );
      }
      final localPath = picked.path;
      final file = localPath == null ? null : File(localPath);
      await ref
          .read(messagesProvider(widget.peerId).notifier)
          .sendFile(
            fileName: picked.name,
            fileSize: picked.size,
            localPath: localPath,
            openRead: () {
              if (file != null) {
                return file.openRead();
              }
              final stream = picked.readStream;
              if (stream == null) {
                throw StateError('Could not read the selected file.');
              }
              return stream;
            },
          );
      _playSound(RainSoundEffect.send);
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest());
    } catch (error) {
      _playSound(RainSoundEffect.error);
      _showErrorSnack(_formatUiError(error));
    } finally {
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }
  }

  Future<void> _acceptFileTransfer(FileTransferRecord transfer) async {
    await _runFileTransferAction(
      () => ref
          .read(fileTransfersProvider(widget.peerId).notifier)
          .accept(transfer.id),
    );
  }

  Future<void> _rejectFileTransfer(FileTransferRecord transfer) async {
    await _runFileTransferAction(
      () => ref
          .read(fileTransfersProvider(widget.peerId).notifier)
          .reject(transfer.id),
    );
  }

  Future<void> _cancelFileTransfer(FileTransferRecord transfer) async {
    await _runFileTransferAction(
      () => ref
          .read(fileTransfersProvider(widget.peerId).notifier)
          .cancel(transfer.id),
    );
  }

  Future<void> _retryFileTransfer(FileTransferRecord transfer) async {
    await _runFileTransferAction(
      () => ref
          .read(fileTransfersProvider(widget.peerId).notifier)
          .retry(transfer),
      successEffect: RainSoundEffect.send,
    );
  }

  Future<void> _openFileTransfer(FileTransferRecord transfer) async {
    final localPath = transfer.localPath;
    if (localPath == null || localPath.isEmpty) {
      _showErrorSnack('Received file is not available.');
      return;
    }
    final file = File(localPath);
    if (!await file.exists()) {
      _showErrorSnack('Received file is not available.');
      return;
    }
    final result = await OpenFilex.open(localPath);
    if (result.type != ResultType.done) {
      _showErrorSnack(result.message);
    }
  }

  Future<void> _saveFileTransfer(FileTransferRecord transfer) async {
    try {
      final result = await ref
          .read(receivedFileExportServiceProvider)
          .saveReceivedFile(transfer);
      if (result.saved) {
        _playSound(RainSoundEffect.action);
        _showInfoSnack('File saved.');
      }
    } catch (error) {
      _playSound(RainSoundEffect.error);
      _showErrorSnack(_formatUiError(error));
    }
  }

  bool _canRetryFileTransfer(FileTransferRecord transfer) {
    return transfer.direction == FileTransferDirection.outgoing &&
        (transfer.state == FileTransferState.failed ||
            transfer.state == FileTransferState.canceled) &&
        transfer.localPath != null &&
        transfer.localPath!.isNotEmpty;
  }

  Future<void> _runFileTransferAction(
    Future<void> Function() action, {
    RainSoundEffect successEffect = RainSoundEffect.action,
  }) async {
    try {
      await action();
      _playSound(successEffect);
    } catch (error) {
      _playSound(RainSoundEffect.error);
      _showErrorSnack(_formatUiError(error));
    }
  }

  void _showErrorSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showInfoSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  FriendRecord? _currentFriend(AsyncValue<List<FriendRecord>> friends) {
    final items = friends.value;
    if (items == null) {
      return null;
    }
    for (final friend in items) {
      if (friend.username == widget.peerId) {
        return friend;
      }
    }
    return null;
  }

  Widget _buildRelationshipState(
    FriendRecord friend,
    double horizontalPadding,
  ) {
    final icon = switch (friend.state) {
      FriendState.pendingIncoming => Icons.mark_email_unread_outlined,
      FriendState.pendingOutgoing => Icons.hourglass_top_rounded,
      FriendState.blocked => Icons.block_outlined,
      FriendState.blockedByPeer => Icons.block_outlined,
      FriendState.friend => Icons.wifi_tethering,
    };
    final title = switch (friend.state) {
      FriendState.pendingIncoming => 'Incoming friend request',
      FriendState.pendingOutgoing => 'Request pending',
      FriendState.blocked => 'User blocked',
      FriendState.blockedByPeer => 'Blocked by peer',
      FriendState.friend => 'Ready to chat',
    };
    final message = switch (friend.state) {
      FriendState.pendingIncoming =>
        'Accept @${friend.username} before starting a peer-to-peer chat.',
      FriendState.pendingOutgoing =>
        'You can connect after @${friend.username} accepts your friend request.',
      FriendState.blocked =>
        'Unblock @${friend.username} before connecting or sending messages.',
      FriendState.blockedByPeer =>
        '@${friend.username} blocked you. You cannot connect or send messages right now.',
      FriendState.friend => 'Rain is ready to connect to @${friend.username}.',
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        24,
        horizontalPadding,
        24,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AppStateMessage(icon: icon, title: title, message: message),
          const SizedBox(height: 16),
          if (friend.state == FriendState.pendingIncoming) ...<Widget>[
            FilledButton.icon(
              onPressed: () => _runRelationshipAction(
                () =>
                    ref.read(friendsProvider.notifier).accept(friend.username),
              ),
              icon: const Icon(Icons.check),
              label: const Text('Accept request'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _runRelationshipAction(
                () =>
                    ref.read(friendsProvider.notifier).reject(friend.username),
              ),
              icon: const Icon(Icons.close),
              label: const Text('Reject request'),
            ),
          ],
          if (friend.state == FriendState.pendingOutgoing)
            OutlinedButton.icon(
              onPressed: () => _runRelationshipAction(
                () =>
                    ref.read(friendsProvider.notifier).reject(friend.username),
              ),
              icon: const Icon(Icons.cancel),
              label: const Text('Cancel request'),
            ),
          if (friend.state == FriendState.blocked)
            FilledButton.icon(
              onPressed: () => _runRelationshipAction(
                () =>
                    ref.read(friendsProvider.notifier).unblock(friend.username),
              ),
              icon: const Icon(Icons.check),
              label: const Text('Unblock'),
            ),
        ],
      ),
    );
  }

  Future<void> _runRelationshipAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_formatUiError(error)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  String _formatMessageTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);

    final time = TimeOfDay.fromDateTime(date).format(context);

    if (messageDay == today) {
      return time;
    } else if (messageDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday $time';
    } else if (now.difference(messageDay).inDays < 7) {
      return '${_weekdayName(date.weekday)} $time';
    } else {
      return '${date.day}/${date.month}/${date.year} $time';
    }
  }

  String _formatMessageDay(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);

    if (messageDay == today) {
      return 'Today';
    }
    if (messageDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    if (now.difference(messageDay).inDays < 7) {
      return _weekdayName(date.weekday);
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  String _weekdayName(int weekday) {
    return switch (weekday) {
      1 => 'Mon',
      2 => 'Tue',
      3 => 'Wed',
      4 => 'Thu',
      5 => 'Fri',
      6 => 'Sat',
      7 => 'Sun',
      _ => '',
    };
  }

  Future<void> _sendMessage(RainRuntimeController? runtime) async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _isSending) {
      return;
    }
    final networkError = _networkActionError();
    if (networkError != null) {
      _playSound(RainSoundEffect.error);
      _showErrorSnack(networkError);
      return;
    }
    if (runtime == null) {
      _playSound(RainSoundEffect.error);
      _showErrorSnack('Peer connection is unavailable right now.');
      return;
    }

    setState(() => _isSending = true);
    _composerController.clear();
    try {
      await runtime.sendMessage(widget.peerId, text);
      _playSound(RainSoundEffect.send);
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest());
    } catch (error) {
      _playSound(RainSoundEffect.error);
      if (mounted) {
        _composerController.text = text;
        _composerController.selection = TextSelection.collapsed(
          offset: _composerController.text.length,
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_formatUiError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _connectToPeer() async {
    if (_isConnecting) return;
    final networkError = _networkActionError();
    if (networkError != null) {
      _playSound(RainSoundEffect.error);
      _showErrorSnack(networkError);
      return;
    }
    setState(() => _isConnecting = true);
    try {
      await ref
          .read(connectionsProvider.notifier)
          .connect(widget.peerId, waitForConnected: true, manualRetry: true);
      _playSound(RainSoundEffect.action);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to @${widget.peerId}.')),
        );
      }
    } catch (error) {
      _playSound(RainSoundEffect.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_formatUiError(error)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _disconnectPeer() async {
    try {
      await ref.read(connectionsProvider.notifier).disconnect(widget.peerId);
      _playSound(RainSoundEffect.action);
    } catch (error) {
      _playSound(RainSoundEffect.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_formatUiError(error)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String? _networkActionError() {
    final status = ref.read(networkStatusProvider).value;
    return status != null && status.blocksNetworkActions
        ? status.actionErrorMessage
        : null;
  }
}
