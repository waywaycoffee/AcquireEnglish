import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../shared/presentation/media/cover_image.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../../utils/url_utils.dart';
import 'bilibili_import_sheet.dart';
import 'recommended_bilibili_provider.dart';

/// Curated Bilibili UPs + sample videos on the import / 视频学习 page.
class RecommendedBilibiliSection extends ConsumerWidget {
  const RecommendedBilibiliSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RecommendedBilibiliCreatorDto>> async =
        ref.watch(recommendedBilibiliCreatorsProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (List<RecommendedBilibiliCreatorDto> items) {
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '推荐关注 · B站发音博主',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '头像进空间；点视频即可导入学习。推荐片中英字幕已在云端缓存，导入后优先直用。',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ...items.map(
              (RecommendedBilibiliCreatorDto item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CreatorCard(item: item),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CreatorCard extends ConsumerWidget {
  const _CreatorCard({required this.item});

  final RecommendedBilibiliCreatorDto item;

  Future<void> _follow(BuildContext context, WidgetRef ref) async {
    final AuthSessionState auth = ref.read(authSessionProvider);
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录后即可关注博主')),
      );
      return;
    }
    try {
      await ref.read(acquireApiClientProvider).followCreator(
            source: 'bilibili',
            creatorId: item.creatorId,
            displayName: item.displayName,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已关注 ${item.displayName}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('关注失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RecommendedBilibiliVideoDto? video =
        item.videos.isEmpty ? null : item.videos.first;
    return Material(
      color: AppDesignTokens.appWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppDesignTokens.borderGray),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                InkWell(
                  onTap: item.profileUrl == null || item.profileUrl!.isEmpty
                      ? null
                      : () => unawaited(openUrl(Uri.parse(item.profileUrl!))),
                  borderRadius: BorderRadius.circular(999),
                  child: _Avatar(url: item.avatarUrl, name: item.displayName),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: item.profileUrl == null || item.profileUrl!.isEmpty
                        ? null
                        : () =>
                            unawaited(openUrl(Uri.parse(item.profileUrl!))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        if (item.blurb != null && item.blurb!.isNotEmpty)
                          Text(
                            item.blurb!,
                            maxLines: 2,
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
                ),
                TextButton(
                  onPressed: () => unawaited(_follow(context, ref)),
                  child: const Text('关注'),
                ),
              ],
            ),
            if (video != null) ...<Widget>[
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  unawaited(
                    showBilibiliImportSheet(
                      context,
                      ref,
                      initialUrl: video.watchUrl,
                    ),
                  );
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 96,
                        height: 64,
                        child: video.coverUrl == null || video.coverUrl!.isEmpty
                            ? const ColoredBox(
                                color: Color(0xFFFFE4EC),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Color(0xFFFB7299),
                                ),
                              )
                            : CoverImage(
                                path: video.coverUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const ColoredBox(
                                  color: Color(0xFFFFE4EC),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Color(0xFFFB7299),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            video.hasSharedSubs
                                ? '云端已备中英字幕 · 点此导入'
                                : '点此导入学习',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: video.hasSharedSubs
                                  ? AppDesignTokens.brandGreen
                                  : AppDesignTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.download_rounded, size: 20),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final String letter = name.isEmpty ? 'B' : String.fromCharCode(name.runes.first);
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFFFE4EC),
      child: ClipOval(
        child: SizedBox(
          width: 44,
          height: 44,
          child: url == null || url!.isEmpty
              ? Center(
                  child: Text(
                    letter,
                    style: const TextStyle(
                      color: Color(0xFFFB7299),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              : CoverImage(
                  path: url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(
                      letter,
                      style: const TextStyle(
                        color: Color(0xFFFB7299),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
