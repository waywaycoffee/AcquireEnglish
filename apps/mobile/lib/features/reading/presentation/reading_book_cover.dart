import 'package:flutter/material.dart';

/// Stable title-based cover for built-in and imported books.
class ReadingBookCover extends StatelessWidget {
  const ReadingBookCover({
    required this.title,
    this.level = '',
    this.standing = false,
    super.key,
  });

  final String title;
  final String level;

  /// When true, sit on a shelf ledge with a soft ground shadow.
  final bool standing;

  static const List<Color> palette = <Color>[
    Color(0xFF315B50),
    Color(0xFFAD6842),
    Color(0xFF384F74),
    Color(0xFF8B4A3A),
    Color(0xFF5C6B3A),
    Color(0xFF2F4A5C),
    Color(0xFFC4A35A),
    Color(0xFF3D5A4C),
    Color(0xFF9C5A3C),
    Color(0xFF4A5E6B),
  ];

  @override
  Widget build(BuildContext context) {
    final int seed =
        title.runes.fold<int>(0, (int value, int rune) => value + rune);
    final Color color = palette[seed % palette.length];
    final bool lightInk = color.computeLuminance() > 0.55;
    final Color ink = lightInk ? const Color(0xFF3A2A18) : Colors.white;
    final Color muted = lightInk
        ? const Color(0xFF3A2A18).withValues(alpha: 0.7)
        : Colors.white70;

    return AspectRatio(
      aspectRatio: 0.68,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0x40000000),
              blurRadius: standing ? 10 : 8,
              offset: standing ? const Offset(2, 3) : const Offset(3, 4),
            ),
          ],
          gradient: LinearGradient(
            colors: <Color>[
              Color.lerp(color, Colors.black, 0.18)!,
              color,
              Color.lerp(color, Colors.white, 0.06)!,
            ],
            stops: const <double>[0, 0.08, 1],
          ),
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(6, 0, 0, 0),
          padding: const EdgeInsets.fromLTRB(10, 12, 8, 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                level.isEmpty ? 'ENGLISH' : level,
                style: TextStyle(color: muted, fontSize: 9, letterSpacing: 0.4),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontFamily: 'Georgia',
                      fontSize: standing ? 13 : 15,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Divider(color: muted.withValues(alpha: 0.5), height: 8),
              Text(
                'ACQUIRE ENGLISH',
                style: TextStyle(color: muted, fontSize: 7, letterSpacing: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
