import 'package:flutter/material.dart';
import '../../domain/coach_animation_timeline.dart';

/// Three-by-three raster atlas. Fixed actions never invoke a video model.
///
/// Frames switch by shifting a single cached [Image.asset] (no AnimatedSwitcher),
/// so mouth / gesture cuts do not flash white between cells.
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
    if (motion == CoachMotion.speaking) return mouth.index;
    if (motion == CoachMotion.thinking) return 7;
    if (motion == CoachMotion.encouraging) return 8;
    if (motion == CoachMotion.listening) return 6;
    // Narrow idle blink window — avoids thrashing 0↔5 near pulse peaks.
    return (phase > 0.97 && phase < 0.995) ? 5 : 0;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final double side = constraints.biggest.shortestSide;
      final int index = frame;
      return SizedBox(
        width: side,
        height: side,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment((index % 3) - 1.0, (index ~/ 3) - 1.0),
            minWidth: side * 3,
            maxWidth: side * 3,
            minHeight: side * 3,
            maxHeight: side * 3,
            child: Image.asset(
              asset,
              width: side * 3,
              height: side * 3,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      );
    },
  );
}
