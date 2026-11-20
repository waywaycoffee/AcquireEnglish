import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community_models.dart';
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'study_today', label: Text('今日时长')),
              ButtonSegment<String>(value: 'study_week', label: Text('本周时长')),
              ButtonSegment<String>(value: 'vocab', label: Text('词汇量')),
            ],
            selected: <String>{metric},
            onSelectionChanged: (Set<String> next) {
              ref
                  .read(communityLeaderboardProvider.notifier)
                  .setMetric(next.first);
            },
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
                    children: const <Widget>[
                      Text('暂无上榜数据。多学习一会儿，时长会上报并出现在这里。'),
                    ],
                  );
                }
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final LeaderboardEntryDto row = rows[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text('${row.rank}'),
                      ),
                      title: Text(
                        row.isMe ? '${row.displayName}（我）' : row.displayName,
                      ),
                      subtitle: Text(
                        row.englishLevel == null
                            ? ''
                            : '水平 ${row.englishLevel}',
                      ),
                      trailing: Text(
                        _formatValue(metric, row.value),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
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
