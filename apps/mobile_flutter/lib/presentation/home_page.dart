import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../data/api_service.dart';
import '../domain/item.dart';

// State for the list view
class ItemListState {
  final bool isLoading;
  final List<Item> items;
  final String? error;

  const ItemListState({
    required this.isLoading,
    required this.items,
    this.error,
  });

  factory ItemListState.initial() =>
      const ItemListState(isLoading: false, items: []);

  ItemListState copyWith({bool? isLoading, List<Item>? items, String? error}) {
    return ItemListState(
      isLoading: isLoading ?? this.isLoading,
      items: items ?? this.items,
      error: error ?? this.error,
    );
  }
}

class ItemListNotifier extends StateNotifier<ItemListState> {
  final ApiService api;
  ItemListNotifier(this.api) : super(ItemListState.initial());

  Future<void> load() async {
    try {
      state = state.copyWith(isLoading: true);
      final items = await api.fetchItems();
      state = state.copyWith(isLoading: false, items: items);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final itemListProvider = StateNotifierProvider<ItemListNotifier, ItemListState>(
  (ref) {
    final api = ApiService();
    return ItemListNotifier(api);
  },
);

class HomePage extends ConsumerStatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    // Trigger initial load after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(itemListProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(itemListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rain Mobile'),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
          ? Center(child: Text('Error: ${state.error}'))
          : ListView.builder(
              itemCount: state.items.length,
              itemBuilder: (context, index) {
                final item = state.items[index];
                return ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(item.title),
                  subtitle: Text('id=${item.id} user=${item.userId}'),
                );
              },
            ),
    );
  }
}

// Expose a small root widget so main.dart can import HomePage directly if desired
const homePage = HomePage();
