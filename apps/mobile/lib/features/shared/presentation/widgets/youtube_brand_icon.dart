import 'package:flutter/material.dart';

/// YouTube play-button mark for import / shelf actions.
class YoutubeBrandIcon extends StatelessWidget {
  const YoutubeBrandIcon({
    this.size = 18,
    this.monochrome = false,
    super.key,
  });

  final double size;

  /// When true, paint a single-color glyph (for dark tonal buttons).
  final bool monochrome;

  static const Color brandRed = Color(0xFFFF0000);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _YoutubeMarkPainter(
          monochrome: monochrome,
          color: IconTheme.of(context).color ?? Colors.white,
        ),
      ),
    );
  }
}

class _YoutubeMarkPainter extends CustomPainter {
  const _YoutubeMarkPainter({
    required this.monochrome,
    required this.color,
  });

  final bool monochrome;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final RRect tube = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.02, h * 0.18, w * 0.96, h * 0.64),
      Radius.circular(w * 0.22),
    );
    canvas.drawRRect(
      tube,
      Paint()
        ..color = monochrome ? color : YoutubeBrandIcon.brandRed
        ..style = PaintingStyle.fill,
    );

    final Path play = Path()
      ..moveTo(w * 0.40, h * 0.34)
      ..lineTo(w * 0.72, h * 0.50)
      ..lineTo(w * 0.40, h * 0.66)
      ..close();
    canvas.drawPath(
      play,
      Paint()
        ..color = monochrome
            ? (color.computeLuminance() > 0.5
                ? const Color(0xFF111111)
                : Colors.white)
            : Colors.white
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _YoutubeMarkPainter oldDelegate) {
    return oldDelegate.monochrome != monochrome || oldDelegate.color != color;
  }
}
