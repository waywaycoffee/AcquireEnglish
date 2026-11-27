import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/url_utils.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../daily_path/presentation/today_plan_materials.dart';
import '../../shared/presentation/media/cover_image.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../data/bilibili_open_or_import.dart';
import 'recommended_bilibili_provider.dart';
import 'bilibili_collection_reservation.dart';

/// Curated Bilibili UPs + sample videos on the import / 视频学习 page.
class RecommendedBilibiliSection extends ConsumerWidget {
  const RecommendedBilibiliSection({
    super.key,
    this.onSelectVideo,
    this.isInTodayPlan,
  });

  final FutureOr<void> Function(String title, String url)? onSelectVideo;
  final bool Function(String watchUrl)? isInTodayPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RecommendedBilibiliCreatorDto>> async =
        ref.watch(recommendedBilibiliCreatorsProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              '正在加载推荐博主…',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
        ),
      ),
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
              onSelectVideo != null
                  ? '点「加入今日计划」可多选视频；已加入会显示状态。'
                  : '点封面或标题在线播放。合集可先看第一集，再预约字幕或下载全集。'
                      '推荐片中英字幕已在云端缓存。关注仅保存在本 App，不会同步到 B 站。',
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
                child: _CreatorCard(
                  item: item,
                  onSelectVideo: onSelectVideo,
                  isInTodayPlan: isInTodayPlan,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CreatorCard extends ConsumerStatefulWidget {
  const _CreatorCard({
    required this.item,
    required this.onSelectVideo,
    this.isInTodayPlan,
  });

  final FutureOr<void> Function(String title, String url)? onSelectVideo;
  final bool Function(String watchUrl)? isInTodayPlan;

  final RecommendedBilibiliCreatorDto item;

  @override
  ConsumerState<_CreatorCard> createState() => _CreatorCardState();
}

class _CreatorCardState extends ConsumerState<_CreatorCard> {
  bool _busy = false;
  bool _openingEpisode = false;

  bool _isFollowed(List<FollowedCreatorDto> followed) {
    final String mid = widget.item.creatorId.trim();
    if (mid.isEmpty) {
      return false;
    }
    return followed.any(
      (FollowedCreatorDto c) =>
          c.source == 'bilibili' && c.creatorId.trim() == mid,
    );
  }

  Future<void> _syncFollowed(List<FollowedCreatorDto> list) async {
    final AcquirePreferencesDto prefs = ref.read(learningPreferencesProvider);
    await ref.read(learningPreferencesProvider.notifier).applyLocal(
          prefs.copyWith(followedCreators: list),
        );
    ref.invalidate(followedCreatorsListProvider);
    await ref.read(dailyFeedProvider.notifier).refresh(force: true);
  }

  Future<void> _openOneEpisode(String watchUrl) async {
    if (_openingEpisode) return;
    _openingEpisode = true;
    try {
      await openBilibiliLearningOrImport(
        context,
        ref,
        watchUrl: watchUrl,
        startImportImmediately: true,
        waitForPlayerClose: true,
      );
    } finally {
      _openingEpisode = false;
    }
  }

  Future<void> _downloadFullCollection(String watchUrl) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await downloadBilibiliCollectionForWatchUrl(
        context,
        ref,
        watchUrl: watchUrl,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _toggleFollow(bool currentlyFollowed) async {
    if (_busy) {
      return;
    }
    final AuthSessionState auth = ref.read(authSessionProvider);
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录后即可关注博主')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final List<FollowedCreatorDto> list = currentlyFollowed
          ? await api.unfollowCreator(
              source: 'bilibili',
              creatorId: widget.item.creatorId,
            )
          : await api.followCreator(
              source: 'bilibili',
              creatorId: widget.item.creatorId,
              displayName: widget.item.displayName,
            );
      await _syncFollowed(list);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentlyFollowed
                ? '已取消关注 ${widget.item.displayName}'
                : '已关注 ${widget.item.displayName}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentlyFollowed ? '取消关注失败：$e' : '关注失败：$e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final RecommendedBilibiliCreatorDto item = widget.item;
    final RecommendedBilibiliVideoDto? video =
        item.videos.isEmpty ? null : item.videos.first;
    final AsyncValue<List<FollowedCreatorDto>> followedAsync =
        ref.watch(followedCreatorsListProvider);
    final List<FollowedCreatorDto> followed = followedAsync.maybeWhen(
      data: (List<FollowedCreatorDto> list) => list,
      orElse: () => ref.watch(learningPreferencesProvider).followedCreators,
    );
    final bool isFollowed = _isFollowed(followed);

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
                  onPressed: _busy
                      ? null
                      : () => unawaited(_toggleFollow(isFollowed)),
                  child: Text(
                    _busy
                        ? '…'
                        : (isFollowed ? '已关注' : '关注'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isFollowed
                          ? AppDesignTokens.textSecondary
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            if (video != null) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _busy
                          ? null
                          : () => unawaited(_openOneEpisode(video.watchUrl)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 96,
                              height: 64,
                              child: video.coverUrl == null ||
                                      video.coverUrl!.isEmpty
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
                                      errorBuilder: (_, __, ___) =>
                                          const ColoredBox(
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
                                  video.hasSharedSubs ? '有云端字幕 · 点此播放' : '点此在线播放',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppDesignTokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.onSelectVideo != null) ...<Widget>[
                    const SizedBox(width: 6),
                    TodayPlanJoinChip(
                      joined: widget.isInTodayPlan?.call(video.watchUrl) ?? false,
                      busy: _busy,
                      onPressed: () async {
                        final FutureOr<void> Function(String, String)? select =
                            widget.onSelectVideo;
                        if (select == null || _busy) return;
                        setState(() => _busy = true);
                        try {
                          await select(video.title, video.watchUrl);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                    ),
                  ],
                  if (widget.onSelectVideo == null) BilibiliCollectionReservation(
                    key: ValueKey(video.watchUrl),
                    source: video.watchUrl,
                  ),
                  if (widget.onSelectVideo == null) IconButton(
                    tooltip: '下载合集全部视频',
                    onPressed: _busy
                        ? null
                        : () => unawaited(
                              _downloadFullCollection(video.watchUrl),
                            ),
                    icon: const Icon(Icons.download_rounded),
                  ),
                ],
              ),
            ] else if (widget.onSelectVideo != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '暂无样片可加入今日计划',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
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
