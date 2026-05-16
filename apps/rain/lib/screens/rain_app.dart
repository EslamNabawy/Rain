import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_routes.dart';
import '../providers/app_providers.dart';
import '../theme/rain_theme.dart';

class RainApp extends ConsumerWidget {
  const RainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Rain',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode.themeMode,
      theme: RainTheme.light(),
      darkTheme: RainTheme.dark(),
      routerConfig: router,
    );
  }
}
