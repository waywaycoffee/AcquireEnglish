import 'package:flutter/material.dart';

/// Pencil「Study Player · 深色 / 浅色」palette.
class StudyShellColors {
  const StudyShellColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.card,
    required this.cardActive,
    required this.border,
    required this.borderActive,
    required this.accent,
    required this.accentSoft,
    required this.accentOn,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.highlight,
    required this.progressPlayed,
    required this.progressTrack,
    required this.chipIdle,
    required this.playGlow,
    required this.glowAccent,
    required this.favorite,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color card;
  final Color cardActive;
  final Color border;
  final Color borderActive;
  final Color accent;
  final Color accentSoft;
  final Color accentOn;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color highlight;
  final Color progressPlayed;
  final Color progressTrack;
  final Color chipIdle;
  final Color playGlow;
  final Color glowAccent;
  final Color favorite;

  static const StudyShellColors dark = StudyShellColors(
    background: Color(0xFF16181E),
    surface: Color(0xFF22252E),
    surfaceRaised: Color(0xFF2A2E38),
    card: Color(0xFF22252E),
    cardActive: Color(0xFF2A2E38),
    border: Color(0xFF343845),
    borderActive: Color(0xFF4B8EFF),
    accent: Color(0xFF4B8EFF),
    accentSoft: Color(0xFF2A4A7A),
    accentOn: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9AA0AE),
    textMuted: Color(0xFF6B7280),
    highlight: Color(0xFF3DDB7A),
    progressPlayed: Color(0xFFE53935),
    progressTrack: Color(0xFF343845),
    chipIdle: Color(0xFF2A2E38),
    playGlow: Color(0x664B8EFF),
    glowAccent: Color(0x554B8EFF),
    favorite: Color(0xFFFF5A7A),
  );

  static const StudyShellColors light = StudyShellColors(
    background: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEEF1F5),
    card: Color(0xFFFFFFFF),
    cardActive: Color(0xFFFFFFFF),
    border: Color(0xFFE5E7EB),
    borderActive: Color(0xFF3B7CFF),
    accent: Color(0xFF3B7CFF),
    accentSoft: Color(0xFFD9E7FF),
    accentOn: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF6B7280),
    textMuted: Color(0xFF9CA3AF),
    highlight: Color(0xFF16A34A),
    progressPlayed: Color(0xFFDC2626),
    progressTrack: Color(0xFFE5E7EB),
    chipIdle: Color(0xFFEEF1F5),
    playGlow: Color(0x403B7CFF),
    glowAccent: Color(0x333B7CFF),
    favorite: Color(0xFFE11D48),
  );

  static StudyShellColors of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light ? light : dark;
  }
}

/// Backward-compatible static aliases (dark defaults).
class StudyShellTokens {
  StudyShellTokens._();

  static const Color background = Color(0xFF16181E);
  static const Color surface = Color(0xFF22252E);
  static const Color card = Color(0xFF22252E);
  static const Color cardActive = Color(0xFF2A2E38);
  static const Color border = Color(0xFF343845);
  static const Color borderActive = Color(0xFF4B8EFF);
  static const Color accent = Color(0xFF4B8EFF);
  static const Color accentSoft = Color(0xFF2A4A7A);
  static const Color accentOn = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9AA0AE);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color underline = Color(0xFF3DDB7A);
  static const Color progressPlayed = Color(0xFFE53935);
  static const Color progressTrack = Color(0xFF343845);
  static const Color chipIdle = Color(0xFF2A2E38);
  static const Color playGlow = Color(0x664B8EFF);

  static const Color lightBackground = Color(0xFFF5F6F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightAccent = Color(0xFF3B7CFF);
  static const Color lightHighlight = Color(0xFF16A34A);
  static const Color lightTextPrimary = Color(0xFF111827);
  static const Color lightTextSecondary = Color(0xFF6B7280);
}
