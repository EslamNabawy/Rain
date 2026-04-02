import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain_core/rain_core.dart';

import '../providers/app_providers.dart';
import '../navigation/app_routes.dart';
import '../services/rain_runtime_controller.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialogs.dart';

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
    final runtime = ref.watch(runtimeControllerProvider);
    final environment = ref.watch(appEnvironmentProvider);
    final identity = ref.watch(identityProvider).valueOrNull;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompact = constraints.maxWidth < _compactBreakpoint;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(isCompact ? 12 : 20),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0C1820).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(isCompact ? 24 : 32),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    blurRadius: 36,
                    color: Color(0x33000000),
                    offset: Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  _ShellHeader(
                    identity: identity,
                    backendLabel: environment.backendLabel,
                    onAddFriend: runtime == null ? null : _showAddFriendDialog,
                    onLogOut: _confirmLogOut,
                    isCompact: isCompact,
                    onOpenSettings: _openSettings,
                    onSearch: _openSearch,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: isCompact
                        ? _buildCompactBody(friends, runtime)
                        : _buildWideBody(friends, runtime),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactBody(
    AsyncValue<List<FriendRecord>> friends,
    RainRuntimeController? runtime,
  ) {
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
      onSelect: (FriendRecord friend) =>
          _handleFriendSelection(friend, runtime),
      compact: true,
    );
  }

  Widget _buildWideBody(
    AsyncValue<List<FriendRecord>> friends,
    RainRuntimeController? runtime,
  ) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 320,
          child: _FriendsListView(
            friends: friends,
            selectedPeerId: _selectedPeerId,
            onSelect: (FriendRecord friend) =>
                _handleFriendSelection(friend, runtime),
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

  Future<void> _handleFriendSelection(
    FriendRecord friend,
    RainRuntimeController? runtime,
  ) async {
    setState(() => _selectedPeerId = friend.username);
    await runtime?.markConversationRead(friend.username);
    if (friend.state == FriendState.friend) {
      await runtime?.connectPeer(friend.username);
    }
  }

  Future<void> _showAddFriendDialog() async {
    final runtime = ref.read(runtimeControllerProvider);
    final rawUsername = await showAppTextInputDialog(
      context: context,
      title: 'Add friend',
      confirmLabel: 'Send request',
      labelText: 'Username',
      hintText: 'username',
      helperText: '3-24 lowercase letters, numbers, underscores',
      maxLength: InputValidator.usernameMaxLength,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
        const AppLowerCaseTextFormatter(),
      ],
    );

    if (rawUsername == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final username = InputValidator.normalizeUsername(rawUsername);
    final error = InputValidator.usernameError(username);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    try {
      await runtime?.sendFriendRequest(username);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Friend request sent to @$username')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _confirmLogOut() async {
    final runtime = ref.read(runtimeControllerProvider);
    if (runtime == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);

    final shouldLogOut = await showAppConfirmDialog(
      context: context,
      title: 'Log out',
      message:
          'This will sign you out and clear the local Rain session on this device.',
      confirmLabel: 'Log out',
    );

    if (shouldLogOut != true) {
      return;
    }

    try {
      await runtime.logOut();
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not log out: $error')),
      );
    }
  }

  void _openSettings() {
    Navigator.of(context).push(AppRoutes.settings());
  }

  void _openSearch() {
    Navigator.of(context).push(AppRoutes.search());
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.identity,
    required this.backendLabel,
    required this.onAddFriend,
    required this.onLogOut,
    required this.isCompact,
    required this.onOpenSettings,
    required this.onSearch,
  });

  final RainIdentity? identity;
  final String backendLabel;
  final VoidCallback? onAddFriend;
  final VoidCallback onLogOut;
  final bool isCompact;
  final VoidCallback onOpenSettings;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final accountLabel = identity == null
        ? backendLabel
        : '${identity!.displayName} | @${identity!.username}';

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final stackActions = isCompact || constraints.maxWidth < 560;
        final actionChildren = <Widget>[
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search users',
            onPressed: onSearch,
          ),
          FilledButton.tonalIcon(
            onPressed: onAddFriend,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: onOpenSettings,
          ),
          PopupMenuButton<_HeaderAction>(
            tooltip: 'Open account menu',
            onSelected: (_HeaderAction action) {
              switch (action) {
                case _HeaderAction.logOut:
                  onLogOut();
              }
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<_HeaderAction>>[
                  PopupMenuItem<_HeaderAction>(
                    value: _HeaderAction.logOut,
                    child: Text('Log out'),
                  ),
                ],
          ),
        ];

        return Padding(
          padding: EdgeInsets.fromLTRB(
            isCompact ? 18 : 24,
            isCompact ? 18 : 24,
            isCompact ? 18 : 24,
            12,
          ),
          child: stackActions
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Rain',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(accountLabel),
                    if (identity != null)
                      Text(
                        backendLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actionChildren,
                    ),
                  ],
                )
              : Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Rain',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(accountLabel),
                          if (identity != null)
                            Text(
                              backendLabel,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    ...actionChildren,
                  ],
                ),
        );
      },
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

enum _HeaderAction { logOut }

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
    final runtime = ref.watch(runtimeControllerProvider);
    final presence = ref.watch(presenceProvider(friend.username));
    final isOnline = presence.valueOrNull ?? friend.isOnline;

    void openProfile() {
      Navigator.of(context).push(AppRoutes.friendProfile(friend));
    }

    return Material(
      color: selected ? const Color(0xFF122934) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: openProfile,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 18,
            vertical: compact ? 12 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline
                          ? const Color(0xFF2DD4A3)
                          : const Color(0xFF52646D),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(friend.displayName),
                        Text(
                          _labelForState(friend.state),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (friend.unreadCount > 0)
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      child: Text(
                        '${friend.unreadCount}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  if (friend.state != FriendState.pendingIncoming &&
                      friend.state != FriendState.blocked) ...<Widget>[
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      onSelected: (String value) async {
                        if (value == 'block') {
                          await runtime?.blockFriend(friend.username);
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                          const <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'block',
                              child: Text('Block'),
                            ),
                          ],
                    ),
                  ],
                ],
              ),
              if (friend.state == FriendState.pendingIncoming) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.tonal(
                      onPressed: () => runtime?.acceptFriend(friend.username),
                      child: const Text('Accept'),
                    ),
                    TextButton(
                      onPressed: () => runtime?.rejectFriend(friend.username),
                      child: const Text('Reject'),
                    ),
                    TextButton(
                      onPressed: () => runtime?.blockFriend(friend.username),
                      child: const Text('Block'),
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

  static String _labelForState(FriendState state) => switch (state) {
    FriendState.pendingOutgoing => 'Request sent',
    FriendState.pendingIncoming => 'Incoming request',
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
  bool _isConnecting = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _composerController.addListener(_handleComposerChanged);
  }

  @override
  void didUpdateWidget(covariant _ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peerId != widget.peerId) {
      _composerController.clear();
      _isConnecting = false;
      _isSending = false;
    }
  }

  @override
  void dispose() {
    _composerController.removeListener(_handleComposerChanged);
    _composerController.dispose();
    super.dispose();
  }

  void _handleComposerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.peerId));
    final runtime = ref.watch(runtimeControllerProvider);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isNarrow = constraints.maxWidth < 560;
        final horizontalPadding = widget.isCompact ? 16.0 : 24.0;
        final headerTopPadding = widget.isCompact ? 16.0 : 24.0;

        return Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                headerTopPadding,
                horizontalPadding,
                16,
              ),
              child: isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            if (widget.onBack != null)
                              IconButton(
                                onPressed: widget.onBack,
                                icon: const Icon(Icons.arrow_back),
                              ),
                            Expanded(
                              child: Text(
                                widget.peerId,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed: runtime == null
                                ? null
                                : () => runtime.connectPeer(widget.peerId),
                            icon: const Icon(Icons.wifi_tethering),
                            label: const Text('Connect'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        if (widget.onBack != null)
                          IconButton(
                            onPressed: widget.onBack,
                            icon: const Icon(Icons.arrow_back),
                          ),
                        Expanded(
                          child: Text(
                            widget.peerId,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: runtime == null || _isConnecting
                              ? null
                              : () => _connectToPeer(runtime),
                          icon: _isConnecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.wifi_tethering),
                          label: Text(
                            _isConnecting ? 'Connecting...' : 'Connect',
                          ),
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: messages.when(
                data: (List<StoredMessage> items) {
                  if (items.isEmpty) {
                    return AppStateMessage(
                      icon: Icons.water_drop_outlined,
                      title: 'No messages yet',
                      message:
                          'Messages will appear here once the conversation starts.',
                    );
                  }

                  return ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    reverse: true,
                    itemCount: items.length,
                    itemBuilder: (BuildContext context, int index) {
                      final message = items[items.length - index - 1];
                      final align = message.isOutgoing
                          ? Alignment.centerRight
                          : Alignment.centerLeft;
                      final bubbleColor = message.isOutgoing
                          ? const Color(0xFF1D7E8E)
                          : const Color(0xFF18262E);
                      final textColor = Colors.white;
                      final maxBubbleWidth = isNarrow
                          ? constraints.maxWidth * 0.86
                          : 440.0;

                      return Align(
                        alignment: align,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                          decoration: BoxDecoration(
                            color: bubbleColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                message.content,
                                style: TextStyle(color: textColor),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _formatMessageTime(message.sentAt),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: textColor.withValues(alpha: 0.78),
                                    ),
                              ),
                              if (message.isOutgoing &&
                                  message.status ==
                                      MessageStatus.failed) ...<Widget>[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () =>
                                      runtime?.resendMessage(message.id),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    foregroundColor: textColor,
                                  ),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                error: (Object error, StackTrace stackTrace) =>
                    Center(child: Text(error.toString())),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                8,
                horizontalPadding,
                widget.isCompact ? 16 : 24,
              ),
              child: isNarrow
                  ? Column(
                      children: <Widget>[
                        AppTextInputField(
                          controller: _composerController,
                          hintText: 'Write a message',
                          minLines: 1,
                          maxLines: 5,
                          maxLength: InputValidator.messageMaxLength,
                          suffixIcon: _composerController.text.length > 3800
                              ? Icon(
                                  Icons.warning_amber_rounded,
                                  color: Theme.of(context).colorScheme.error,
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _sendMessage(runtime),
                            icon: const Icon(Icons.arrow_upward),
                            label: const Text('Send'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        Expanded(
                          child: AppTextInputField(
                            controller: _composerController,
                            hintText: 'Write a message',
                            minLines: 1,
                            maxLines: 5,
                            maxLength: InputValidator.messageMaxLength,
                            suffixIcon: _composerController.text.length > 3800
                                ? Icon(
                                    Icons.warning_amber_rounded,
                                    color: Theme.of(context).colorScheme.error,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () => _sendMessage(runtime),
                          icon: const Icon(Icons.arrow_upward),
                          label: const Text('Send'),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
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
    await runtime?.sendMessage(widget.peerId, text);
    if (mounted) {
      setState(() => _isSending = false);
    }
  }

  Future<void> _connectToPeer(RainRuntimeController? runtime) async {
    if (runtime == null || _isConnecting) return;
    setState(() => _isConnecting = true);
    try {
      await runtime.connectPeer(widget.peerId);
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }
}
