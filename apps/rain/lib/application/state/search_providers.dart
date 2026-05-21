import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'app_state.dart';
import 'core_providers.dart';
import 'runtime_providers.dart';
import 'settings_providers.dart';

final userSearchProvider =
    AsyncNotifierProvider<UserSearchController, UserSearchState>(
      UserSearchController.new,
    );

class UserSearchController extends AsyncNotifier<UserSearchState> {
  int _searchSerial = 0;

  @override
  UserSearchState build() => const UserSearchState();

  Future<void> search(String query) async {
    final normalized = query.trim().toLowerCase();
    final searchSerial = ++_searchSerial;
    if (normalized.length < 2) {
      state = AsyncValue.data(UserSearchState(query: normalized));
      return;
    }
    try {
      assertNetworkReady(ref);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return;
    }

    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(() async {
      final results = await ref.read(adapterProvider).searchUsers(normalized);
      return UserSearchState(query: normalized, results: results);
    });
    if (searchSerial == _searchSerial) {
      state = next;
      if (next.hasValue) {
        ref.read(recentSearchesProvider.notifier).add(normalized);
      }
    }
  }

  Future<void> refreshCurrent() async {
    final currentQuery = state.value?.query.trim() ?? '';
    if (currentQuery.length < 2) {
      return;
    }
    await search(currentQuery);
  }

  Future<FriendRequestResult?> sendFriendRequest(String username) async {
    assertNetworkReady(ref);
    final previous = state.value ?? const UserSearchState();
    state = AsyncValue.data(previous.copyWith(sendingTo: username));
    try {
      return await _runtime().sendFriendRequest(username);
    } finally {
      final current = state.value ?? previous;
      state = AsyncValue.data(current.copyWith(sendingTo: null));
    }
  }

  RainRuntimeController _runtime() {
    final runtime = ref.read(runtimeControllerProvider).value;
    if (runtime == null) {
      throw StateError('Rain is still starting. Try again in a moment.');
    }
    return runtime;
  }
}
