import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import '../navigation/app_routes.dart';
import '../providers/app_providers.dart';
import '../providers/app_state.dart';
import '../services/rain_runtime_controller.dart';
import '../services/sound_effects_service.dart';
import '../theme/rain_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/chat_composer.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/rain_command_widgets.dart';

String _formatUiError(Object error) {
  final raw = error.toString().trim();
  const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length).trim();
    }
  }
  return raw;
}

class _ConnectionStatus {
  const _ConnectionStatus({
    required this.label,
    required this.icon,
    required this.color,
    required this.detail,
    this.isBusy = false,
    this.isConnected = false,
    this.canDisconnect = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String detail;
  final bool isBusy;
  final bool isConnected;
  final bool canDisconnect;
}

_ConnectionStatus _connectionStatusFor({
  required bool canChat,
  required bool isPeerOnline,
  required PeerConnectionView connection,
}) {
  if (!canChat) {
    return const _ConnectionStatus(
      label: 'Unavailable',
      icon: Icons.lock_outline,
      color: Color(0xFF52646D),
      detail: 'Only accepted friends can chat.',
    );
  }

  if (connection.disconnecting) {
    return const _ConnectionStatus(
      label: 'Disconnecting',
      icon: Icons.link_off,
      color: Color(0xFFFBBF24),
      detail: 'Closing peer session.',
      isBusy: true,
      canDisconnect: true,
    );
  }

  final session = connection.session;
  switch (session?.state) {
    case SessionState.connected:
      return _ConnectionStatus(
        label: 'Linked',
        icon: Icons.hub_outlined,
        color: const Color(0xFF2DD4A3),
        detail: connection.localDetail ?? 'Encrypted peer lane is open.',
        isConnected: true,
        canDisconnect: true,
      );
    case SessionState.failed:
      return _ConnectionStatus(
        label: 'Failed',
        icon: Icons.error_outline,
        color: const Color(0xFFFF6B6B),
        detail:
            connection.error?.toString() ??
            connection.localDetail ??
            session!.detail,
      );
    case SessionState.reconnecting:
      return _ConnectionStatus(
        label: 'Recovering',
        icon: Icons.sync,
        color: const Color(0xFFFBBF24),
        detail: connection.localDetail ?? session!.detail,
        isBusy: true,
        canDisconnect: true,
      );
    case SessionState.connecting:
      return _ConnectionStatus(
        label: _phaseLabel(session!.phase),
        icon: Icons.sync,
        color: const Color(0xFFFBBF24),
        detail: connection.localDetail ?? session.detail,
        isBusy: true,
        canDisconnect: true,
      );
    case null:
      break;
  }

  if (connection.actionBusy) {
    return _ConnectionStatus(
      label: 'Connecting',
      icon: Icons.sync,
      color: const Color(0xFFFBBF24),
      detail: connection.localDetail ?? 'Starting peer connection.',
      isBusy: true,
    );
  }
  if (connection.error != null) {
    return _ConnectionStatus(
      label: 'Failed',
      icon: Icons.error_outline,
      color: const Color(0xFFFF6B6B),
      detail: _formatUiError(connection.error!),
    );
  }
  if (!isPeerOnline) {
    return const _ConnectionStatus(
      label: 'Offline',
      icon: Icons.cloud_off_outlined,
      color: Color(0xFF52646D),
      detail: 'Peer is offline. Keep both apps open.',
    );
  }
  return const _ConnectionStatus(
    label: 'Ready',
    icon: Icons.wifi_tethering,
    color: Color(0xFF7DD3FC),
    detail: 'Peer is online. Open the peer lane.',
  );
}

String _phaseLabel(SessionPhase phase) {
  return switch (phase) {
    SessionPhase.checkingPresence => 'Checking',
    SessionPhase.registeringPeer => 'Registering',
    SessionPhase.waitingForOffer => 'Signaling',
    SessionPhase.creatingOffer => 'Signaling',
    SessionPhase.writingOffer => 'Signaling',
    SessionPhase.waitingForAnswer => 'Signaling',
    SessionPhase.writingAnswer => 'Signaling',
    SessionPhase.exchangingIce => 'Exchanging data',
    SessionPhase.openingDataChannels => 'Opening channels',
    SessionPhase.reconnecting => 'Reconnecting',
    SessionPhase.disconnecting => 'Disconnecting',
    SessionPhase.connected => 'Connected',
    SessionPhase.disconnected => 'Disconnected',
    SessionPhase.failed => 'Failed',
    SessionPhase.idle => 'Connecting',
  };
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const double _compactBreakpoint = 860;

  String? _selectedPeerId;

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final environment = ref.watch(appEnvironmentProvider);
    final identity = ref.watch(identityProvider).valueOrNull;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompact = constraints.maxWidth < _compactBreakpoint;
        final scheme = Theme.of(context).colorScheme;
        final isDark = scheme.brightness == Brightness.dark;

        final showShellHeader = !isCompact || _selectedPeerId == null;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(isCompact ? 8 : 20),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0C1820).withValues(alpha: 0.94)
                    : scheme.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(isCompact ? 24 : 32),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(
                    alpha: isDark ? 0.18 : 0.55,
                  ),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    blurRadius: 36,
                    color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.08),
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  if (showShellHeader) ...<Widget>[
                    _ShellHeader(
                      identity: identity,
                      backendLabel: environment.backendLabel,
                      isCompact: isCompact,
                    ),
                    const Divider(height: 1),
                  ],
                  Expanded(
                    child: isCompact
                        ? _buildCompactBody(friends)
                        : _buildWideBody(friends),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactBody(AsyncValue<List<FriendRecord>> friends) {
    if (_selectedPeerId != null) {
      return _ChatPanel(
        peerId: _selectedPeerId!,
        isCompact: true,
        onBack: () => setState(() => _selectedPeerId = null),
      );
    }

    return _FriendsListView(
      friends: friends,
      selectedPeerId: _selectedPeerId,
      onSelect: _handleFriendSelection,
      compact: true,
    );
  }

  Widget _buildWideBody(AsyncValue<List<FriendRecord>> friends) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 320,
          child: _FriendsListView(
            friends: friends,
            selectedPeerId: _selectedPeerId,
            onSelect: _handleFriendSelection,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedPeerId == null
              ? AppStateMessage(
                  icon: Icons.water_drop_outlined,
                  title: 'Choose a friend',
                  message: 'Open a conversation to start chatting.',
                )
              : _ChatPanel(peerId: _selectedPeerId!),
        ),
      ],
    );
  }

  Future<void> _handleFriendSelection(FriendRecord friend) async {
    setState(() => _selectedPeerId = friend.username);
    await ref.read(messagesProvider(friend.username).notifier).markRead();
    if (friend.state == FriendState.friend && friend.isOnline) {
      unawaited(_connectSelectedFriend(friend.username));
    }
  }

  Future<void> _connectSelectedFriend(String username) async {
    try {
      await ref.read(connectionsProvider.notifier).connect(username);
    } catch (error) {
      debugPrint('Connection attempt failed for @$username: $error');
    }
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.identity,
    required this.backendLabel,
    required this.isCompact,
  });

  final RainIdentity? identity;
  final String backendLabel;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayName = identity?.displayName ?? 'Rain';
    final handle = identity == null ? backendLabel : '@${identity!.username}';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 12 : 18,
        isCompact ? 10 : 14,
        isCompact ? 10 : 18,
        isCompact ? 10 : 14,
      ),
      child: Row(
        children: <Widget>[
          const _RainHeaderIcon(size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '$displayName  |  $backendLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RainHeaderIcon extends StatelessWidget {
  const _RainHeaderIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.30),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.24)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          'assets/branding/rain_app_icon_1024.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.water_drop, size: size * 0.58, color: scheme.primary),
        ),
      ),
    );
  }
}

class _CompactLinkStatusPill extends StatelessWidget {
  const _CompactLinkStatusPill({
    required this.status,
    required this.onTap,
    this.enabled = true,
  });

  final _ConnectionStatus status;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: status.color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: status.color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (status.isBusy)
                SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: status.color,
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: status.color,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 7),
              Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: status.color,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.tune_rounded,
                size: 14,
                color: scheme.onSurface.withValues(alpha: 0.46),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendsListView extends StatelessWidget {
  const _FriendsListView({
    required this.friends,
    required this.selectedPeerId,
    required this.onSelect,
    this.compact = false,
  });

  final AsyncValue<List<FriendRecord>> friends;
  final String? selectedPeerId;
  final ValueChanged<FriendRecord> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return friends.when(
      data: (List<FriendRecord> items) {
        if (items.isEmpty) {
          return AppStateMessage(
            icon: Icons.group_outlined,
            title: 'No friends yet',
            message:
                'Add a friend to start chatting and testing the peer connection flow.',
            iconSize: compact ? 46 : 52,
          );
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(vertical: compact ? 6 : 0),
          itemCount: items.length,
          itemBuilder: (BuildContext context, int index) {
            final friend = items[index];
            return _FriendTile(
              friend: friend,
              selected: friend.username == selectedPeerId,
              compact: compact,
              onTap: () => onSelect(friend),
            );
          },
        );
      },
      error: (Object error, StackTrace stackTrace) => AppStateMessage(
        icon: Icons.error_outline,
        title: 'Could not load friends',
        message: error.toString(),
        iconColor: Theme.of(context).colorScheme.error,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({
    required this.friend,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final FriendRecord friend;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsController = ref.read(friendsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    void openProfile() {
      AppRoutes.openFriendProfile(context, friend);
    }

    Future<void> runFriendAction(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        if (!context.mounted) {
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

    Future<void> confirmUnfriend() async {
      final confirmed = await showAppConfirmDialog(
        context: context,
        title: 'Unfriend?',
        message:
            'Remove @${friend.username} from your friends and close the peer connection?',
        confirmLabel: 'Unfriend',
        confirmStyle: FilledButton.styleFrom(backgroundColor: scheme.error),
      );
      if (confirmed == true) {
        await runFriendAction(
          () => friendsController.unfriend(friend.username),
        );
      }
    }

    final statusColor = _statusColorForFriend(friend);
    final statusLabel = _labelForState(friend.state);
    final avatarSize = compact ? 42.0 : 44.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: 3),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.24 : 0.46,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          onLongPress: openProfile,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 8 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    RainAvatar(
                      name: friend.displayName,
                      size: avatarSize,
                      statusColor: statusColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  friend.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (friend.unreadCount > 0)
                                Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 22,
                                  ),
                                  height: 22,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.secondary,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${friend.unreadCount}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onSecondary,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  '@${friend.username}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurface.withValues(
                                          alpha: 0.62,
                                        ),
                                      ),
                                ),
                              ),
                              if (compact) ...<Widget>[
                                const SizedBox(width: 8),
                                RainMiniStatusChip(
                                  label: statusLabel,
                                  color: statusColor,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (friend.state != FriendState.pendingIncoming &&
                        friend.state != FriendState.blocked) ...<Widget>[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        tooltip: 'Open peer actions',
                        iconSize: compact ? 20 : 24,
                        onSelected: (String value) async {
                          if (value == 'unfriend') {
                            await confirmUnfriend();
                          } else if (value == 'block') {
                            await runFriendAction(
                              () => friendsController.block(friend.username),
                            );
                          }
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<String>>[
                              if (friend.state == FriendState.friend)
                                const PopupMenuItem<String>(
                                  value: 'unfriend',
                                  child: Row(
                                    children: <Widget>[
                                      Icon(Icons.person_remove_outlined),
                                      SizedBox(width: 12),
                                      Text('Unfriend'),
                                    ],
                                  ),
                                ),
                              PopupMenuItem<String>(
                                value: 'block',
                                child: Row(
                                  children: <Widget>[
                                    Icon(
                                      Icons.block,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('Block'),
                                  ],
                                ),
                              ),
                            ],
                      ),
                    ],
                  ],
                ),
                if (!compact) ...<Widget>[
                  const SizedBox(height: 8),
                  RainMiniStatusChip(label: statusLabel, color: statusColor),
                ],
                if (friend.state == FriendState.pendingIncoming) ...<Widget>[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.tonal(
                        onPressed: () =>
                            friendsController.accept(friend.username),
                        child: const Text('Accept'),
                      ),
                      TextButton(
                        onPressed: () =>
                            friendsController.reject(friend.username),
                        child: const Text('Reject'),
                      ),
                      TextButton(
                        onPressed: () =>
                            friendsController.block(friend.username),
                        child: const Text('Block'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _statusColorForFriend(FriendRecord friend) {
    return switch (friend.state) {
      FriendState.friend =>
        friend.isOnline ? const Color(0xFF2DD4A3) : const Color(0xFF52646D),
      FriendState.pendingIncoming => const Color(0xFF7DD3FC),
      FriendState.pendingOutgoing => const Color(0xFFFBBF24),
      FriendState.blocked => const Color(0xFFFF6B6B),
    };
  }

  static String _labelForState(FriendState state) => switch (state) {
    FriendState.pendingOutgoing => 'Request sent',
    FriendState.pendingIncoming => 'Incoming',
    FriendState.friend => 'Friend',
    FriendState.blocked => 'Blocked',
  };
}

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
    final runtime = ref.watch(runtimeControllerProvider).valueOrNull;
    final friend = _currentFriend(friends);
    final canChat = friend?.state == FriendState.friend;
    final isPeerOnline = canChat ? friend?.isOnline ?? false : false;
    final connection = ref.watch(connectionsProvider).peer(widget.peerId);
    final connectionStatus = _connectionStatusFor(
      canChat: canChat,
      isPeerOnline: isPeerOnline,
      connection: connection,
    );
    final canConnectNow =
        runtime != null &&
        canChat &&
        isPeerOnline &&
        !connectionStatus.isBusy &&
        !connectionStatus.isConnected;
    final canDisconnectNow =
        runtime != null && canChat && connectionStatus.canDisconnect;
    final messages = ref.watch(messagesProvider(widget.peerId));
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
                  maxLength: InputValidator.messageMaxLength,
                  onSend: () => _sendMessage(runtime),
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
    final previousMessages = previous?.valueOrNull;
    final nextMessages = next.valueOrNull;
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
    required _ConnectionStatus connectionStatus,
    required bool canConnectNow,
    required bool canDisconnectNow,
  }) {
    final displayName = friend?.displayName ?? widget.peerId;
    final scheme = Theme.of(context).colorScheme;
    final handle = '@${friend?.username ?? widget.peerId}';
    void openLinkSheet() {
      _showLinkCommandSheet(
        connectionStatus: connectionStatus,
        canConnectNow: canConnectNow,
        canDisconnectNow: canDisconnectNow,
      );
    }

    if (widget.isCompact) {
      return Row(
        children: <Widget>[
          if (widget.onBack != null)
            IconButton(
              tooltip: 'Back',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(
            child: Text(
              handle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          _CompactLinkStatusPill(
            status: connectionStatus,
            enabled: canChat,
            onTap: openLinkSheet,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (widget.onBack != null)
              IconButton(
                tooltip: 'Back to control deck',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
            RainAvatar(
              name: displayName,
              size: 46,
              statusColor: canChat ? connectionStatus.color : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.62),
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
        if (canChat) ...<Widget>[
          const SizedBox(height: 12),
          RainLiveLinkBar(
            label: connectionStatus.label,
            detail: connectionStatus.detail,
            color: connectionStatus.color,
            icon: connectionStatus.icon,
            isBusy: connectionStatus.isBusy,
            strength: _linkStrength(connectionStatus),
            onTap: openLinkSheet,
          ),
        ],
      ],
    );
  }

  int _linkStrength(_ConnectionStatus status) {
    if (status.isConnected) {
      return 4;
    }
    if (status.isBusy) {
      return 2;
    }
    return switch (status.label) {
      'Failed' => 1,
      'Offline' => 0,
      _ => 1,
    };
  }

  Future<void> _showLinkCommandSheet({
    required _ConnectionStatus connectionStatus,
    required bool canConnectNow,
    required bool canDisconnectNow,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;

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
                      connectionStatus.icon,
                      color: connectionStatus.color,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Live Link',
                            style: Theme.of(sheetContext).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            connectionStatus.label,
                            style: Theme.of(sheetContext).textTheme.bodyMedium
                                ?.copyWith(color: connectionStatus.color),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  connectionStatus.detail,
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _LinkStatCard(
                      label: 'Route',
                      value: connectionStatus.isConnected
                          ? 'Peer lane'
                          : connectionStatus.isBusy
                          ? 'Opening'
                          : 'Standby',
                    ),
                    _LinkStatCard(
                      label: 'Signal',
                      value: connectionStatus.label == 'Offline'
                          ? 'Stale'
                          : connectionStatus.label == 'Failed'
                          ? 'Needs action'
                          : 'Fresh',
                    ),
                    _LinkStatCard(
                      label: 'Recovery',
                      value: connectionStatus.label == 'Recovering'
                          ? 'Active'
                          : connectionStatus.label == 'Failed'
                          ? 'Manual'
                          : 'Ready',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: canConnectNow
                          ? () {
                              Navigator.of(sheetContext).pop();
                              _connectToPeer();
                            }
                          : null,
                      icon: Icon(
                        connectionStatus.label == 'Failed'
                            ? Icons.refresh
                            : Icons.hub_outlined,
                      ),
                      label: Text(
                        connectionStatus.label == 'Failed'
                            ? 'Retry link'
                            : 'Open link',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: canDisconnectNow
                          ? () {
                              Navigator.of(sheetContext).pop();
                              _disconnectPeer();
                            }
                          : null,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
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

  Widget _buildMessages(
    AsyncValue<List<StoredMessage>> messages,
    BoxConstraints constraints,
    double horizontalPadding,
    bool isNarrow,
  ) {
    return messages.when(
      data: (List<StoredMessage> items) {
        if (items.isEmpty) {
          return AppStateMessage(
            icon: Icons.water_drop_outlined,
            title: 'No messages yet',
            message: 'Messages will appear here once the conversation starts.',
          );
        }

        return ListView.builder(
          controller: _messageScrollController,
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

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (showDayDivider)
                  RainMessageDayDivider(
                    label: _formatMessageDay(message.sentAt),
                  ),
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
                  onOpenActions: () => unawaited(_showMessageActions(message)),
                ),
              ],
            );
          },
        );
      },
      error: (Object error, StackTrace stackTrace) =>
          Center(child: Text(error.toString())),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
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
      MessageStatus.queued || MessageStatus.sending => 'Sending',
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

  FriendRecord? _currentFriend(AsyncValue<List<FriendRecord>> friends) {
    final items = friends.valueOrNull;
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
      FriendState.friend => Icons.wifi_tethering,
    };
    final title = switch (friend.state) {
      FriendState.pendingIncoming => 'Incoming friend request',
      FriendState.pendingOutgoing => 'Request pending',
      FriendState.blocked => 'User blocked',
      FriendState.friend => 'Ready to chat',
    };
    final message = switch (friend.state) {
      FriendState.pendingIncoming =>
        'Accept @${friend.username} before starting a peer-to-peer chat.',
      FriendState.pendingOutgoing =>
        'You can connect after @${friend.username} accepts your friend request.',
      FriendState.blocked =>
        'Unblock @${friend.username} before connecting or sending messages.',
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

    setState(() => _isSending = true);
    _composerController.clear();
    try {
      await runtime?.sendMessage(widget.peerId, text);
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
    setState(() => _isConnecting = true);
    try {
      await ref
          .read(connectionsProvider.notifier)
          .connect(widget.peerId, waitForConnected: true);
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
}

class _LinkStatCard extends StatelessWidget {
  const _LinkStatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
