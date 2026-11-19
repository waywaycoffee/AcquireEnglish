import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/dub_session_store.dart';
import '../../domain/shadow_episode_stats.dart';
import 'study_shell_tokens.dart';

/// Episode-level 100-pass shadowing progress + score line chart.
class ShadowHundredStatsCard extends StatelessWidget {
  const ShadowHundredStatsCard({
    required this.episodeId,
    this.compact = false,
    super.key,
  });

  final String episodeId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final StudyShellColors shell = StudyShellColors.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: DubSessionStore.instance.revision,
      builder: (BuildContext context, int revision, _) {
        return FutureBuilder<List<DubTake>>(
          key: ValueKey<String>('shadow-stats-$episodeId-$revision'),
          future: DubSessionStore.instance.loadTakes(
            episodeId,
            history: true,
          ),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<DubTake>> snapshot,
              ) {
                final ShadowEpisodeStats stats =
                    ShadowEpisodeStats.fromTakes(
                      snapshot.data ?? const <DubTake>[],
                    );
                return _StatsBody(
                  shell: shell,
                  stats: stats,
                  compact: compact,
                );
              },
        );
      },
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({
    required this.shell,
    required this.stats,
    required this.compact,
  });

  final StudyShellColors shell;
  final ShadowEpisodeStats stats;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final List<({int passIndex, int score})> points = stats.chartPoints();
    final String avgLabel = stats.avgScore == null
        ? '—'
        : stats.avgScore!.round().toString();
    return Material(
      color: shell.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: compact
            ? () => _openDetailSheet(context)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      stats.goalReached
                          ? '本集已完成 100 遍跟读'
                          : '本集跟读 ${stats.passCount}/${ShadowEpisodeStats.goalPasses}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: shell.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    stats.goalReached
                        ? '达标'
                        : '还差 ${stats.remaining} 遍',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: stats.goalReached
                          ? const Color(0xFF58CC02)
                          : shell.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: stats.progress.clamp(0.02, 1.0),
                  minHeight: 8,
                  backgroundColor: shell.border.withValues(alpha: 0.35),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    stats.goalReached
                        ? const Color(0xFF58CC02)
                        : shell.accent,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  _StatChip(
                    shell: shell,
                    label: '最高',
                    value: '${stats.maxScore ?? '—'}',
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    shell: shell,
                    label: '最低',
                    value: '${stats.minScore ?? '—'}',
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    shell: shell,
                    label: '平均',
                    value: avgLabel,
                  ),
                  const Spacer(),
                  Text(
                    '已评分 ${stats.scoresChronological.length} 次',
                    style: TextStyle(
                      fontSize: 11,
                      color: shell.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (!compact && points.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                SizedBox(
                  height: 140,
                  child: _ScoreLineChart(shell: shell, points: points),
                ),
              ],
              if (compact && points.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  '点按查看分数折线图',
                  style: TextStyle(
                    fontSize: 11,
                    color: shell.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openDetailSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: shell.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: shell.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '100 遍跟读统计',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: shell.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '每一次跟读录音计 1 遍；折线为历次评分（0–100）。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: shell.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              _StatsBody(
                shell: shell,
                stats: stats,
                compact: false,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.shell,
    required this.label,
    required this.value,
  });

  final StudyShellColors shell;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: shell.border.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: shell.textPrimary,
        ),
      ),
    );
  }
}

class _ScoreLineChart extends StatelessWidget {
  const _ScoreLineChart({
    required this.shell,
    required this.points,
  });

  final StudyShellColors shell;
  final List<({int passIndex, int score})> points;

  @override
  Widget build(BuildContext context) {
    final int labelStep = points.length <= 8 ? 1 : (points.length / 5).ceil();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: points.length <= 1 ? 1 : (points.length - 1).toDouble(),
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: shell.border.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 50,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value != 0 && value != 50 && value != 100) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${value.toInt()}',
                    style: TextStyle(
                      color: shell.textMuted,
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
              reservedSize: 22,
              interval: labelStep.toDouble(),
              getTitlesWidget: (double value, TitleMeta meta) {
                final int index = value.round();
                if (index < 0 ||
                    index >= points.length ||
                    index % labelStep != 0) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '#${points[index].passIndex}',
                    style: TextStyle(
                      color: shell.textMuted,
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
                .map(
                  (LineBarSpot spot) => LineTooltipItem(
                    '第${points[spot.x.round()].passIndex}遍 · ${points[spot.x.round()].score}分',
                    TextStyle(
                      color: shell.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            isCurved: true,
            curveSmoothness: 0.25,
            color: shell.accent,
            barWidth: 3.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: points.length <= 20,
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 3.2,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: shell.accent,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  shell.accent.withValues(alpha: 0.35),
                  shell.accent.withValues(alpha: 0),
                ],
              ),
            ),
            spots: <FlSpot>[
              for (int i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].score.toDouble()),
            ],
          ),
        ],
      ),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }
}
