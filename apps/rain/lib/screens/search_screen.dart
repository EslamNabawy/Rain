import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol_brain/protocol_brain.dart';

import '../providers/app_providers.dart';
import '../widgets/app_components.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final searchResults = ref.watch(userSearchProvider(query));
    final identity = ref.watch(identityProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Search Users')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppTextInputField(
              controller: _controller,
              labelText: 'Search',
              hintText: 'Search by username...',
              onChanged: _onSearchChanged,
              autofocus: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _debounce?.cancel();
                        _controller.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
          ),
          Expanded(
            child: query.length < 2
                ? const _SearchHint()
                : searchResults.when(
                    data: (List<BackendIdentity> results) => _SearchResults(
                      results: results,
                      currentUsername: identity?.username,
                      onSendRequest: (String username) async {
                        try {
                          await ref
                              .read(runtimeControllerProvider)
                              ?.sendFriendRequest(username);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Friend request sent to @$username',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    error: (Object error, StackTrace stackTrace) =>
                        AppStateMessage(
                          icon: Icons.error_outline,
                          title: 'Search failed',
                          message: error.toString(),
                          iconColor: Theme.of(context).colorScheme.error,
                        ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: AppStateMessage(
        icon: Icons.search,
        title: 'Search for users',
        message: 'Enter at least 2 characters to search by username.',
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.results,
    required this.currentUsername,
    required this.onSendRequest,
  });

  final List<BackendIdentity> results;
  final String? currentUsername;
  final void Function(String username) onSendRequest;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(
        child: AppStateMessage(
          icon: Icons.person_off_outlined,
          title: 'No users found',
          message: 'Try a different search term.',
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final user = results[index];
        final isCurrentUser = user.username == currentUsername;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: user.online
                ? const Color(0xFF2DD4A3)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              user.displayName.isNotEmpty
                  ? user.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(color: user.online ? Colors.white : null),
            ),
          ),
          title: Text(user.displayName),
          subtitle: Row(
            children: <Widget>[
              Text('@${user.username}'),
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: user.online
                      ? const Color(0xFF2DD4A3)
                      : const Color(0xFF52646D),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                user.online ? 'Online' : 'Offline',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          trailing: isCurrentUser
              ? const Chip(label: Text('You'))
              : FilledButton.tonal(
                  onPressed: () => onSendRequest(user.username),
                  child: const Text('Add'),
                ),
        );
      },
    );
  }
}
