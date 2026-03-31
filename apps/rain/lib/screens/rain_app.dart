import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'root_screen.dart';

class RainApp extends StatelessWidget {
  const RainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0B6E7A),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF1F5F4),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'Rain',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme),
        colorScheme: base.colorScheme.copyWith(
          primary: const Color(0xFF0B6E7A),
          secondary: const Color(0xFFF4A261),
          surface: Colors.white,
        ),
      ),
      home: const RootScreen(),
    );
  }
}
