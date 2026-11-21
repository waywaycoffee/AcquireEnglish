import 'package:flutter/material.dart';

/// Approved Pencil 「复习」方向：深炭底 + 亮石灰强调（R01–R07）。
abstract final class ReviewRecallTheme {
  static const Color bg = Color(0xFF1A1B1E);
  static const Color card = Color(0xFF25262B);
  static const Color cardOlive = Color(0xFF2A3324);
  static const Color cardDanger = Color(0xFF2C2222);
  static const Color lime = Color(0xFF6EC207);
  static const Color limeMuted = Color(0xFF4F8A12);
  static const Color textPrimary = Color(0xFFF4F5F7);
  static const Color textSecondary = Color(0xFF9AA0AE);
  static const Color textMuted = Color(0xFF6F7585);
  static const Color rateAgain = Color(0xFF7A3030);
  static const Color rateHard = Color(0xFF5C5230);
  static const Color rateGood = Color(0xFF2F4A28);
  static const Color rateEasy = Color(0xFF2E3A48);
  static const Color border = Color(0xFF343845);

  static ButtonStyle get primaryButton => FilledButton.styleFrom(
        backgroundColor: lime,
        foregroundColor: const Color(0xFF102000),
        disabledBackgroundColor: const Color(0xFF3A3D45),
        disabledForegroundColor: textMuted,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );

  static ButtonStyle get secondaryButton => FilledButton.styleFrom(
        backgroundColor: card,
        foregroundColor: textPrimary,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      );
}
