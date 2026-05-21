import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/application/state/app_providers.dart';
import 'package:rain/application/state/app_state.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/presentation/widgets/app_components.dart';
import 'package:rain/presentation/widgets/rain_chat_widgets.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  String _formatError(Object error) {
    final raw = error.toString().trim();
    const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
    for (final prefix in prefixes) {
      if (raw.startsWith(prefix)) {
        return raw.substring(prefix.length).trim();
      }
    }
    return raw;
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(userSearchProvider.notifier).search(_normalizedHandleText());
    });
    setState(() {});
  }

  String _normalizedHandleText() {
    final raw = _controller.text.trim();
    return InputValidator.normalizeUsername(
      raw.startsWith('@') ? raw.substring(1) : raw,
    );
  }

  Future<void> _sendHandleRequest(String? currentUsername) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final username = _normalizedHandleText();
    final error = InputValidator.usernameError(username);

    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(error), backgroundColor: errorColor),
      );
      return;
    }
    if (currentUsername != null && username == currentUsername) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('You cannot add yourself.'),
          backgroundColor: errorColor,
        ),
      );
      return;
    }

    try {
      final result = await ref
          .read(userSearchProvider.notifier)
          .sendFriendRequest(username);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result == FriendRequestResult.acceptedExisting
                ? '@$username was waiting. Friend request accepted.'
                : 'Friend request sent to @$username',
          ),
        ),
      );
      unawaited(ref.read(userSearchProvider.notifier).search(username));
    } catch (e) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(_formatError(e)), backgroundColor: errorColor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(userSearchProvider);
    final identity = ref.watch(identityProvider).value;
    final recentSearches = ref.watch(recentSearchesProvider);
    final query = _normalizedHandleText();

    return AppPageFrame(
      title: 'Find',
      icon: Icons.person_search,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppTextInputField(
                  controller: _controller,
                  labelText: 'Friend handle',
                  hintText: '@handle',
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) =>
                      unawaited(_sendHandleRequest(identity?.username)),
                  textInputAction: TextInputAction.send,
                  textInputType: TextInputType.text,
                  maxLength: InputValidator.usernameMaxLength + 1,
                  inputFormatters: <TextInputFormatter>[
                    const AppLowerCaseTextFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_@]')),
                  ],
                  autofocus: false,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isNotEmpty
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _debounce?.cancel();
                                _controller.clear();
                                ref
                                    .read(userSearchProvider.notifier)
                                    .search('');
                                setState(() {});
                              },
                            ),
                            IconButton.filledTonal(
                              tooltip: 'Add friend',
                              icon: const Icon(Icons.person_add_alt_1),
                              onPressed: () => unawaited(
                                _sendHandleRequest(identity?.username),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                        )
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  'Type @handle. Tap + to add.',
                  maxLines: 2,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(userSearchProvider.notifier).refreshCurrent(),
              child: query.length < 2
                  ? _SearchHint(
                      recentSearches: recentSearches,
                      onSelect: (String recentQuery) {
                        _controller.text = recentQuery;
                        _controller.selection = TextSelection.collapsed(
                          offset: _controller.text.length,
                        );
                        ref
                            .read(userSearchProvider.notifier)
                            .search(recentQuery);
                        setState(() {});
                      },
                    )
                  : search.when(
                      data: (UserSearchState value) => value.query == query
                          ? _SearchResults(
                              results: value.results,
                              currentUsername: identity?.username,
                              sendingTo: value.sendingTo,
                              onSendRequest: (String username) async {
                                try {
                                  final result = await ref
                                      .read(userSearchProvider.notifier)
                                      .sendFriendRequest(username);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          result ==
                                                  FriendRequestResult
                                                      .acceptedExisting
                                              ? '@$username was already waiting for you. The friend request was accepted.'
                                              : 'Friend request sent to @$username',
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(_formatError(e)),
                                        backgroundColor: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    );
                                  }
                                }
                              },
                            )
                          : const _SearchLoading(),
                      error: (Object error, StackTrace stackTrace) =>
                          _SearchError(message: error.toString()),
                      loading: () => const _SearchLoading(),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint({required this.recentSearches, required this.onSelect});

  final List<String> recentSearches;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
      children: <Widget>[
        const AppStateMessage(
          icon: Icons.search,
          title: 'Find friend',
          message: 'Type a handle to search, then tap Add.',
        ),
        if (recentSearches.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          Text(
            'Recent searches',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final query in recentSearches)
                ActionChip(
                  label: Text('@$query'),
                  avatar: const Icon(Icons.history, size: 18),
                  onPressed: () => onSelect(query),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SearchLoading extends StatelessWidget {
  const _SearchLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const <Widget>[
        SizedBox(height: 180),
        Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
      children: <Widget>[
        AppStateMessage(
          icon: Icons.error_outline,
          title: 'Find failed',
          message: message,
          iconColor: Theme.of(context).colorScheme.error,
        ),
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.results,
    required this.currentUsername,
    required this.onSendRequest,
    required this.sendingTo,
  });

  final List<BackendIdentity> results;
  final String? currentUsername;
  final String? sendingTo;
  final void Function(String username) onSendRequest;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
        children: const <Widget>[
          AppStateMessage(
            icon: Icons.person_off_outlined,
            title: 'No users found',
            message: 'Try a different search term.',
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final user = results[index];
        final isCurrentUser = user.username == currentUsername;
        final isSending = sendingTo == user.username;

        return ListTile(
          leading: RainAvatar(
            name: user.displayName,
            size: 44,
            statusColor: user.online ? const Color(0xFF2DD4A3) : null,
            gender: user.gender,
          ),
          title: Text(
            user.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '@${user.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(_genderLabel(user.gender)),
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
                  Text(
                    user.online ? 'Online' : 'Offline',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
          trailing: isCurrentUser
              ? const SizedBox(width: 44, child: Center(child: Text('You')))
              : SizedBox.square(
                  dimension: 44,
                  child: IconButton.filledTonal(
                    tooltip: isSending ? 'Sending request' : 'Add friend',
                    onPressed: isSending
                        ? null
                        : () => onSendRequest(user.username),
                    icon: isSending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1),
                  ),
                ),
        );
      },
    );
  }

  String _genderLabel(String? gender) => switch (gender) {
    'male' => 'Male',
    'female' => 'Female',
    _ => 'Gender not set',
  };
}
