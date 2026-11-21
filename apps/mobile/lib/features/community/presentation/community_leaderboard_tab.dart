import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/community_models.dart';
import 'adventure_ui.dart';
import 'community_provider.dart';

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

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '排行榜 · 勋章激励',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.selected)) {
                        return AdventurePalette.pathAmber;
                      }
                      return Colors.white;
                    },
                  ),
                  foregroundColor: WidgetStateProperty.all(
                    const Color(0xFF3A2A00),
                  ),
                  side: WidgetStateProperty.all(
                    BorderSide(
                      color: AdventurePalette.pathAmber.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(
                    value: 'study_today',
                    label: Text('今日时长'),
                  ),
                  ButtonSegment<String>(
                    value: 'study_week',
                    label: Text('本周时长'),
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
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () =>
                ref.read(communityLeaderboardProvider.notifier).refresh(),
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, StackTrace st) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: <Widget>[Text('加载失败：$e')],
              ),
              data: (List<LeaderboardEntryDto> rows) {
                if (rows.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: <Widget>[
                      Text(
                        '暂无上榜数据。多学习一会儿，时长会上报并出现在这里。',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                    ],
                  );
                }
                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: rows.length,
                  itemBuilder: (BuildContext context, int index) {
                    final LeaderboardEntryDto row = rows[index];
                    return AdventureRankRow(
                      rank: row.rank,
                      name: row.displayName,
                      isMe: row.isMe,
                      subtitle: row.englishLevel == null
                          ? null
                          : '水平 ${row.englishLevel}',
                      valueLabel: _formatValue(metric, row.value),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
