import 'dart:ui';

import 'package:flutter/material.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';

/// Game-flavored surfaces for the community adventure loop.
/// Visual language: brand green / amber path / chunky CTAs (not purple glass).
class AdventurePalette {
  AdventurePalette._();

  static const Color pathAmber = Color(0xFFFFC800);
  static const Color pathAmberDeep = Color(0xFFE6A800);
  static const Color nightInk = Color(0xFF1A1520);
  static const Color cafeWarm = Color(0xFF2A2118);
  static const Color cafeGlow = Color(0xFFFFE4B8);
  static const Color locked = Color(0xFF4A4F5C);
}

class AdventureHeroBanner extends StatelessWidget {
  const AdventureHeroBanner({
    required this.chapterTitle,
    required this.stageLabel,
    required this.progressLabel,
    required this.onContinue,
    super.key,
    this.partnerLabel,
    this.onPartner,
    this.nodeCount = 4,
    this.clearedCount = 2,
    this.nodeLabels,
    this.chapterIndex = 1,
    this.edgeToEdge = false,
  });

  final String chapterTitle;
  final String stageLabel;
  final String progressLabel;
  final VoidCallback onContinue;
  final String? partnerLabel;
  final VoidCallback? onPartner;
  final int nodeCount;
  final int clearedCount;
  final List<String>? nodeLabels;
  final int chapterIndex;
  final bool edgeToEdge;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = edgeToEdge
        ? BorderRadius.zero
        : BorderRadius.circular(24);
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF3A2C22),
              AdventurePalette.cafeWarm,
              AdventurePalette.nightInk,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: edgeToEdge ? 168 : 132,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CustomPaint(painter: _CafeNightPainter()),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'CHAPTER ${chapterIndex.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w800,
                            color: AdventurePalette.pathAmber.withValues(
                              alpha: 0.95,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          chapterTitle,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$stageLabel · $progressLabel',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AdventurePalette.cafeGlow.withValues(
                              alpha: 0.9,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                children: <Widget>[
                  AdventurePathStrip(
                    nodeCount: nodeCount,
                    clearedCount: clearedCount,
                    labels: nodeLabels,
                  ),
                  const SizedBox(height: 14),
                  HubChunkyButton(
                    label: '继续冒险',
                    icon: Icons.play_arrow_rounded,
                    onPressed: onContinue,
                  ),
                  if (partnerLabel != null) ...<Widget>[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onPartner,
                      child: Text(
                        partnerLabel!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AdventurePalette.pathAmber,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft cafe silhouette for the adventure hero (no bundled media).
class _CafeNightPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFF1B2436), Color(0xFF2A2118)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    final Paint building = Paint()..color = const Color(0xFF17120E);
    final RRect cafe = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.18, size.height * 0.28, size.width * 0.64, size.height * 0.72),
      const Radius.circular(8),
    );
    canvas.drawRRect(cafe, building);

    final Paint window = Paint()..color = const Color(0xFFFFD28A);
    for (final double x in <double>[0.28, 0.44, 0.60]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * x, size.height * 0.42, size.width * 0.1, size.height * 0.18),
          const Radius.circular(4),
        ),
        window,
      );
    }
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.22),
      10,
      Paint()..color = AdventurePalette.pathAmber.withValues(alpha: 0.55),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.88, size.width, size.height * 0.12),
      Paint()..color = const Color(0xFF0E0C0A),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AdventurePathStrip extends StatelessWidget {
  const AdventurePathStrip({
    required this.nodeCount,
    required this.clearedCount,
    super.key,
    this.currentIndex,
    this.labels,
  });

  final int nodeCount;
  final int clearedCount;
  final int? currentIndex;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final int current = currentIndex ?? clearedCount.clamp(0, nodeCount - 1);
    return SizedBox(
      height: labels == null ? 52 : 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < nodeCount; i++) ...<Widget>[
            if (i > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i <= clearedCount
                          ? AppDesignTokens.brandGreen
                          : Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
            Column(
              children: <Widget>[
                _PathNode(
                  index: i,
                  state: i < clearedCount
                      ? _NodeState.cleared
                      : i == current
                          ? _NodeState.current
                          : _NodeState.locked,
                ),
                if (labels != null && i < labels!.length) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    labels![i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: i == current
                          ? AdventurePalette.pathAmber
                          : Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

enum _NodeState { cleared, current, locked }

class _PathNode extends StatelessWidget {
  const _PathNode({required this.index, required this.state});

  final int index;
  final _NodeState state;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color border;
    final Widget child;
    switch (state) {
      case _NodeState.cleared:
        fill = AppDesignTokens.brandGreen;
        border = AppDesignTokens.brandGreenDark;
        child = const Icon(Icons.check_rounded, color: Colors.white, size: 18);
      case _NodeState.current:
        fill = AdventurePalette.pathAmber;
        border = AdventurePalette.pathAmberDeep;
        child = Text(
          '${index + 1}',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF3A2A00),
          ),
        );
      case _NodeState.locked:
        fill = AdventurePalette.locked;
        border = const Color(0xFF2E3340);
        child = Icon(
          Icons.lock_outline_rounded,
          size: 16,
          color: Colors.white.withValues(alpha: 0.7),
        );
    }
    return Container(
      width: state == _NodeState.current ? 40 : 34,
      height: state == _NodeState.current ? 40 : 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 3),
        boxShadow: state == _NodeState.current
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x66FFC800),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class HubChunkyButton extends StatelessWidget {
  const HubChunkyButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon = Icons.play_arrow_rounded,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color bg = color ?? AppDesignTokens.brandGreen;
    final Color shadow = color == null
        ? AppDesignTokens.brandGreenDark
        : Color.lerp(bg, Colors.black, 0.25)!;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: onPressed == null
              ? const <BoxShadow>[]
              : <BoxShadow>[
                  BoxShadow(color: shadow, offset: const Offset(0, 5)),
                ],
        ),
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: AppDesignTokens.onAccent,
            disabledBackgroundColor: AppDesignTokens.softGray,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: Icon(icon, size: 26),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
        ),
      ),
    );
  }
}

/// Zigzag Duolingo-style path for the cafe chapter map.
class CafeWindingPath extends StatelessWidget {
  const CafeWindingPath({
    required this.titles,
    required this.cleared,
    required this.currentIndex,
    required this.onTapLevel,
    super.key,
  });

  final List<String> titles;
  final Set<int> cleared;
  final int currentIndex;
  final ValueChanged<int> onTapLevel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < titles.length; i++) ...<Widget>[
          _WindingRow(
            index: i,
            title: titles[i],
            alignRight: i.isOdd,
            cleared: cleared.contains(i),
            current: i == currentIndex,
            onTap: () => onTapLevel(i),
          ),
          if (i < titles.length - 1)
            _PathDash(
              fromRight: i.isOdd,
              lit: cleared.contains(i),
            ),
        ],
      ],
    );
  }
}

class _WindingRow extends StatelessWidget {
  const _WindingRow({
    required this.index,
    required this.title,
    required this.alignRight,
    required this.cleared,
    required this.current,
    required this.onTap,
  });

  final int index;
  final String title;
  final bool alignRight;
  final bool cleared;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fill = cleared
        ? AppDesignTokens.brandGreen
        : current
            ? AdventurePalette.pathAmber
            : AdventurePalette.locked;
    final Color border = cleared
        ? AppDesignTokens.brandGreenDark
        : current
            ? AdventurePalette.pathAmberDeep
            : const Color(0xFF2E3340);
    final Widget node = GestureDetector(
      onTap: onTap,
      child: Column(
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: current ? 72 : 60,
            height: current ? 72 : 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: border, width: 4),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: border,
                  offset: const Offset(0, 5),
                ),
                if (current)
                  const BoxShadow(
                    color: Color(0x66FFC800),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: cleared
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 32)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: current ? 26 : 22,
                      fontWeight: FontWeight.w900,
                      color: current
                          ? const Color(0xFF3A2A00)
                          : Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: current
                    ? AdventurePalette.pathAmber
                    : Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ),
          if (current)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '当前关',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AdventurePalette.cafeGlow,
                ),
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: <Widget>[
          if (alignRight) const Spacer(flex: 3),
          node,
          if (!alignRight) const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _PathDash extends StatelessWidget {
  const _PathDash({required this.fromRight, required this.lit});

  final bool fromRight;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: CustomPaint(
        painter: _DashPainter(
          fromRight: fromRight,
          color: lit
              ? AppDesignTokens.brandGreen
              : Colors.white.withValues(alpha: 0.28),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter({required this.fromRight, required this.color});

  final bool fromRight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final Path path = Path();
    final double startX = fromRight ? size.width * 0.72 : size.width * 0.28;
    final double endX = fromRight ? size.width * 0.28 : size.width * 0.72;
    path.moveTo(startX, 0);
    path.quadraticBezierTo(size.width * 0.5, size.height * 0.55, endX, size.height);
    final PathMetrics metrics = path.computeMetrics();
    for (final PathMetric metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = (distance + 10).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 18;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) =>
      oldDelegate.fromRight != fromRight || oldDelegate.color != color;
}

/// Three equal game tiles used on the study desk (PK / check-in / invite).
class DeskActionTile extends StatelessWidget {
  const DeskActionTile({
    required this.label,
    required this.icon,
    required this.onTap,
    super.key,
    this.color = AdventurePalette.pathAmber,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 96,
          decoration: BoxDecoration(
            color: AppDesignTokens.appWhite,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x33000000), offset: Offset(0, 4)),
            ],
            border: Border.all(color: color.withValues(alpha: 0.45), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuestFeedCard extends StatelessWidget {
  const QuestFeedCard({
    required this.title,
    required this.meta,
    required this.onPlay,
    super.key,
    this.badge = '可开练',
    this.accent,
  });

  final String title;
  final String meta;
  final VoidCallback onPlay;
  final String badge;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final Color stripe = accent ?? AppDesignTokens.brandGreen;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: AppDesignTokens.appWhite,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppDesignTokens.toyCardShadow,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: stripe,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(18),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: stripe.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: stripe,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          meta,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: stripe,
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
