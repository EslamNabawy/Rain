import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/app_providers.dart';
import 'root_screen.dart';

class RainApp extends ConsumerWidget {
  const RainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeProvider);

    final darkBase = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2BA7B8),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF07131A),
      useMaterial3: true,
    );

    final lightBase = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2BA7B8),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      useMaterial3: true,
    );

    ThemeData buildDarkTheme() => darkBase.copyWith(
      textTheme: GoogleFonts.spaceGroteskTextTheme(darkBase.textTheme),
      colorScheme: darkBase.colorScheme.copyWith(
        primary: const Color(0xFF2BA7B8),
        secondary: const Color(0xFFFF9F6E),
        surface: const Color(0xFF11222B),
        surfaceContainerHighest: const Color(0xFF18313D),
      ),
      cardColor: const Color(0xFF11222B),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF11222B)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0C1B22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF28424D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF28424D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF2BA7B8), width: 1.4),
        ),
      ),
    );

    ThemeData buildLightTheme() => lightBase.copyWith(
      textTheme: GoogleFonts.spaceGroteskTextTheme(lightBase.textTheme),
      colorScheme: lightBase.colorScheme.copyWith(
        primary: const Color(0xFF1A8A9B),
        secondary: const Color(0xFFE67A4A),
        surface: const Color(0xFFFFFFFF),
        surfaceContainerHighest: const Color(0xFFE8EDF2),
      ),
      cardColor: const Color(0xFFFFFFFF),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFFFFFFFF)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0F4F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD1D9E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFD1D9E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF1A8A9B), width: 1.4),
        ),
      ),
    );

    final notifier = ref.read(themeModeProvider.notifier);

    return MaterialApp(
      title: 'Rain',
      debugShowCheckedModeBanner: false,
      themeMode: notifier.themeMode,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: const RootScreen(),
    );
  }
}
