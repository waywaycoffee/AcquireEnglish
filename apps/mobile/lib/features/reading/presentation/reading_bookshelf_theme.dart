import 'package:flutter/material.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';

/// Light oak (cream canvas) and dark walnut bookshelf palettes.
class ReadingBookshelfTheme {
  const ReadingBookshelfTheme({
    required this.canvas,
    required this.woodOuter,
    required this.woodInner,
    required this.ledge,
    required this.ledgeHighlight,
    required this.basePlank,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.stats,
    required this.statsHint,
    required this.importFill,
    required this.importInk,
    required this.emptyHint,
  });

  final Color canvas;
  final Color woodOuter;
  final Color woodInner;
  final Color ledge;
  final Color ledgeHighlight;
  final Color basePlank;
  final Color title;
  final Color subtitle;
  final Color action;
  final Color stats;
  final Color statsHint;
  final Color importFill;
  final Color importInk;
  final Color emptyHint;

  static const ReadingBookshelfTheme light = ReadingBookshelfTheme(
    canvas: Color(0xFFFAF4E8),
    woodOuter: Color(0xFFC99F6B),
    woodInner: Color(0xFFD8B687),
    ledge: Color(0xFFCFA672),
    ledgeHighlight: Color(0xFFE9CFA3),
    basePlank: Color(0xFFD3AB78),
    title: Color(0xFF4A2E1A),
    subtitle: Color(0xFF8A6D4E),
    action: Color(0xFF5A3D27),
    stats: Color(0xFF5A3D27),
    statsHint: Color(0xFF9A8168),
    importFill: Color(0x14FFFFFF),
    importInk: Color(0xFF6B4A2E),
    emptyHint: Color(0xFFA88660),
  );

  static const ReadingBookshelfTheme dark = ReadingBookshelfTheme(
    canvas: Color(0xFF1A1410),
    woodOuter: Color(0xFF2C1B14),
    woodInner: Color(0xFF3D2A1F),
    ledge: Color(0xFF5C3D2E),
    ledgeHighlight: Color(0xFF7A5238),
    basePlank: Color(0xFF1F130E),
    title: Color(0xFFF0E4D0),
    subtitle: Color(0xFFA89078),
    action: Color(0xFFD4B896),
    stats: Color(0xFFC4A88A),
    statsHint: Color(0xFF8A7260),
    importFill: Color(0xFF4A3428),
    importInk: Color(0xFFD4B896),
    emptyHint: Color(0xFF8A7260),
  );

  static ReadingBookshelfTheme of(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    if (brightness == Brightness.dark || AppDesignTokens.isDark) {
      return dark;
    }
    return light;
  }
}
