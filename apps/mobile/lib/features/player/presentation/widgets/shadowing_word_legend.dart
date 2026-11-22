import 'package:flutter/material.dart';

import '../../domain/pronunciation_assessment.dart';

/// MatchTag → UI: 正确 / 多读 / 漏读 / 错读 (Tencent SOE tags).
Color shadowingMatchColor(PronunciationWordResult word) {
  switch (word.matchTag) {
    case 1:
      return const Color(0xFF7E57C2); // 多读
    case 2:
      return const Color(0xFFFFB300); // 漏读
    case 3:
      return const Color(0xFFE53935); // 错读
    case 4:
      return const Color(0xFF90A4AE); // 未录入
    default:
      if (word.accuracy != null && word.accuracy! < 60) {
        return const Color(0xFFE53935);
      }
      return const Color(0xFF43A047); // 正确
  }
}

String shadowingMatchLabel(PronunciationWordResult word) {
  final String tip = word.shadowingFeedback;
  if (tip.isNotEmpty) return tip;
  return '正确';
}

/// Compact four-color legend under shadowing scores.
class ShadowingWordLegend extends StatelessWidget {
  const ShadowingWordLegend({super.key});

  static const List<(Color, String)> items = <(Color, String)>[
    (Color(0xFF43A047), '正确'),
    (Color(0xFFE53935), '错读'),
    (Color(0xFFFFB300), '漏读'),
    (Color(0xFF7E57C2), '多读'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
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
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class ShadowingWordChips extends StatelessWidget {
  const ShadowingWordChips({required this.words, super.key});

  final List<PronunciationWordResult> words;

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const ShadowingWordLegend(),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final PronunciationWordResult word in words)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: shadowingMatchColor(word).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: shadowingMatchColor(word).withValues(alpha: 0.55),
                  ),
                ),
                child: Text(
                  '${word.referenceWord.isNotEmpty ? word.referenceWord : word.word}'
                  '${word.accuracy != null ? ' ${word.accuracy!.round()}' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: shadowingMatchColor(word),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
