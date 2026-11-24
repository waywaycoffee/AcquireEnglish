import 'package:flutter/material.dart';
import '../../domain/coach_animation_timeline.dart';

/// Three-by-three raster atlas. Fixed actions never invoke a video model.
///
/// Cells are shown by integer pixel translation (not [Alignment]), and speaking
/// holds a single open-mouth cell — alternating cells reads as left-right shake
/// because these atlases are not position-locked.
class CartoonCoachSprite extends StatelessWidget {
  const CartoonCoachSprite({
    super.key,
    required this.asset,
    required this.motion,
    required this.mouth,
    required this.phase,
    this.transitionDuration = Duration.zero,
  });
  const CartoonCoachSprite.portrait({super.key, required this.asset})
    : motion = CoachMotion.idle,
      mouth = CoachViseme.closed,
      phase = 0,
      transitionDuration = Duration.zero;

  final String asset;
  final CoachMotion motion;
  final CoachViseme mouth;
  final double phase;

  /// Kept for API compatibility; fades are disabled to avoid flicker.
  final Duration transitionDuration;

  int get frame {
    // Speaking: hold open cell only. Cycling closed↔open shakes every persona.
    if (motion == CoachMotion.speaking) return CoachViseme.open.index;
    // Gesture cells (6–8) are also misaligned vs idle — skip until atlases
    // are re-authored with locked head position.
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = constraints.biggest.shortestSide;
        final int index = frame;
        final int col = index % 3;
        final int row = index ~/ 3;
        return SizedBox(
          width: side,
          height: side,
          child: ClipRect(
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: -side * col,
                  top: -side * row,
                  width: side * 3,
                  height: side * 3,
                  child: Image.asset(
                    asset,
                    width: side * 3,
                    height: side * 3,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    alignment: Alignment.topLeft,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
