import 'package:flutter/material.dart';

/// Palettes for the textured oak cabinet (design/exports/reading_bookshelf/
/// shelf-3d-target.jpg). Oak textures are multiplied by the tint colors.
class ReadingBookshelfTheme {
  const ReadingBookshelfTheme({
    required this.canvas,
    required this.headerTop,
    required this.headerBottom,
    required this.title,
    required this.action,
    required this.subtitle,
    required this.woodTint,
    required this.backTint,
    required this.cubbyShade,
    required this.engrave,
    required this.importInk,
    required this.importGlow,
    required this.emptyHint,
  });

  final Color canvas;
  final Color headerTop;
  final Color headerBottom;
  final Color title;
  final Color action;
  final Color subtitle;

  /// Multiplied over oak on posts, planks and the base board.
  final Color woodTint;

  /// Multiplied over oak on the recessed back panel.
  final Color backTint;

  /// Shadow cast by each plank onto the back panel below it.
  final Color cubbyShade;

  /// Stats text and ornaments carved into the base board.
  final Color engrave;
  final Color importInk;
  final Color importGlow;
  final Color emptyHint;

  static const ReadingBookshelfTheme light = ReadingBookshelfTheme(
    canvas: Color(0xFFEFE3D5),
    headerTop: Color(0xFFF1E6D9),
    headerBottom: Color(0xFFDCC9B6),
    title: Color(0xFF3A2212),
    action: Color(0xFF4A2E1A),
    subtitle: Color(0xFF8A6D4E),
    woodTint: Color(0xFFF2E6DA),
    backTint: Color(0xFFB08A68),
    cubbyShade: Color(0xFF1C0F02),
    engrave: Color(0xFF4A2D15),
    importInk: Color(0xFF4A2D15),
    importGlow: Color(0x55F6E2C6),
    emptyHint: Color(0xFFE6CFAE),
  );

  /// The cabinet is a physical object, so it keeps the light-oak look from
  /// the design even when the app runs in dark mode.
  static ReadingBookshelfTheme of(BuildContext context) => light;
}
