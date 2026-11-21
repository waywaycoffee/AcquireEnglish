import 'dart:math' as math;

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

  /// When true, render a thick 3D hardcover (spine + face + page edges).
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
      return _ClassicHardcover3D(title: title, color: color, seed: seed);
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

const Color _goldLight = Color(0xFFE8C97A);
const Color _goldMid = Color(0xFFC9A24A);
const Color _goldDark = Color(0xFF4A3410);
const Color _pageCream = Color(0xFFF4EBD8);

const List<IconData> _glyphs = <IconData>[
  Icons.eco_outlined,
  Icons.vpn_key_outlined,
  Icons.castle_outlined,
  Icons.local_florist_outlined,
  Icons.history_edu_outlined,
  Icons.pets_outlined,
];

/// Thick hardcover: left spine, front cover, right page block, soft contact shadow.
class _ClassicHardcover3D extends StatelessWidget {
  const _ClassicHardcover3D({
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
        color.computeLuminance() > 0.38 ? _goldDark : _goldLight;
    final IconData glyph = _glyphs[seed % _glyphs.length];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double w =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 100;
        final double h =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 160;
        final double spine = (w * 0.11).clamp(8.0, 14.0);
        final double pages = (w * 0.08).clamp(6.0, 11.0);
        final double depth = (w * 0.055).clamp(4.0, 8.0);
        final double faceLeft = spine;
        final double faceRight = w - pages;
        final double faceWidth = math.max(24.0, faceRight - faceLeft);
        final double unit = (faceWidth / 78).clamp(0.72, 1.35);

        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // Soft oval contact shadow on the ledge.
            Positioned(
              left: spine * 0.4,
              right: pages * 0.2,
              bottom: -3,
              height: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x55301808),
                      blurRadius: 10,
                      spreadRadius: -2,
                      offset: Offset(2, 2),
                    ),
                  ],
                ),
              ),
            ),
            CustomPaint(
              size: Size(w, h),
              painter: _HardcoverShellPainter(
                cover: color,
                spineWidth: spine,
                pageWidth: pages,
                depth: depth,
              ),
            ),
            // Face content sits on the front plane.
            Positioned(
              left: faceLeft + 5 * unit,
              right: pages + 4 * unit,
              top: depth + 8 * unit,
              bottom: 7 * unit,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: gold.withValues(alpha: 0.9),
                    width: 0.9,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(2.2 * unit),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: gold.withValues(alpha: 0.55),
                        width: 0.55,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        3 * unit,
                        6 * unit,
                        3 * unit,
                        4 * unit,
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
                              fontSize: 11.2 * unit,
                              height: 1.12,
                              fontWeight: FontWeight.w700,
                              shadows: <Shadow>[
                                Shadow(
                                  color: gold.withValues(alpha: 0.35),
                                  blurRadius: 0.6,
                                  offset: const Offset(0, 0.4),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Icon(
                                glyph,
                                size: 28 * unit,
                                color: gold.withValues(alpha: 0.92),
                                shadows: <Shadow>[
                                  Shadow(
                                    color: _goldMid.withValues(alpha: 0.45),
                                    blurRadius: 1.2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Text(
                            'ACQUIRE ENGLISH',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              color: gold.withValues(alpha: 0.88),
                              fontFamily: 'Georgia',
                              fontSize: 5.4 * unit,
                              letterSpacing: 0.45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Draws spine (left), cover face, top bevel, and stacked page edges (right).
class _HardcoverShellPainter extends CustomPainter {
  const _HardcoverShellPainter({
    required this.cover,
    required this.spineWidth,
    required this.pageWidth,
    required this.depth,
  });

  final Color cover;
  final double spineWidth;
  final double pageWidth;
  final double depth;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Color spineColor = Color.lerp(cover, Colors.black, 0.38)!;
    final Color faceLit = Color.lerp(cover, Colors.white, 0.07)!;
    final Color faceShade = Color.lerp(cover, Colors.black, 0.14)!;
    final Color topColor = Color.lerp(cover, Colors.white, 0.18)!;

    // Drop shadow behind the block (right/bottom).
    final Path shadow = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(spineWidth * 0.35, depth + 4, w - spineWidth * 0.2, h - depth - 2),
          const Radius.circular(2),
        ),
      );
    canvas.drawShadow(shadow, const Color(0xFF000000), 8, true);

    // --- Top bevel (thickness plane) ---
    final Path top = Path()
      ..moveTo(spineWidth * 0.35, depth)
      ..lineTo(spineWidth, 0)
      ..lineTo(w - pageWidth * 0.35, 0)
      ..lineTo(w - pageWidth * 0.1, depth)
      ..close();
    canvas.drawPath(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[topColor, Color.lerp(cover, Colors.black, 0.08)!],
        ).createShader(Rect.fromLTWH(0, 0, w, depth)),
    );

    // --- Spine (left thickness, slight taper) ---
    final Path spine = Path()
      ..moveTo(0, depth + 2)
      ..lineTo(spineWidth, 0)
      ..lineTo(spineWidth, h)
      ..lineTo(spineWidth * 0.25, h - 2)
      ..close();
    canvas.drawPath(
      spine,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Color.lerp(spineColor, Colors.black, 0.25)!,
            spineColor,
            Color.lerp(spineColor, cover, 0.35)!,
          ],
        ).createShader(Rect.fromLTWH(0, 0, spineWidth, h)),
    );
    // Spine ridge highlight.
    canvas.drawLine(
      Offset(spineWidth * 0.55, depth + 6),
      Offset(spineWidth * 0.55, h - 6),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 1.2,
    );

    // --- Front cover face ---
    final Path face = Path()
      ..moveTo(spineWidth, 0)
      ..lineTo(w - pageWidth, 0)
      ..lineTo(w - pageWidth, h)
      ..lineTo(spineWidth, h)
      ..close();
    canvas.drawPath(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[faceLit, cover, faceShade],
          stops: const <double>[0, 0.45, 1],
        ).createShader(Rect.fromLTWH(spineWidth, 0, w - pageWidth - spineWidth, h)),
    );
    // Cloth-ish vignette on the right edge of the face.
    canvas.drawRect(
      Rect.fromLTWH(w - pageWidth - 10, 0, 10, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            const Color(0x00000000),
            Colors.black.withValues(alpha: 0.18),
          ],
        ).createShader(Rect.fromLTWH(w - pageWidth - 10, 0, 10, h)),
    );

    // --- Page block (right) ---
    final Path pages = Path()
      ..moveTo(w - pageWidth, 0)
      ..lineTo(w - pageWidth * 0.15, depth * 0.6)
      ..lineTo(w, depth + 3)
      ..lineTo(w, h - 2)
      ..lineTo(w - pageWidth, h)
      ..close();
    canvas.drawPath(
      pages,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Color(0xFFE8DCC4),
            _pageCream,
            Color(0xFFD9CBB0),
          ],
        ).createShader(Rect.fromLTWH(w - pageWidth, 0, pageWidth, h)),
    );
    final Paint pageLine = Paint()
      ..color = const Color(0xFFC9B89A)
      ..strokeWidth = 0.7;
    for (double y = depth + 8; y < h - 6; y += 2.4) {
      canvas.drawLine(
        Offset(w - pageWidth + 1.2, y),
        Offset(w - 1.5, y + depth * 0.15),
        pageLine,
      );
    }

    // Subtle round corners silhouette.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(spineWidth * 0.2, depth * 0.2, w - spineWidth * 0.25, h - depth * 0.2),
        const Radius.circular(2),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(_HardcoverShellPainter oldDelegate) =>
      oldDelegate.cover != cover ||
      oldDelegate.spineWidth != spineWidth ||
      oldDelegate.pageWidth != pageWidth ||
      oldDelegate.depth != depth;
}
