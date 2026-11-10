import 'package:flutter/material.dart';

/// Dark-first design tokens aligned with the Pencil dark theme board.
class AppDesignTokens {
  AppDesignTokens._();

  /// Updated from MyApp whenever theme mode resolves to light/dark.
  static Brightness brightness = Brightness.dark;

  static bool get isDark => brightness == Brightness.dark;

  static const Color brandGreen = Color(0xFF58CC02);
  static const Color brandGreenDark = Color(0xFF46A302);
  static const Color primaryBlue = Color(0xFF4DBAF0);
  static const Color primaryBlueDark = Color(0xFF1CB0F6);
  static const Color yellow = Color(0xFFFFC800);
  static const Color orange = Color(0xFFFF9600);
  static const Color onAccent = Color(0xFFFFFFFF);

  static Color get pinkLight =>
      isDark ? const Color(0xFF3D2A36) : const Color(0xFFFFE4EC);
  static Color get skyLight =>
      isDark ? const Color(0xFF1C3038) : const Color(0xFFDDF2FF);
  static Color get purpleLight =>
      isDark ? const Color(0xFF2A2438) : const Color(0xFFE8E4FF);

  /// Elevated card / chip surface.
  static Color get appWhite =>
      isDark ? const Color(0xFF22252E) : const Color(0xFFFFFFFF);

  /// App canvas / scaffold background.
  static Color get softWhite =>
      isDark ? const Color(0xFF12141A) : const Color(0xFFF3F4F7);

  static Color get softGray =>
      isDark ? const Color(0xFF2A2E38) : const Color(0xFFE8EAED);

  static Color get borderGray =>
      isDark ? const Color(0xFF343845) : const Color(0xFFD5D8E0);

  static Color get textPrimary =>
      isDark ? const Color(0xFFF3F4F6) : const Color(0xFF12141A);

  static Color get textSecondary =>
      isDark ? const Color(0xFF9AA0AE) : const Color(0xFF667085);

  static List<BoxShadow> get toyCardShadow => <BoxShadow>[
        BoxShadow(
          color: isDark ? const Color(0x66000000) : const Color(0x14000000),
          blurRadius: isDark ? 18 : 14,
          offset: const Offset(0, 8),
        ),
      ];

  static const List<BoxShadow> toyButtonShadow = <BoxShadow>[
    BoxShadow(
      color: brandGreenDark,
      offset: Offset(0, 5),
    ),
  ];
}
