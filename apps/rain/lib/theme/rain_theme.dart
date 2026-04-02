import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

class RainColors {
  static const Color primary = Color(0xFF46C6D6);
  static const Color primarySoft = Color(0xFF1C6D78);
  static const Color secondary = Color(0xFF50C878);
  static const Color tertiary = Color(0xFFFFBF00);
  static const Color backgroundDark = Color(0xFF061017);
  static const Color backgroundMid = Color(0xFF0A1E26);
  static const Color backgroundDeep = Color(0xFF10141E);
  static const Color surfaceDark = Color(0xFF11222B);
  static const Color surfaceRaisedDark = Color(0xFF18313D);
  static const Color surfaceInk = Color(0xFF0C1B22);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceRaisedLight = Color(0xFFE8EDF2);
  static const Color surfaceInkLight = Color(0xFFF0F4F8);
  static const Color warning = tertiary;
}

class RainMotion {
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 340);
}

class RainTheme {
  const RainTheme._();

  static ThemeData dark() {
    final base = ThemeData(
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: RainColors.primary,
            brightness: Brightness.dark,
            surface: RainColors.surfaceDark,
          ).copyWith(
            primary: RainColors.primary,
            secondary: RainColors.secondary,
            tertiary: RainColors.tertiary,
            surface: RainColors.surfaceDark,
            surfaceContainerHighest: RainColors.surfaceRaisedDark,
          ),
      scaffoldBackgroundColor: RainColors.backgroundDark,
      useMaterial3: true,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      cardTheme: CardThemeData(
        color: RainColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: RainColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0x223C5E6A),
        space: 1,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: RainColors.primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: RainColors.primary,
          textStyle: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0x3346C6D6)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: RainColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RainColors.surfaceInk,
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
          borderSide: const BorderSide(color: RainColors.primary, width: 1.4),
        ),
        labelStyle: const TextStyle(fontFamily: 'Space Grotesk'),
        hintStyle: const TextStyle(color: Color(0xFF7FA2AD)),
      ),
      pageTransitionsTheme: _pageTransitionsTheme(),
    );
  }

  static ThemeData light() {
    final base = ThemeData(
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: RainColors.primarySoft,
            brightness: Brightness.light,
            surface: RainColors.surfaceLight,
          ).copyWith(
            primary: RainColors.primarySoft,
            secondary: const Color(0xFF2E8B57),
            tertiary: RainColors.tertiary,
            surface: RainColors.surfaceLight,
            surfaceContainerHighest: RainColors.surfaceRaisedLight,
          ),
      scaffoldBackgroundColor: RainColors.surfaceLight,
      useMaterial3: true,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      cardTheme: CardThemeData(
        color: RainColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: RainColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0x1A12212A),
        space: 1,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: RainColors.primarySoft,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: RainColors.primarySoft,
          textStyle: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          side: const BorderSide(color: Color(0x3346C6D6)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: RainColors.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RainColors.surfaceInkLight,
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
          borderSide: const BorderSide(
            color: RainColors.primarySoft,
            width: 1.4,
          ),
        ),
        labelStyle: const TextStyle(fontFamily: 'Space Grotesk'),
        hintStyle: const TextStyle(color: Color(0xFF69808C)),
      ),
      pageTransitionsTheme: _pageTransitionsTheme(),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    final inter = GoogleFonts.interTextTheme(base);
    return inter.copyWith(
      displayLarge: GoogleFonts.spaceGrotesk(
        textStyle: inter.displayLarge,
        fontWeight: FontWeight.w700,
      ),
      displayMedium: GoogleFonts.spaceGrotesk(
        textStyle: inter.displayMedium,
        fontWeight: FontWeight.w700,
      ),
      displaySmall: GoogleFonts.spaceGrotesk(
        textStyle: inter.displaySmall,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: GoogleFonts.spaceGrotesk(
        textStyle: inter.headlineLarge,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.spaceGrotesk(
        textStyle: inter.headlineMedium,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: GoogleFonts.spaceGrotesk(
        textStyle: inter.headlineSmall,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.spaceGrotesk(
        textStyle: inter.titleLarge,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.spaceGrotesk(
        textStyle: inter.titleMedium,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: GoogleFonts.spaceGrotesk(
        textStyle: inter.titleSmall,
        fontWeight: FontWeight.w600,
      ),
      labelLarge: GoogleFonts.spaceGrotesk(
        textStyle: inter.labelLarge,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: GoogleFonts.spaceGrotesk(
        textStyle: inter.labelMedium,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: GoogleFonts.spaceGrotesk(
        textStyle: inter.labelSmall,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static PageTransitionsTheme _pageTransitionsTheme() {
    return const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: _RainPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: _RainPageTransitionsBuilder(),
        TargetPlatform.windows: _RainPageTransitionsBuilder(),
        TargetPlatform.linux: _RainPageTransitionsBuilder(),
      },
    );
  }
}

class _RainPageTransitionsBuilder extends PageTransitionsBuilder {
  const _RainPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.animation == null) {
      return child;
    }

    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final slide = Tween<Offset>(
      begin: const Offset(0.02, 0.015),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}
