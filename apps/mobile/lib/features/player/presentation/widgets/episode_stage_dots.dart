import 'package:flutter/material.dart';

import '../../domain/episode_study_progress.dart';

/// Four-stage dots: 未开始 / 第一次学习 / 间隔复习 / 完全掌握.
class EpisodeStageDots extends StatelessWidget {
  const EpisodeStageDots({
    required this.stage,
    this.size = 8,
    this.compact = false,
    super.key,
  });

  final EpisodeStudyStage stage;
  final double size;
  final bool compact;

  static const List<Color> _active = <Color>[
    Color(0xFF9E9E9E),
    Color(0xFF42A5F5),
    Color(0xFFFFB300),
    Color(0xFF66BB6A),
  ];

  @override
  Widget build(BuildContext context) {
    final int active = stage.dotIndex;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < 4; i++) ...<Widget>[
          if (i > 0)
            Container(
              width: compact ? 6 : 10,
              height: 1.5,
              color: i <= active
                  ? _active[i].withValues(alpha: 0.55)
                  : const Color(0xFFE0E0E0),
            ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= active ? _active[i] : const Color(0xFFE8E8E8),
              border: i == 0 && active == 0
                  ? Border.all(color: const Color(0xFFBDBDBD))
                  : null,
            ),
            child: i == 0 && active >= 0 && active < 1
                ? Icon(Icons.check, size: size * 0.75, color: Colors.white)
                : null,
          ),
        ],
      ],
    );
  }
}

class EpisodeStageLegend extends StatelessWidget {
  const EpisodeStageLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const List<(Color, String)> items = <(Color, String)>[
      (Color(0xFF9E9E9E), '未开始'),
      (Color(0xFF42A5F5), '第一次学习'),
      (Color(0xFFFFB300), '间隔复习'),
      (Color(0xFF66BB6A), '完全掌握'),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: <Widget>[
        for (final (Color c, String label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}
