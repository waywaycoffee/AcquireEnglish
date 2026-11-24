import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/community_models.dart';
import 'adventure_ui.dart';
import 'community_provider.dart';
import 'community_today_stars.dart';

class CommunityLeaderboardTab extends ConsumerWidget {
  const CommunityLeaderboardTab({super.key});

  String _formatValue(String metric, int value) {
    if (metric == 'vocab') {
      return '$value 词';
    }
    final int minutes = (value / 60).round();
    if (minutes < 60) return '$minutes 分钟';
    final int hours = minutes ~/ 60;
    final int rem = minutes % 60;
    return rem == 0 ? '$hours 小时' : '$hours 小时 $rem 分';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LeaderboardEntryDto>> async =
        ref.watch(communityLeaderboardProvider);
    final String metric = ref.watch(communityLeaderboardMetricProvider);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        const CommunityTodayStars(embedded: false),
        const SizedBox(height: 22),
        Text(
          '综合排行 · 勋章激励',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (Set<WidgetState> states) {
                if (states.contains(WidgetState.selected)) {
                  return AppDesignTokens.brandGreen.withValues(alpha: 0.22);
                }
                return AppDesignTokens.appWhite;
              },
            ),
            foregroundColor: WidgetStateProperty.all(
              AppDesignTokens.textPrimary,
            ),
            side: WidgetStateProperty.all(
              BorderSide(color: AppDesignTokens.borderGray),
            ),
          ),
          segments: const <ButtonSegment<String>>[
            ButtonSegment<String>(
              value: 'study_today',
              label: Text('今日'),
            ),
            ButtonSegment<String>(
              value: 'study_week',
              label: Text('本周'),
            ),
            ButtonSegment<String>(
              value: 'study_month',
              label: Text('本月'),
            ),
            ButtonSegment<String>(
              value: 'study_year',
              label: Text('本年'),
            ),
            ButtonSegment<String>(
              value: 'vocab',
              label: Text('词汇量'),
            ),
          ],
          selected: <String>{metric},
          onSelectionChanged: (Set<String> next) {
            ref
                .read(communityLeaderboardProvider.notifier)
                .setMetric(next.first);
          },
        ),
        const SizedBox(height: 12),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object e, StackTrace st) => Text('加载失败：$e'),
          data: (List<LeaderboardEntryDto> rows) {
            if (rows.isEmpty) {
              return Text(
                '暂无上榜数据。多学习一会儿，时长会上报并出现在这里。',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              );
            }
            return Column(
              children: <Widget>[
                for (final LeaderboardEntryDto row in rows)
                  AdventureRankRow(
                    rank: row.rank,
                    name: row.displayName,
                    isMe: row.isMe,
                    valueLabel: _formatValue(metric, row.value),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
