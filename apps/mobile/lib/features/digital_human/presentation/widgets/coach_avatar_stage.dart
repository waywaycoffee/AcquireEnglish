import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../domain/coach_animation_timeline.dart';
import 'cartoon_coach_sprite.dart';

/// Coach portrait with a status ring for speaking and listening.
class CoachAvatarStage extends StatelessWidget {
  const CoachAvatarStage({
    required this.pulse,
    required this.speaking,
    required this.listening,
    required this.label,
    this.imageAsset,
    this.spriteAsset,
    this.displayName,
    this.liveVideo,
    super.key,
  });

  final Animation<double> pulse;
  final bool speaking;
  final bool listening;
  final String label;
  final String? spriteAsset;
  final String? imageAsset;
  final String? displayName;

  /// LiveTalking WebRTC remote video (full-bleed). When set, replaces still/cartoon.
  final Widget? liveVideo;

  @override
  Widget build(BuildContext context) {
    if (liveVideo != null) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(color: Color(0xFF18122A)),
          liveVideo!,
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
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: reduceMotion ? const AlwaysStoppedAnimation<double>(0) : pulse,
      builder: (BuildContext context, Widget? child) {
        final double t = reduceMotion ? 0 : pulse.value;
        final double bob = speaking
            ? math.sin(t * math.pi * 2) * 6
            : listening
            ? math.sin(t * math.pi * 2) * 3
            : math.sin(t * math.pi) * 2;
        final double scale = speaking
            ? 1.0 + math.sin(t * math.pi * 2) * 0.008
            : listening
            ? 1.0 + math.sin(t * math.pi * 2) * 0.005
            : 1.0;
        final double tilt = !reduceMotion && listening && !speaking
            ? math.sin(t * math.pi * 2) * 0.018
            : 0;
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
                child: Transform.rotate(
                  angle: tilt,
                  child: Transform.scale(scale: scale, child: child),
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
      child: spriteAsset != null
          ? SizedBox(
              width: 260,
              height: 260,
              child: CartoonCoachSprite(
                asset: spriteAsset!,
                mouth: CoachViseme.closed,
                phase: 0,
                motion: CoachMotion.idle,
              ),
            )
          : _AvatarDisc(
              speaking: speaking,
              listening: listening,
              pulse: pulse,
              imageAsset: imageAsset,
              displayName: displayName,
            ),
    );
  }
}

class _AvatarDisc extends StatelessWidget {
  const _AvatarDisc({
    required this.speaking,
    required this.listening,
    required this.pulse,
    this.imageAsset,
    this.displayName,
  });

  final bool speaking;
  final bool listening;
  final Animation<double> pulse;
  final String? imageAsset;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    final Color ring = speaking
        ? const Color(0xFF7C9CFF)
        : listening
        ? const Color(0xFF6EE7B7)
        : const Color(0xFF9B8EC4);
    final String asset = (imageAsset ?? '').trim();
    return AnimatedBuilder(
      animation: pulse,
      builder: (BuildContext context, Widget? child) {
        final double glow = 18 + pulse.value * (speaking ? 22 : 10);
        return Container(
          width: 196,
          height: 196,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring.withValues(alpha: 0.95), width: 3.5),
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
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (asset.isNotEmpty)
              Image.asset(
                asset,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _FallbackFace(displayName: displayName),
              )
            else
              _FallbackFace(displayName: displayName),
          ],
        ),
      ),
    );
  }
}

class _FallbackFace extends StatelessWidget {
  const _FallbackFace({this.displayName});

  final String? displayName;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF3A2F5C),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.face_retouching_natural_rounded,
              size: 72,
              color: Colors.white.withValues(alpha: 0.92),
            ),
            if ((displayName ?? '').trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                displayName!.trim(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
