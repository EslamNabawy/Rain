import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RainColors {
  static const Color primary = Color(0xFF46C6D6);
  static const Color primarySoft = Color(0xFF1C6D78);
  static const Color secondary = Color(0xFF50C878);
  static const Color tertiary = Color(0xFFFFBF00);
  static const Color mistCyan = Color(0xFF7DEBFF);
  static const Color peerMint = Color(0xFF2DD4A3);
  static const Color quietLine = Color(0xFF28424D);
  static const Color errorCoral = Color(0xFFFF6B6B);
  static const Color backgroundDark = Color(0xFF061017);
  static const Color backgroundMid = Color(0xFF0A1E26);
  static const Color backgroundDeep = Color(0xFF10141E);
  static const Color surfaceDark = Color(0xFF11222B);
  static const Color surfaceRaisedDark = Color(0xFF18313D);
  static const Color surfaceInk = Color(0xFF0C1B22);
  static const Color backgroundLight = Color(0xFFF5F9FB);
  static const Color backgroundLightCool = Color(0xFFEAF4F7);
  static const Color surfaceLight = Color(0xFFFCFEFF);
  static const Color surfaceRaisedLight = Color(0xFFE8F1F5);
  static const Color surfaceInkLight = Color(0xFFF2F7FA);
  static const Color surfaceLineLight = Color(0xFFC9D8DF);
  static const Color primaryLight = Color(0xFF086B78);
  static const Color secondaryLight = Color(0xFF16714B);
  static const Color amberLight = Color(0xFF8A5A00);
  static const Color inkLight = Color(0xFF10242D);
  static const Color inkMutedLight = Color(0xFF607783);
  static const Color warning = tertiary;
}

class RainMotion {
  static const Duration quick = Duration(milliseconds: 110);
  static const Duration standard = Duration(milliseconds: 150);
  static const Duration slow = Duration(milliseconds: 220);
  static const Duration page = Duration(milliseconds: 130);
  static const Duration pageReverse = Duration(milliseconds: 95);
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
    const primary = RainColors.primaryLight;
    const primaryContainer = Color(0xFFCFF6FA);
    const secondaryContainer = Color(0xFFD7F7E4);
    const tertiaryContainer = Color(0xFFFFE8A8);
    const error = Color(0xFFBA1A1A);
    const errorContainer = Color(0xFFFFDAD6);

    final base = ThemeData(
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: primary,
            brightness: Brightness.light,
            surface: RainColors.surfaceLight,
          ).copyWith(
            primary: primary,
            onPrimary: Colors.white,
            primaryContainer: primaryContainer,
            onPrimaryContainer: const Color(0xFF06323A),
            secondary: RainColors.secondaryLight,
            onSecondary: Colors.white,
            secondaryContainer: secondaryContainer,
            onSecondaryContainer: const Color(0xFF07351F),
            tertiary: RainColors.amberLight,
            onTertiary: Colors.white,
            tertiaryContainer: tertiaryContainer,
            onTertiaryContainer: const Color(0xFF2D1C00),
            error: error,
            onError: Colors.white,
            errorContainer: errorContainer,
            onErrorContainer: const Color(0xFF410002),
            surface: RainColors.surfaceLight,
            onSurface: RainColors.inkLight,
            surfaceBright: RainColors.surfaceLight,
            surfaceDim: RainColors.backgroundLightCool,
            surfaceContainerLow: const Color(0xFFF8FCFD),
            surfaceContainer: const Color(0xFFF4F9FB),
            surfaceContainerHigh: RainColors.surfaceInkLight,
            surfaceContainerHighest: RainColors.surfaceRaisedLight,
            outline: const Color(0xFF78909B),
            outlineVariant: RainColors.surfaceLineLight,
            shadow: const Color(0xFF14313A),
            scrim: const Color(0xFF061017),
          ),
      scaffoldBackgroundColor: RainColors.backgroundLight,
      useMaterial3: true,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      cardTheme: CardThemeData(
        color: RainColors.surfaceLight,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: RainColors.surfaceLineLight),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: RainColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: RainColors.surfaceLineLight),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: RainColors.inkLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0x66C9D8DF),
        space: 1,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: RainColors.inkLight,
          backgroundColor: Colors.white.withValues(alpha: 0.54),
          side: const BorderSide(color: RainColors.surfaceLineLight),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: RainColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: RainColors.surfaceLineLight),
        ),
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
          borderSide: const BorderSide(color: RainColors.surfaceLineLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        labelStyle: const TextStyle(
          fontFamily: 'Space Grotesk',
          color: RainColors.inkMutedLight,
        ),
        hintStyle: const TextStyle(color: RainColors.inkMutedLight),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: RainColors.inkLight,
          highlightColor: primary.withValues(alpha: 0.10),
          hoverColor: primary.withValues(alpha: 0.08),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: RainColors.surfaceLight.withValues(alpha: 0.96),
        indicatorColor: primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w700,
            color: RainColors.inkLight,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primary
                : RainColors.inkMutedLight,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: RainColors.surfaceLight.withValues(alpha: 0.90),
        indicatorColor: primaryContainer,
        selectedIconTheme: const IconThemeData(color: primary),
        unselectedIconTheme: const IconThemeData(
          color: RainColors.inkMutedLight,
        ),
        selectedLabelTextStyle: const TextStyle(
          fontFamily: 'Space Grotesk',
          fontWeight: FontWeight.w700,
          color: primary,
        ),
        unselectedLabelTextStyle: const TextStyle(
          fontFamily: 'Space Grotesk',
          fontWeight: FontWeight.w600,
          color: RainColors.inkMutedLight,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: RainColors.inkMutedLight,
        textColor: RainColors.inkLight,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: RainColors.surfaceInkLight,
        selectedColor: primaryContainer,
        disabledColor: const Color(0xFFE0E8EC),
        labelStyle: const TextStyle(color: RainColors.inkLight),
        secondaryLabelStyle: const TextStyle(color: RainColors.inkLight),
        side: const BorderSide(color: RainColors.surfaceLineLight),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: RainColors.inkLight,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
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
        TargetPlatform.iOS: _RainPageTransitionsBuilder(),
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

    final fade = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final slide =
        Tween<Offset>(
          begin: const Offset(0.012, 0.008),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}
