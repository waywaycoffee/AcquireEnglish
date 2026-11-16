import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Local coach stage: circular avatar + fixed idle / speaking motions.
///
/// Replaces always-on LiveTalking WebRTC during conversation to save GPU.
class CoachAvatarStage extends StatelessWidget {
  const CoachAvatarStage({
    required this.pulse,
    required this.speaking,
    required this.listening,
    required this.label,
    super.key,
  });

  final Animation<double> pulse;
  final bool speaking;
  final bool listening;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (BuildContext context, Widget? child) {
        final double t = pulse.value;
        final double bob = speaking
            ? math.sin(t * math.pi * 2) * 6
            : listening
            ? math.sin(t * math.pi * 2) * 3
            : math.sin(t * math.pi) * 2;
        final double scale = speaking
            ? 1.0 + t * 0.04
            : listening
            ? 1.0 + t * 0.02
            : 1.0;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 0.95,
                  colors: <Color>[
                    Color(0xFF4A3A6E),
                    Color(0xFF2A2038),
                    Color(0xFF18122A),
                  ],
                ),
              ),
            ),
            Center(
              child: Transform.translate(
                offset: Offset(0, bob),
                child: Transform.scale(
                  scale: scale,
                  child: child,
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 28,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        );
      },
      child: _AvatarDisc(speaking: speaking, listening: listening, pulse: pulse),
    );
  }
}

class _AvatarDisc extends StatelessWidget {
  const _AvatarDisc({
    required this.speaking,
    required this.listening,
    required this.pulse,
  });

  final bool speaking;
  final bool listening;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final Color ring = speaking
        ? const Color(0xFF7C9CFF)
        : listening
        ? const Color(0xFF6EE7B7)
        : const Color(0xFF9B8EC4);
    return AnimatedBuilder(
      animation: pulse,
      builder: (BuildContext context, Widget? child) {
        final double glow = 18 + pulse.value * (speaking ? 22 : 10);
        return Container(
          width: 168,
          height: 168,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF5B4B8A), Color(0xFF2F2550)],
            ),
            border: Border.all(color: ring.withValues(alpha: 0.9), width: 3),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: ring.withValues(alpha: 0.35),
                blurRadius: glow,
                spreadRadius: speaking ? 4 : 1,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Icon(
            Icons.face_retouching_natural_rounded,
            size: 78,
            color: Colors.white.withValues(alpha: 0.92),
          ),
          Positioned(
            bottom: 28,
            child: _MouthBar(speaking: speaking, pulse: pulse),
          ),
        ],
      ),
    );
  }
}

/// Fixed “talking” motion — a simple mouth bar, not GPU lip-sync.
class _MouthBar extends StatelessWidget {
  const _MouthBar({required this.speaking, required this.pulse});

  final bool speaking;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (BuildContext context, Widget? child) {
        final double h = speaking ? 4.0 + pulse.value * 10.0 : 3.0;
        final double w = speaking ? 28.0 + pulse.value * 8.0 : 22.0;
        return Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: speaking ? 0.85 : 0.35),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
    );
  }
}
