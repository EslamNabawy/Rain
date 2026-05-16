import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rain/navigation/rain_navigation_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('compact navigation switches between main app destinations', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = _buildRouter();

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Chats page'), findsOneWidget);
    expect(find.text('Search page'), findsNothing);

    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();

    expect(find.text('Search page'), findsOneWidget);
    expect(find.text('Settings page'), findsNothing);
  });

  testWidgets('wide navigation uses a rail and does not build inactive pages', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final builtPages = <String>[];
    final router = _buildRouter(onBuild: builtPages.add);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(builtPages, <String>['chats']);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings page'), findsOneWidget);
    expect(builtPages, <String>['chats', 'settings']);
  });
}

GoRouter _buildRouter({void Function(String page)? onBuild}) {
  return GoRouter(
    routes: <RouteBase>[
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) {
          return RainNavigationShell(location: state.uri.path, child: child);
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                _TrackedPage(name: 'chats', onBuild: onBuild),
          ),
          GoRoute(
            path: '/search',
            builder: (BuildContext context, GoRouterState state) =>
                _TrackedPage(name: 'search', onBuild: onBuild),
          ),
          GoRoute(
            path: '/settings',
            builder: (BuildContext context, GoRouterState state) =>
                _TrackedPage(name: 'settings', onBuild: onBuild),
          ),
        ],
      ),
    ],
  );
}

class _TrackedPage extends StatelessWidget {
  const _TrackedPage({required this.name, this.onBuild});

  final String name;
  final void Function(String page)? onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild?.call(name);
    return Center(
      child: Text('${name[0].toUpperCase()}${name.substring(1)} page'),
    );
  }
}
