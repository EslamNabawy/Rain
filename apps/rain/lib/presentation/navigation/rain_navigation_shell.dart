import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:rain/presentation/widgets/rain_backdrop.dart';

class RainNavigationShell extends StatelessWidget {
  const RainNavigationShell({
    super.key,
    required this.location,
    required this.child,
    this.showNavigation = true,
  });

  static const double _railBreakpoint = 900;

  final String location;
  final Widget child;
  final bool showNavigation;

  @override
  Widget build(BuildContext context) {
    return RainBackdrop(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final useRail =
              showNavigation && constraints.maxWidth >= _railBreakpoint;
          final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

          return Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: true,
            body: showNavigation && useRail
                ? _RailLayout(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (int index) =>
                        _openDestination(context, index),
                    child: child,
                  )
                : RepaintBoundary(child: child),
            bottomNavigationBar: showNavigation && !useRail && !keyboardOpen
                ? _BottomNavigation(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (int index) =>
                        _openDestination(context, index),
                  )
                : null,
          );
        },
      ),
    );
  }

  int get _selectedIndex {
    if (location.startsWith('/search')) {
      return 1;
    }
    if (location.startsWith('/settings')) {
      return 2;
    }
    return 0;
  }

  void _openDestination(BuildContext context, int index) {
    final target = switch (index) {
      1 => '/search',
      2 => '/settings',
      _ => '/',
    };

    if (location == target) {
      return;
    }
    context.go(target);
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return NavigationBar(
      height: 68,
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      backgroundColor: scheme.surface.withValues(alpha: 0.94),
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      destinations: const <NavigationDestination>[
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: 'Chats',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_search_outlined),
          selectedIcon: Icon(Icons.person_search),
          label: 'Find',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }
}

class _RailLayout extends StatelessWidget {
  const _RailLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SafeArea(
          right: false,
          child: NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            labelType: NavigationRailLabelType.all,
            minWidth: 86,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.82),
            destinations: const <NavigationRailDestination>[
              NavigationRailDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: Text('Chats'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.person_search_outlined),
                selectedIcon: Icon(Icons.person_search),
                label: Text('Find'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: RepaintBoundary(child: child)),
      ],
    );
  }
}
