import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import 'feature_tour_keys.dart';
import 'feature_tour_provider.dart';

/// Full-screen coach marks over the real home shell (body + bottom nav).
class FeatureTourOverlay extends ConsumerStatefulWidget {
  const FeatureTourOverlay({super.key});

  @override
  ConsumerState<FeatureTourOverlay> createState() => _FeatureTourOverlayState();
}

class _FeatureTourOverlayState extends ConsumerState<FeatureTourOverlay> {
  Rect? _hole;
  int _skipStreak = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHole());
  }

  @override
  void didUpdateWidget(covariant FeatureTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHole());
  }

  GlobalKey? _keyForStep(FeatureTourStep step) {
    return switch (step) {
      FeatureTourStep.recentWatched => FeatureTourKeys.recentWatched,
      FeatureTourStep.navLibrary => FeatureTourKeys.navLibrary,
      FeatureTourStep.navReading => FeatureTourKeys.navReading,
      FeatureTourStep.navOral => FeatureTourKeys.navOral,
      FeatureTourStep.navMore => FeatureTourKeys.navMore,
      FeatureTourStep.wrapUp => null,
    };
  }

  void _measureHole() {
    if (!mounted) return;
    final FeatureTourState tour = ref.read(featureTourProvider);
    if (!tour.active) return;

    final GlobalKey? key = _keyForStep(tour.step);
    if (key == null) {
      if (_hole != null) setState(() => _hole = null);
      _skipStreak = 0;
      return;
    }

    final BuildContext? targetContext = key.currentContext;
    final RenderObject? renderObject = targetContext?.findRenderObject();
    if (targetContext == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      _skipStreak += 1;
      // Target not laid out yet — retry a few frames, then skip step.
      if (_skipStreak >= 8) {
        _skipStreak = 0;
        if (tour.step == FeatureTourStep.wrapUp) {
          return;
        }
        ref.read(featureTourProvider.notifier).next();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureHole());
      return;
    }

    _skipStreak = 0;
    final Offset topLeft = renderObject.localToGlobal(Offset.zero);
    final Size size = renderObject.size;
    final Rect next = Rect.fromLTWH(
      topLeft.dx - 6,
      topLeft.dy - 6,
      size.width + 12,
      size.height + 12,
    ).inflate(2);
    if (_hole != next) {
      setState(() => _hole = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final FeatureTourState tour = ref.watch(featureTourProvider);
    if (!tour.active) {
      return const SizedBox.shrink();
    }

    ref.listen<FeatureTourState>(featureTourProvider, (
      FeatureTourState? prev,
      FeatureTourState next,
    ) {
      if (prev?.stepIndex != next.stepIndex || prev?.active != next.active) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measureHole());
      }
    });

    final Size screen = MediaQuery.sizeOf(context);
    final FeatureTourStepCopy copy = tour.copy;
    final bool isLast = tour.stepIndex >= tour.stepCount - 1;
    final Rect? hole = tour.step == FeatureTourStep.wrapUp ? null : _hole;

    final double bubbleTop = () {
      if (hole == null) {
        return screen.height * 0.32;
      }
      final double below = hole.bottom + 16;
      final double above = hole.top - 168;
      if (below + 180 < screen.height - 24) return below;
      if (above > 48) return above;
      return (screen.height - 200).clamp(48.0, screen.height - 200);
    }();

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CustomPaint(
            painter: _HoleScrimPainter(
              hole: hole,
              color: Colors.black.withValues(alpha: 0.62),
            ),
            child: const SizedBox.expand(),
          ),
          if (hole != null)
            Positioned(
              left: hole.left,
              top: hole.top,
              width: hole.width,
              height: hole.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppDesignTokens.brandGreen,
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 20,
            right: 20,
            top: bubbleTop,
            child: _TourBubble(
              title: copy.title,
              body: copy.body,
              progressLabel: '${tour.stepIndex + 1} / ${tour.stepCount}',
              primaryLabel: isLast ? '开始使用' : '下一步',
              onPrimary: () => ref.read(featureTourProvider.notifier).next(),
              onSkip: () => ref.read(featureTourProvider.notifier).skip(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TourBubble extends StatelessWidget {
  const _TourBubble({
    required this.title,
    required this.body,
    required this.progressLabel,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onSkip,
  });

  final String title;
  final String body;
  final String progressLabel;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.appWhite,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                ),
                Text(
                  progressLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: onSkip,
                  child: Text(
                    '跳过',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: onPrimary,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.brandGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(primaryLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HoleScrimPainter extends CustomPainter {
  _HoleScrimPainter({required this.hole, required this.color});

  final Rect? hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      path.addRRect(
        RRect.fromRectAndRadius(hole!, const Radius.circular(16)),
      );
      path.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HoleScrimPainter oldDelegate) {
    return oldDelegate.hole != hole || oldDelegate.color != color;
  }

  @override
  bool hitTest(Offset position) => true;
}
