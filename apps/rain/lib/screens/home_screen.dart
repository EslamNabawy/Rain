import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain_core/rain_core.dart';

import '../providers/app_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedPeerId;

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final runtime = ref.watch(runtimeControllerProvider);
    final environment = ref.watch(appEnvironmentProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(32),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                blurRadius: 36,
                color: Color(0x1A0F4C5C),
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 320,
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Rain',
                                  style: Theme.of(context).textTheme.headlineMedium,
                                ),
                                Text(environment.backendLabel),
                              ],
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: runtime == null ? null : _showAddFriendDialog,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: friends.when(
                        data: (items) => ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (BuildContext context, int index) {
                            final friend = items[index];
                            final selected = friend.username == _selectedPeerId;
                            return _FriendTile(
                              friend: friend,
                              selected: selected,
                              onTap: () {
                                setState(() => _selectedPeerId = friend.username);
                                if (friend.state == FriendState.friend) {
                                  runtime?.connectPeer(friend.username);
                                }
                              },
                              onAccept: friend.state == FriendState.pendingIncoming
                                  ? () => runtime?.acceptFriend(friend.username)
                                  : null,
                            );
                          },
                        ),
                        error: (error, stackTrace) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(error.toString()),
                          ),
                        ),
                        loading: () => const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _selectedPeerId == null
                    ? const _EmptyConversation()
                    : _ChatPanel(peerId: _selectedPeerId!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddFriendDialog() async {
    final controller = TextEditingController();
    final runtime = ref.read(runtimeControllerProvider);

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add friend'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'username'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await runtime?.sendFriendRequest(
                  controller.text.trim().toLowerCase(),
                );
              },
              child: const Text('Send request'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({
    required this.friend,
    required this.selected,
    required this.onTap,
    this.onAccept,
  });

  final FriendRecord friend;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence = ref.watch(presenceProvider(friend.username));
    final isOnline = presence.valueOrNull ?? friend.isOnline;

    return Material(
      color: selected ? const Color(0xFFF0FAF9) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? const Color(0xFF1D9A6C) : const Color(0xFFD6DBD9),
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
              if (onAccept != null) ...<Widget>[
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: onAccept,
                  child: const Text('Accept'),
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
  const _ChatPanel({required this.peerId});

  final String peerId;

  @override
  ConsumerState<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<_ChatPanel> {
  final TextEditingController _composerController = TextEditingController();

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.peerId));
    final runtime = ref.watch(runtimeControllerProvider);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.peerId,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: runtime == null ? null : () => runtime.connectPeer(widget.peerId),
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Connect'),
              ),
            ],
          ),
        ),
        Expanded(
          child: messages.when(
            data: (items) => ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              reverse: true,
              itemCount: items.length,
              itemBuilder: (BuildContext context, int index) {
                final message = items[items.length - index - 1];
                final align = message.isOutgoing
                    ? Alignment.centerRight
                    : Alignment.centerLeft;
                final bubbleColor = message.isOutgoing
                    ? const Color(0xFF0B6E7A)
                    : const Color(0xFFF1F4F4);
                final textColor = message.isOutgoing ? Colors.white : Colors.black87;

                return Align(
                  alignment: align,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    constraints: const BoxConstraints(maxWidth: 440),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(message.content, style: TextStyle(color: textColor)),
                        const SizedBox(height: 8),
                        Text(
                          '${message.status.name} · ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(message.sentAt)).format(context)}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: textColor.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            error: (error, stackTrace) => Center(child: Text(error.toString())),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _composerController,
                  minLines: 1,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: 'Write a message'),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () async {
                  final text = _composerController.text.trim();
                  if (text.isEmpty) {
                    return;
                  }
                  _composerController.clear();
                  await runtime?.sendMessage(widget.peerId, text);
                },
                icon: const Icon(Icons.arrow_upward),
                label: const Text('Send'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.water_drop_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Choose a friend to open the conversation.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
