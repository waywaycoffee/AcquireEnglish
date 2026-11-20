import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../import_course/presentation/bilibili_import_sheet.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../data/community_models.dart';
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
              Text(
                '大家喜欢的 B 站视频',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '欢迎在「动态」分享你觉得好听的片子，帮助同学发现好内容。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (data.shares.isEmpty)
                const Text('还没有人分享。去「动态」贴一条你喜欢的 B 站链接吧。')
              else
                for (final HotShareDto share in data.shares)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      share.linkTitle?.isNotEmpty == true
                          ? share.linkTitle!
                          : share.linkUrl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        '分享 ${share.shareCount} 次',
                        if (share.latestBody?.isNotEmpty == true)
                          share.latestBody!,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      onPressed: () =>
                          unawaited(_openShare(context, ref, share.linkUrl)),
                      child: const Text('我也想学'),
                    ),
                  ),
              const SizedBox(height: 24),
              Text(
                '大家喜欢的 B 站博主',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '关注后新视频会出现在首页推荐；导入仍需你确认。YouTube 博主因政策原因暂时不可关注。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (data.creators.isEmpty)
                const Text('暂无聚合数据。去「关注博主」添加你喜欢的 B 站 UP 主吧。')
              else
                for (final HotCreatorDto creator in data.creators)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(
                      creator.displayName.isEmpty
                          ? creator.creatorId
                          : creator.displayName,
                    ),
                    subtitle: Text(
                      'B站 · ${creator.followerCount} 人关注',
                    ),
                    trailing: TextButton(
                      onPressed: () =>
                          unawaited(_followCreator(context, ref, creator)),
                      child: const Text('关注'),
                    ),
                  ),
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
