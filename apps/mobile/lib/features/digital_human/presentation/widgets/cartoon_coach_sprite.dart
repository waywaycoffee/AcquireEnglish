import 'package:flutter/material.dart';
import '../../domain/coach_animation_timeline.dart';

/// Three-by-three raster atlas. Fixed actions never invoke a video model.
///
/// Uses [Alignment] + oversized [Image] inside [ClipRect] so only one cell is
/// visible. The old [Positioned] offset path leaked adjacent mouths/faces on
/// some Android GPUs (looked like a duplicated Leo).
class CartoonCoachSprite extends StatelessWidget {
  const CartoonCoachSprite({
    super.key,
    required this.asset,
    required this.motion,
    required this.mouth,
    required this.phase,
    this.transitionDuration = Duration.zero,
    this.cols = 3,
    this.rows = 3,
  });

  const CartoonCoachSprite.portrait({super.key, required this.asset})
    : motion = CoachMotion.idle,
      mouth = CoachViseme.closed,
      phase = 0,
      transitionDuration = Duration.zero,
      cols = 3,
      rows = 3;

  final String asset;
  final CoachMotion motion;
  final CoachViseme mouth;
  final double phase;

  /// Kept for API compatibility; fades are disabled to avoid flicker.
  final Duration transitionDuration;

  final int cols;
  final int rows;

  int get frame {
    if (motion == CoachMotion.speaking) {
      // Only closed/open — other mouth cells add little and can feel jumpy.
      return mouth == CoachViseme.closed
          ? CoachViseme.closed.index
          : CoachViseme.open.index;
    }
    if (motion == CoachMotion.thinking) return 7;
    if (motion == CoachMotion.encouraging) return 8;
    if (motion == CoachMotion.listening) return 6;
    return 0;
  }

  Alignment _alignmentFor(int index) {
    final int col = index % cols;
    final int row = index ~/ cols;
    // Map cell (col,row) to Alignment of a (cols x rows)-sized child in a
    // one-cell parent: -1 = left/top edge, +1 = right/bottom edge.
    final double ax = cols <= 1 ? 0 : -1 + (2 * col / (cols - 1));
    final double ay = rows <= 1 ? 0 : -1 + (2 * row / (rows - 1));
    return Alignment(ax, ay);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = constraints.biggest.shortestSide;
        if (side <= 0 || !side.isFinite) {
          return const SizedBox.shrink();
        }
        final int index = frame.clamp(0, cols * rows - 1);
        return SizedBox(
          width: side,
          height: side,
          child: ClipRect(
            clipBehavior: Clip.hardEdge,
            child: OverflowBox(
              maxWidth: side * cols,
              maxHeight: side * rows,
              alignment: _alignmentFor(index),
              child: SizedBox(
                width: side * cols,
                height: side * rows,
                child: Image.asset(
                  asset,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  alignment: Alignment.topLeft,
                  errorBuilder:
                      (BuildContext context, Object error, StackTrace? st) =>
                          const ColoredBox(color: Color(0xFF2A2038)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
