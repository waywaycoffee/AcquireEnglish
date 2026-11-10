import 'dart:math';

import 'package:flutter/material.dart';

/// Overlaid reference + own-recording waveforms used by shadowing practice.
class ComparisonWaveformPainter extends CustomPainter {
  const ComparisonWaveformPainter({
    required this.reference,
    required this.own,
    required this.referenceMs,
    required this.ownMs,
    required this.timelineMs,
    required this.positionMs,
    required this.playingOwn,
    this.referenceColor = const Color(0xFF93E7FF),
    this.ownColor = const Color(0xFFFFB878),
  });

  final List<double> reference;
  final List<double> own;
  final int referenceMs;
  final int ownMs;
  final int timelineMs;
  final int? positionMs;
  final bool playingOwn;
  final Color referenceColor;
  final Color ownColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double center = size.height / 2;
    canvas.drawLine(
      Offset(0, center),
      Offset(size.width, center),
      Paint()
        ..color = const Color(0x38D6E3EC)
        ..strokeWidth = 1,
    );
    void drawWave(
      List<double> samples,
      int durationMs,
      Color color, {
      required bool foreground,
    }) {
      if (samples.isEmpty || durationMs == 0) return;
      final double width = size.width * (durationMs / timelineMs).clamp(0, 1);
      final int count = min(samples.length, max(1, (width / 4).floor()));
      final double stride = samples.length / count;
      final double peak = max(0.01, samples.reduce(max));
      final Paint bars = Paint()
        ..color = color.withValues(alpha: foreground ? 0.95 : 0.72)
        ..strokeWidth = min(foreground ? 1.6 : 3.0, width / count * 0.72)
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < count; i++) {
        final int start = (i * stride).floor();
        final int end = min(samples.length, ((i + 1) * stride).ceil());
        double amplitude = 0;
        for (int j = start; j < end; j++) {
          amplitude = max(amplitude, samples[j]);
        }
        final double height =
            (amplitude / peak).clamp(0, 1) * size.height * 0.35;
        if (height < 0.8) continue;
        final double x = width * (i + 0.5) / count;
        canvas.drawLine(
          Offset(x, center - height),
          Offset(x, center + height),
          bars,
        );
      }
    }

    drawWave(reference, referenceMs, referenceColor, foreground: false);
    drawWave(own, ownMs, ownColor, foreground: true);
    if (positionMs != null) {
      final int activeMs = playingOwn ? ownMs : referenceMs;
      final double x = size.width * positionMs!.clamp(0, activeMs) / timelineMs;
      final Color color = playingOwn ? ownColor : referenceColor;
      canvas
        ..drawLine(
          Offset(x, 8),
          Offset(x, size.height - 8),
          Paint()
            ..color = color
            ..strokeWidth = 1.5,
        )
        ..drawCircle(Offset(x, 8), 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant ComparisonWaveformPainter oldDelegate) =>
      reference != oldDelegate.reference ||
      own != oldDelegate.own ||
      referenceMs != oldDelegate.referenceMs ||
      ownMs != oldDelegate.ownMs ||
      timelineMs != oldDelegate.timelineMs ||
      positionMs != oldDelegate.positionMs ||
      playingOwn != oldDelegate.playingOwn;
}
