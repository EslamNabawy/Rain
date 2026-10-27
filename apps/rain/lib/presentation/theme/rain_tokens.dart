import 'package:material_ui/material_ui.dart';

/// Spacing scale shared by presentation code. Use these in code you touch;
/// existing literals are not swept.
class RainSpace {
  const RainSpace._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii taken from the most common literals in presentation/.
class RainRadius {
  const RainRadius._();

  static const double sm = 12;
  static const double md = 16;
  static const double lg = 18;
  static const double xl = 22;
  static const double xxl = 28;
  static const double pill = 999;
}

class RainShadows {
  const RainShadows._();

  static List<BoxShadow> panel(bool isDark) => <BoxShadow>[
    BoxShadow(
      blurRadius: 18,
      offset: const Offset(0, 10),
      color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
    ),
  ];

  static List<BoxShadow> raised(bool isDark) => <BoxShadow>[
    BoxShadow(
      blurRadius: 28,
      offset: const Offset(0, 16),
      color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
    ),
  ];
}
