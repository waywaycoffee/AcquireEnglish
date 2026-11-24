import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/community_models.dart';

const List<(String metric, String label)> kStarBoards =
    <(String, String)>[
  ('video_count', '看视频最多'),
  ('video_seconds', '看视频最久'),
  ('reading_seconds', '阅读最久'),
  ('vocab_seconds', '背单词最久'),
  ('vocab_learned', '背单词最多'),
];

const List<(String period, String label)> kStarPeriods =
    <(String, String)>[
  ('day', '日榜'),
  ('month', '月榜'),
  ('year', '年榜'),
];

/// 学习之星 — day / month / year multi-metric leaderboards.
class CommunityTodayStars extends ConsumerStatefulWidget {
  const CommunityTodayStars({super.key, this.embedded = true});

  final bool embedded;

  @override
  ConsumerState<CommunityTodayStars> createState() =>
      _CommunityTodayStarsState();
}

class _CommunityTodayStarsState extends ConsumerState<CommunityTodayStars> {
  String _metric = kStarBoards.first.$1;
  String _period = 'day';
  late Future<List<LeaderboardEntryDto>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<LeaderboardEntryDto>> _load() async {
    if (!ref.read(authSessionProvider).isLoggedIn) {
      return const <LeaderboardEntryDto>[];
    }
    return ref.read(acquireApiClientProvider).communityLeaderboard(
          metric: _metric,
          period: _period,
        );
  }

  void _reload() {
    setState(() => _future = _load());
  }

  String get _title {
    return switch (_period) {
      'month' => '本月学习之星',
      'year' => '本年学习之星',
      _ => '今日学习之星',
    };
  }

  String _formatValue(String metric, int value) {
    if (metric == 'video_count' || metric == 'vocab_learned') {
      final String unit = metric == 'video_count' ? '集' : '词';
      return '$value $unit';
    }
    final int minutes = (value / 60).round();
    if (minutes < 60) return '$minutes 分钟';
    final int hours = minutes ~/ 60;
    final int rem = minutes % 60;
    return rem == 0 ? '$hours 小时' : '$hours 小时 $rem 分';
  }

  @override
  Widget build(BuildContext context) {
    final bool loggedIn = ref.watch(authSessionProvider).isLoggedIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _title,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: widget.embedded ? 16 : 18,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '日榜 / 月榜 / 年榜 · 看视频 · 阅读 · 背单词',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final (String period, String label) in kStarPeriods)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _period == period,
                    onSelected: (bool selected) {
                      if (!selected || _period == period) return;
                      _period = period;
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final (String metric, String label) in kStarBoards)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _metric == metric,
                    onSelected: (bool selected) {
                      if (!selected || _metric == metric) return;
                      _metric = metric;
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (!loggedIn)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppDesignTokens.appWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppDesignTokens.borderGray),
            ),
            child: Text(
              '登录后可查看学习之星排行榜',
              style: TextStyle(
                color: AppDesignTokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          FutureBuilder<List<LeaderboardEntryDto>>(
            future: _future,
            builder: (
              BuildContext context,
              AsyncSnapshot<List<LeaderboardEntryDto>> snapshot,
            ) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  '加载失败：${snapshot.error}',
                  style: TextStyle(color: AppDesignTokens.dangerText),
                );
              }
              final List<LeaderboardEntryDto> rows =
                  snapshot.data ?? const <LeaderboardEntryDto>[];
              if (rows.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.appWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppDesignTokens.borderGray),
                  ),
                  child: Text(
                    '这段时间还没有人上榜。学习一会儿后会自动上报。',
                    style: TextStyle(
                      color: AppDesignTokens.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }
              return Column(
                children: <Widget>[
                  for (final LeaderboardEntryDto row in rows.take(10))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppDesignTokens.appWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: row.isMe
                                ? AppDesignTokens.brandGreen
                                    .withValues(alpha: 0.55)
                                : AppDesignTokens.borderGray,
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${row.rank}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: row.rank <= 3 ? 18 : 15,
                                  color: row.rank == 1
                                      ? AppDesignTokens.orange
                                      : row.rank <= 3
                                          ? AppDesignTokens.brandGreen
                                          : AppDesignTokens.textSecondary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                row.displayName + (row.isMe ? '（我）' : ''),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppDesignTokens.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              _formatValue(_metric, row.value),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppDesignTokens.primaryBlueDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
