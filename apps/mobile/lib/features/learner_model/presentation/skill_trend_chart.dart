import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/learner_skill_profile.dart';
import '../domain/skill_trend.dart';

class SkillTrendChart extends StatelessWidget {
  const SkillTrendChart({required this.trend, super.key});

  final List<SkillTrendDay> trend;

  static const List<LearnerSkill> _skills = <LearnerSkill>[
    LearnerSkill.vocab,
    LearnerSkill.listening,
    LearnerSkill.reading,
  ];

  static Color _colorFor(LearnerSkill skill) => switch (skill) {
    LearnerSkill.vocab => AppDesignTokens.brandGreen,
    LearnerSkill.listening => AppDesignTokens.primaryBlue,
    LearnerSkill.reading => AppDesignTokens.orange,
    LearnerSkill.speaking => AppDesignTokens.yellow,
  };

  static String _nameFor(LearnerSkill skill) => switch (skill) {
    LearnerSkill.vocab => '认词',
    LearnerSkill.listening => '听力',
    LearnerSkill.reading => '阅读',
    LearnerSkill.speaking => '口语',
  };

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) {
      return Text(
        '还没有足够的抽测记录。',
        style: TextStyle(color: AppDesignTokens.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (trend.length - 1).toDouble(),
              minY: 0,
              maxY: (kLearnerBands.length - 1).toDouble(),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: 1,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: AppDesignTokens.softGray, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      final int index = value.round();
                      if (index < 0 || index >= kLearnerBands.length) {
                        return const SizedBox.shrink();
                      }
                      if (index % 2 != 0) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          kLearnerBands[index],
                          style: TextStyle(
                            color: AppDesignTokens.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 1,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      final int index = value.round();
                      if (index < 0 || index >= trend.length) {
                        return const SizedBox.shrink();
                      }
                      if (trend.length > 7 && index % 2 != 0) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          trend[index].label,
                          style: TextStyle(
                            color: AppDesignTokens.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (List<LineBarSpot> spots) => spots
                      .map((LineBarSpot spot) {
                        final LearnerSkill skill = _skills[spot.barIndex];
                        final String band =
                            trend[spot.x.round()].bandBySkill[skill] ?? '';
                        return LineTooltipItem(
                          '${_nameFor(skill)} $band',
                          TextStyle(
                            color: AppDesignTokens.onAccent,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
              lineBarsData: <LineChartBarData>[
                for (int s = 0; s < _skills.length; s++)
                  LineChartBarData(
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: _colorFor(_skills[s]),
                    barWidth: 3.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: trend.length <= 7,
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 3.2,
                        color: AppDesignTokens.appWhite,
                        strokeWidth: 2.5,
                        strokeColor: _colorFor(_skills[s]),
                      ),
                    ),
                    spots: <FlSpot>[
                      for (int i = 0; i < trend.length; i++)
                        FlSpot(
                          i.toDouble(),
                          trend[i].indexOf(_skills[s]).toDouble(),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: <Widget>[
            for (final LearnerSkill skill in _skills)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _colorFor(skill),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _nameFor(skill),
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
