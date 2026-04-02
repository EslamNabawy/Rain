import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/rain_theme.dart';
import 'root_screen.dart';

class RainApp extends ConsumerWidget {
  const RainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);

    final notifier = ref.read(themeModeProvider.notifier);

    return MaterialApp(
      title: 'Rain',
      debugShowCheckedModeBanner: false,
      themeMode: notifier.themeMode,
      theme: RainTheme.light(),
      darkTheme: RainTheme.dark(),
      home: const RootScreen(),
    );
  }
}
