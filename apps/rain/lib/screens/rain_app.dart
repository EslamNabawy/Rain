import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'root_screen.dart';

class RainApp extends StatelessWidget {
  const RainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2BA7B8),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF07131A),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'Rain',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: base.copyWith(
        textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme),
        colorScheme: base.colorScheme.copyWith(
          primary: const Color(0xFF2BA7B8),
          secondary: const Color(0xFFFF9F6E),
          surface: const Color(0xFF11222B),
          surfaceContainerHighest: const Color(0xFF18313D),
        ),
        cardColor: const Color(0xFF11222B),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF11222B),
        ),
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
      ),
      darkTheme: base.copyWith(
        textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme),
      ),
      home: const RootScreen(),
    );
  }
}
