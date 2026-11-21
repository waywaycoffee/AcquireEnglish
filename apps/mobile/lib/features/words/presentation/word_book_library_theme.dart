import 'package:flutter/material.dart';

/// Library / shelf palette for 词书 selection (aligned with Pencil
/// `design/word_book_library.pen` and the reading bookshelf oak look).
class WordBookLibraryTheme {
  const WordBookLibraryTheme({
    required this.canvas,
    required this.title,
    required this.subtitle,
    required this.wood,
    required this.woodInner,
    required this.card,
    required this.accent,
    required this.onAccent,
    required this.chip,
  });

  final Color canvas;
  final Color title;
  final Color subtitle;
  final Color wood;
  final Color woodInner;
  final Color card;
  final Color accent;
  final Color onAccent;
  final Color chip;

  static const WordBookLibraryTheme light = WordBookLibraryTheme(
    canvas: Color(0xFFEFE3D5),
    title: Color(0xFF3A2212),
    subtitle: Color(0xFF8A6D4E),
    wood: Color(0xFF5C3D2E),
    woodInner: Color(0xFF6B4633),
    card: Color(0xFFF7EEE3),
    accent: Color(0xFF5C3D2E),
    onAccent: Color(0xFFF7EEE3),
    chip: Color(0xFFE6CFAE),
  );

  /// Keep the physical-library look in both app themes.
  static WordBookLibraryTheme of(BuildContext context) => light;

  static const List<Color> coverPalette = <Color>[
    Color(0xFF2E4634),
    Color(0xFFA4553A),
    Color(0xFF1F3557),
    Color(0xFFCFA03C),
    Color(0xFF5E2430),
    Color(0xFF4E2228),
    Color(0xFF1F4F55),
    Color(0xFF55602E),
  ];

  static Color coverColor(String seed, [int? index]) {
    final int hash = seed.runes.fold<int>(0, (int a, int b) => a + b);
    return coverPalette[(index ?? hash) % coverPalette.length];
  }
}
