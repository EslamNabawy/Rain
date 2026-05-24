import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:rain/presentation/branding/rain_ripple_halo_surface.dart';
import 'package:rain/presentation/widgets/rain_backdrop.dart';

class RainNavigationShell extends StatelessWidget {
  const RainNavigationShell({
    super.key,
    required this.location,
    required this.child,
    this.showNavigation = true,
    this.networkStatusMessage,
  });

  static const double _railBreakpoint = 900;

  final String location;
  final Widget child;
  final bool showNavigation;
  final String? networkStatusMessage;

  @override
  Widget build(BuildContext context) {
    final statusMessage = networkStatusMessage;
    final showStatus = statusMessage != null && statusMessage.isNotEmpty;
    final backdropVariant = location.startsWith('/settings')
        ? RainBackdropVariant.settings
        : RainBackdropVariant.shell;
    return RainBackdrop(
      variant: backdropVariant,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final useRail =
              showNavigation && constraints.maxWidth >= _railBreakpoint;
          final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

          final body = showNavigation && useRail
              ? _RailLayout(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) =>
                      _openDestination(context, index),
                  child: child,
                )
              : RepaintBoundary(child: child);

          return Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: true,
            body: Column(
              children: <Widget>[
                if (showStatus) _NetworkStatusStrip(statusMessage),
                Expanded(child: body),
              ],
            ),
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

class _NetworkStatusStrip extends StatelessWidget {
  const _NetworkStatusStrip(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        color: scheme.errorContainer.withValues(alpha: 0.92),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              size: 18,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      destinations: <NavigationDestination>[
        NavigationDestination(
          icon: const Icon(Icons.chat_bubble_outline),
          selectedIcon: _RainNavigationHaloIcon(icon: Icons.chat_bubble),
          label: 'Chats',
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_search_outlined),
          selectedIcon: _RainNavigationHaloIcon(icon: Icons.person_search),
          label: 'Find',
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: _RainNavigationHaloIcon(icon: Icons.settings),
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
            destinations: <NavigationRailDestination>[
              NavigationRailDestination(
                icon: const Icon(Icons.chat_bubble_outline),
                selectedIcon: _RainNavigationHaloIcon(icon: Icons.chat_bubble),
                label: const Text('Chats'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.person_search_outlined),
                selectedIcon: _RainNavigationHaloIcon(
                  icon: Icons.person_search,
                ),
                label: const Text('Find'),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: _RainNavigationHaloIcon(icon: Icons.settings),
                label: const Text('Settings'),
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

class _RainNavigationHaloIcon extends StatelessWidget {
  const _RainNavigationHaloIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return RainRippleHaloSurface(
      enabled: true,
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      pulseKey: icon,
      pulseOnMount: true,
      child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon)),
    );
  }
}
