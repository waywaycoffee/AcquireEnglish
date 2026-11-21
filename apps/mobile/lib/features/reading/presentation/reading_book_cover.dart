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

  /// When true, render the classic gold-trimmed hardcover for shelf ledges.
  final bool standing;

  static const List<Color> palette = <Color>[
    Color(0xFF25472F),
    Color(0xFFB4533A),
    Color(0xFF1F3A66),
    Color(0xFFD1A23A),
    Color(0xFF5A1F2B),
    Color(0xFF1F5058),
    Color(0xFF4A2340),
    Color(0xFF3D5A4C),
    Color(0xFF8B3A2E),
    Color(0xFF33496B),
  ];

  @override
  Widget build(BuildContext context) {
    final int seed =
        title.runes.fold<int>(0, (int value, int rune) => value + rune);
    final Color color = palette[seed % palette.length];
    final bool lightInk = color.computeLuminance() > 0.55;
    final Color ink = lightInk ? const Color(0xFF3A2A18) : Colors.white;

    if (standing) {
      return _ClassicHardcover(title: title, color: color, seed: seed);
    }

    final Color muted = lightInk
        ? const Color(0xFF3A2A18).withValues(alpha: 0.7)
        : Colors.white70;

    return AspectRatio(
      aspectRatio: 0.68,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 8,
              offset: Offset(3, 4),
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
                      fontSize: 15,
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

const Color _goldLight = Color(0xFFE6C677);
const Color _goldDark = Color(0xFF4A3410);

const List<IconData> _glyphs = <IconData>[
  Icons.eco_outlined,
  Icons.vpn_key_outlined,
  Icons.castle_outlined,
  Icons.local_florist_outlined,
  Icons.history_edu_outlined,
  Icons.pets_outlined,
];

/// Jewel-tone hardcover with thin gold double border, title, glyph and imprint.
class _ClassicHardcover extends StatelessWidget {
  const _ClassicHardcover({
    required this.title,
    required this.color,
    required this.seed,
  });

  final String title;
  final Color color;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final Color gold =
        color.computeLuminance() > 0.35 ? _goldDark : _goldLight;
    final IconData glyph = _glyphs[seed % _glyphs.length];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double w = constraints.maxWidth.isFinite ? constraints.maxWidth : 96;
        final double unit = (w / 96).clamp(0.7, 1.4);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(2),
              right: Radius.circular(4),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x4D3A2410),
                blurRadius: 8,
                offset: Offset(2, 4),
              ),
            ],
            gradient: LinearGradient(
              colors: <Color>[
                Color.lerp(color, Colors.black, 0.35)!,
                Color.lerp(color, Colors.black, 0.12)!,
                color,
                Color.lerp(color, Colors.white, 0.08)!,
              ],
              stops: const <double>[0, 0.09, 0.2, 1],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(11 * unit, 6 * unit, 5 * unit, 6 * unit),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: gold.withValues(alpha: 0.85), width: 0.8),
              ),
              child: Padding(
                padding: EdgeInsets.all(2.5 * unit),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: gold.withValues(alpha: 0.6),
                      width: 0.5,
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      4 * unit,
                      8 * unit,
                      4 * unit,
                      5 * unit,
                    ),
                    child: Column(
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 3,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: gold,
                            fontFamily: 'Georgia',
                            fontSize: 11.5 * unit,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Icon(
                              glyph,
                              size: 30 * unit,
                              color: gold.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                        Text(
                          'ACQUIRE ENGLISH',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: gold.withValues(alpha: 0.85),
                            fontFamily: 'Georgia',
                            fontSize: 5.5 * unit,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}