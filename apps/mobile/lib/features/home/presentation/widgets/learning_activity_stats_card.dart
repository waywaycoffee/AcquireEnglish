import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/pad/app_design_tokens.dart';
import '../learning_dashboard_provider.dart';
import 'read_aloud_report_card.dart';

/// Home card: today activity counts with today-vs-yesterday deltas + period sheet.
class LearningActivityStatsCard extends ConsumerWidget {
  const LearningActivityStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LearningDashboardStats stats = ref.watch(learningDashboardProvider);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '今日学习',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: () => _openPeriodSheet(context, stats),
                  child: const Text('近 7 / 30 天'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _StatRow(
              label: '视频',
              value: stats.todayVideoCount,
              delta: stats.deltaVideoCount,
            ),
            _StatRow(
              label: '文章',
              value: stats.todayArticleCount,
              delta: stats.deltaArticleCount,
            ),
            _StatRow(
              label: '跟读',
              value: stats.todayShadowingCount,
              delta: stats.deltaShadowingCount,
              hint: stats.todayShadowSentenceCount > 0
                  ? '· ${stats.todayShadowSentenceCount} 句'
                  : null,
            ),
            _StatRow(
              label: '收藏',
              value: stats.todayFavoriteCount,
              delta: stats.deltaFavoriteCount,
            ),
            const Divider(),
            const ReadAloudReportCard(),
            const SizedBox(height: 4),
            Text(
              '与昨天对比；不依赖是否加入今日课程',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppDesignTokens.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPeriodSheet(BuildContext context, LearningDashboardStats stats) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '学习记录统计',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 16),
                _PeriodBlock(title: '近 7 天', summary: stats.weekSummary),
                const SizedBox(height: 16),
                _PeriodBlock(title: '近 30 天', summary: stats.monthSummary),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.delta,
    this.hint,
  });

  final String label;
  final int value;
  final int delta;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (hint != null) ...<Widget>[
            const SizedBox(width: 6),
            Text(
              hint!,
              style: TextStyle(
                color: AppDesignTokens.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const Spacer(),
          _DeltaChip(delta: delta),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.delta});

  final int delta;

  @override
  Widget build(BuildContext context) {
    if (delta == 0) {
      return Text(
        '—',
        style: TextStyle(
          color: AppDesignTokens.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final bool up = delta > 0;
    final Color color = up
        ? AppDesignTokens.brandGreenDark
        : const Color(0xFFB45309);
    return Text(
      '${up ? '+' : ''}$delta',
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _PeriodBlock extends StatelessWidget {
  const _PeriodBlock({required this.title, required this.summary});

  final String title;
  final LearningPeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: <Widget>[
            _chip('视频 ${summary.videoCount}'),
            _chip('文章 ${summary.articleCount}'),
            _chip('跟读 ${summary.shadowAttemptCount}'),
            _chip('跟读句 ${summary.shadowSentenceCount}'),
            _chip('收藏 ${summary.favoriteCount}'),
            _chip('分钟 ${summary.studyMinutes}'),
          ],
        ),
      ],
    );
  }

  Widget _chip(String text) {
    return Chip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
