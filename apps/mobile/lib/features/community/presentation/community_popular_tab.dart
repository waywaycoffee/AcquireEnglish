import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../import_course/data/bilibili_open_or_import.dart';
import '../../shared/presentation/media/cover_image.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/community_models.dart';
import 'community_provider.dart';

/// 「热门」: videos / books others studied today, ranked by learner count.
class CommunityPopularTab extends ConsumerWidget {
  const CommunityPopularTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CommunityPopularBundle> async =
        ref.watch(communityPopularProvider);
    final AsyncValue<CommunityHotBundle> hotShares =
        ref.watch(communityHotProvider);

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait(<Future<void>>[
          ref.read(communityPopularProvider.notifier).refresh(),
          ref.read(communityHotProvider.notifier).refresh(),
        ]);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: <Widget>[Text('加载失败：$e')],
        ),
        data: (CommunityPopularBundle data) {
          final List<HotShareDto> biliFallback =
              hotShares.asData?.value.shares ?? const <HotShareDto>[];
          final List<_RankRow> videos = data.videos.isNotEmpty
              ? data.videos
                  .map(
                    (HotTodayItemDto item) => _RankRow.fromHotToday(item),
                  )
                  .toList(growable: false)
              : biliFallback
                  .asMap()
                  .entries
                  .map(
                    (MapEntry<int, HotShareDto> e) => _RankRow(
                      rank: e.key + 1,
                      title: (e.value.linkTitle ?? '').trim().isEmpty
                          ? e.value.linkUrl
                          : e.value.linkTitle!.trim(),
                      coverUrl: e.value.linkCover ?? '',
                      openUrl: e.value.linkUrl,
                      learnerCount: e.value.shareCount,
                      kindLabel: 'B站',
                      contentType: 'video',
                      source: 'bilibili',
                      sampleLearners: const <String>[],
                    ),
                  )
                  .toList(growable: false);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              Text(
                '今日热门',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '看别人今天学过的视频与读过的书；学习人数越多，排名越前。',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: '今日视频', count: videos.length),
              const SizedBox(height: 8),
              if (videos.isEmpty)
                const _EmptyHint(text: '今天还没有人上报学过的视频')
              else
                for (final _RankRow row in videos) ...<Widget>[
                  _HotRankCard(
                    row: row,
                    onOpen: () => unawaited(_openRow(context, ref, row)),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 18),
              _SectionTitle(title: '今日阅读', count: data.books.length),
              const SizedBox(height: 8),
              if (data.books.isEmpty)
                const _EmptyHint(text: '今天还没有人上报读过的书籍 / 文章')
              else
                for (final HotTodayItemDto item in data.books) ...<Widget>[
                  _HotRankCard(
                    row: _RankRow.fromHotToday(item),
                    onOpen: () => unawaited(
                      _openRow(context, ref, _RankRow.fromHotToday(item)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 18),
              Text(
                '学习时长排名',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const _LeaderboardSnippet(),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _openRow(
  BuildContext context,
  WidgetRef ref,
  _RankRow row,
) async {
  final String url = row.openUrl.trim();
  if (url.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暂无打开链接')),
    );
    return;
  }
  if (row.source == 'bilibili' ||
      url.contains('bilibili.com') ||
      url.contains('b23.tv')) {
    await openBilibiliLearningOrImport(context, ref, watchUrl: url);
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('打开：$url')),
  );
}

class _RankRow {
  const _RankRow({
    required this.rank,
    required this.title,
    required this.coverUrl,
    required this.openUrl,
    required this.learnerCount,
    required this.kindLabel,
    required this.contentType,
    required this.source,
    required this.sampleLearners,
  });

  factory _RankRow.fromHotToday(HotTodayItemDto item) => _RankRow(
        rank: item.rank,
        title: item.title,
        coverUrl: item.coverUrl,
        openUrl: item.openUrl,
        learnerCount: item.learnerCount,
        kindLabel: item.isBook ? '阅读' : '视频',
        contentType: item.contentType,
        source: item.source,
        sampleLearners: item.sampleLearners,
      );

  final int rank;
  final String title;
  final String coverUrl;
  final String openUrl;
  final int learnerCount;
  final String kindLabel;
  final String contentType;
  final String source;
  final List<String> sampleLearners;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppDesignTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignTokens.appWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppDesignTokens.borderGray),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppDesignTokens.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HotRankCard extends StatelessWidget {
  const _HotRankCard({required this.row, required this.onOpen});

  final _RankRow row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 36,
                child: Text(
                  '${row.rank}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: row.rank <= 3 ? 22 : 18,
                    fontWeight: FontWeight.w900,
                    color: row.rank == 1
                        ? AppDesignTokens.orange
                        : row.rank <= 3
                            ? AppDesignTokens.brandGreen
                            : AppDesignTokens.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 54,
                  child: row.coverUrl.trim().isEmpty
                      ? ColoredBox(
                          color: AppDesignTokens.softGray,
                          child: Icon(
                            row.contentType == 'book'
                                ? Icons.menu_book_outlined
                                : Icons.play_circle_outline,
                            color: AppDesignTokens.textSecondary,
                          ),
                        )
                      : CoverImage(path: row.coverUrl, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      row.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      <String>[
                        row.kindLabel,
                        '${row.learnerCount} 人在学',
                        if (row.sampleLearners.isNotEmpty)
                          row.sampleLearners.take(2).join(' · '),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppDesignTokens.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderboardSnippet extends ConsumerStatefulWidget {
  const _LeaderboardSnippet();

  @override
  ConsumerState<_LeaderboardSnippet> createState() =>
      _LeaderboardSnippetState();
}

class _LeaderboardSnippetState extends ConsumerState<_LeaderboardSnippet> {
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
    return ref
        .read(acquireApiClientProvider)
        .communityLeaderboard(metric: 'study_today');
  }

  @override
  Widget build(BuildContext context) {
    final bool loggedIn = ref.watch(authSessionProvider).isLoggedIn;
    if (!loggedIn) {
      return const _EmptyHint(text: '登录后可查看今日学习时长排名');
    }
    return FutureBuilder<List<LeaderboardEntryDto>>(
      future: _future,
      builder: (
        BuildContext context,
        AsyncSnapshot<List<LeaderboardEntryDto>> snapshot,
      ) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _EmptyHint(text: '排行榜加载失败：${snapshot.error}');
        }
        final List<LeaderboardEntryDto> rows =
            snapshot.data ?? const <LeaderboardEntryDto>[];
        if (rows.isEmpty) {
          return const _EmptyHint(text: '今日还没有学习时长数据');
        }
        return Column(
          children: <Widget>[
            for (final LeaderboardEntryDto row in rows.take(8))
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
                    border: Border.all(color: AppDesignTokens.borderGray),
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${row.rank}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppDesignTokens.textPrimary,
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
                        _fmtSeconds(row.value),
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
    );
  }

  String _fmtSeconds(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final int m = seconds ~/ 60;
    if (m < 60) return '${m} 分钟';
    final int h = m ~/ 60;
    final int rm = m % 60;
    return rm == 0 ? '${h} 小时' : '${h}h ${rm}m';
  }
}
