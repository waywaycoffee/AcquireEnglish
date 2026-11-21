import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../import_course/presentation/bilibili_import_sheet.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../data/community_models.dart';
import 'adventure_ui.dart';
import 'community_provider.dart';

class CommunityHotTab extends ConsumerWidget {
  const CommunityHotTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CommunityHotBundle> async =
        ref.watch(communityHotProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(communityHotProvider.notifier).refresh(),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: <Widget>[Text('加载失败：$e')],
        ),
        data: (CommunityHotBundle data) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              const Text(
                '热门 · 视频任务',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                '大家正在练的 B 站片子，点进去就是一关任务',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              if (data.shares.isEmpty)
                QuestFeedCard(
                  title: '还没有人分享视频任务',
                  meta: '去「任务」贴一条你喜欢的 B 站链接吧',
                  badge: '等你来发',
                  accent: AdventurePalette.pathAmber,
                  onPlay: () {},
                )
              else
                for (final HotShareDto share in data.shares) ...<Widget>[
                  QuestFeedCard(
                    title: share.linkTitle?.isNotEmpty == true
                        ? share.linkTitle!
                        : 'B 站视频任务',
                    meta: share.latestBody?.isNotEmpty == true
                        ? '分享 ${share.shareCount} 次 · ${share.latestBody}'
                        : '分享 ${share.shareCount} 次 · ${share.shareCount} 人正在做',
                    badge: '热门',
                    accent: const Color(0xFFE67E22),
                    onPlay: () =>
                        unawaited(_openShare(context, ref, share.linkUrl)),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 12),
              const Text(
                '热门 · 博主关卡源',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                '关注后新视频会出现在首页推荐；导入仍需你确认',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              if (data.creators.isEmpty)
                Text(
                  '暂无聚合数据。去「关注博主」添加你喜欢的 B 站 UP 主吧。',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
                )
              else
                for (final HotCreatorDto creator in data.creators) ...<Widget>[
                  QuestFeedCard(
                    title: creator.displayName.isEmpty
                        ? creator.creatorId
                        : creator.displayName,
                    meta: 'B站 · ${creator.followerCount} 人关注',
                    badge: '关注',
                    accent: AppDesignTokens.brandGreen,
                    onPlay: () =>
                        unawaited(_followCreator(context, ref, creator)),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openShare(
    BuildContext context,
    WidgetRef ref,
    String url,
  ) async {
    final String? episodeId = await showBilibiliImportSheet(
      context,
      ref,
      initialUrl: url,
      startImmediately: true,
    );
    if (!context.mounted || episodeId == null) return;
    await context.pushNamed<void>(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': episodeId},
      queryParameters: const <String, String>{'autoplay': '1'},
    );
  }

  Future<void> _followCreator(
    BuildContext context,
    WidgetRef ref,
    HotCreatorDto creator,
  ) async {
    try {
      await ref.read(acquireApiClientProvider).followCreator(
            source: creator.source,
            creatorId: creator.creatorId,
            displayName: creator.displayName,
          );
      await ref.read(learningPreferencesProvider.notifier).pullRemote();
      await ref.read(communityHotProvider.notifier).refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已关注 ${creator.displayName.isEmpty ? creator.creatorId : creator.displayName}，首页会推荐其视频',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('关注失败：$e')),
      );
    }
  }
}
