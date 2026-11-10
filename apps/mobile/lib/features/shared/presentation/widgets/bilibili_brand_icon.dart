import 'package:flutter/material.dart';

/// Compact Bilibili-style TV mark that stays fully visible in pill buttons.
class BilibiliBrandIcon extends StatelessWidget {
  const BilibiliBrandIcon({
    this.size = 18,
    this.color = Colors.white,
    super.key,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BilibiliMarkPainter(color: color),
      ),
    );
  }
}

class _BilibiliMarkPainter extends CustomPainter {
  const _BilibiliMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double w = size.width;
    final double h = size.height;
    // Antennae
    canvas.drawLine(Offset(w * 0.30, h * 0.08), Offset(w * 0.40, h * 0.28), paint);
    canvas.drawLine(Offset(w * 0.70, h * 0.08), Offset(w * 0.60, h * 0.28), paint);

    // TV body
    final RRect body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.30, w * 0.76, h * 0.58),
      Radius.circular(w * 0.14),
    );
    canvas.drawRRect(body, paint);

    // Play diamond
    final Path play = Path()
      ..moveTo(w * 0.42, h * 0.44)
      ..lineTo(w * 0.66, h * 0.58)
      ..lineTo(w * 0.42, h * 0.72)
      ..close();
    canvas.drawPath(
      play,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _BilibiliMarkPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
