import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../import_course/presentation/bilibili_import_sheet.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../settings/presentation/learning_preferences_screen.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import 'english_level_screen.dart';
import 'followed_creators_screen.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with WidgetsBindingObserver {
  bool _loading = false;
  bool _openingVideo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh({bool force = false}) async {
    if (_loading || !ref.read(authSessionProvider).isLoggedIn) return;
    setState(() => _loading = true);
    try {
      await ref.read(dailyFeedProvider.notifier).refresh(force: force);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(AcquireDailyFeedItemDto item) async {
    if (_openingVideo) return;
    _openingVideo = true;
    try {
      final String? episodeId = await showBilibiliImportSheet(
        context,
        ref,
        initialUrl: item.watchUrl,
        startImmediately: true,
      );
      if (!mounted || episodeId == null) return;
      await context.pushNamed<void>(
        SGRoute.player.name,
        pathParameters: <String, String>{'episodeId': episodeId},
        queryParameters: const <String, String>{'autoplay': '1'},
      );
      if (mounted) await _refresh(force: true);
    } finally {
      _openingVideo = false;
    }
  }

  Future<void> _followAuthor(AcquireDailyFeedItemDto item) async {
    final String? mid = item.authorId?.trim();
    if (mid == null || mid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法识别该 UP 主，请到「关注博主」粘贴空间链接。')),
      );
      return;
    }
    try {
      await ref.read(acquireApiClientProvider).followCreator(
            source: 'bilibili',
            creatorId: mid,
            displayName: item.author,
          );
      await ref.read(learningPreferencesProvider.notifier).pullRemote();
      await _refresh(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已关注 ${item.author.isEmpty ? mid : item.author}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('关注失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool loggedIn = ref.watch(authSessionProvider).isLoggedIn;
    ref.listen(
      authSessionProvider.select(
        (AuthSessionState session) => session.isLoggedIn,
      ),
      (bool? previous, bool next) {
        if (next && previous != next) unawaited(_refresh(force: true));
      },
    );
    final List<AcquireDailyFeedItemDto> feed = ref.watch(dailyFeedProvider);
    final AcquirePreferencesDto preferences = ref.watch(
      learningPreferencesProvider,
    );
    final List<AcquireDailyFeedItemDto> followed = feed
        .where((AcquireDailyFeedItemDto e) => e.isFollowed)
        .toList(growable: false);
    final List<AcquireDailyFeedItemDto> interest = feed
        .where((AcquireDailyFeedItemDto e) => !e.isFollowed)
        .toList(growable: false);

    return PadScaffold(
      currentDestination: AppNavDestination.discover,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '发现',
        description: '按兴趣与关注博主推荐，导入由你确认',
        actions: <Widget>[
          IconButton(
            tooltip: '刷新推荐',
            onPressed: _loading || !loggedIn
                ? null
                : () => _refresh(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ActionChip(
                  avatar: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('选择兴趣'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const LearningPreferencesScreen(),
                    ),
                  ),
                ),
                ActionChip(
                  label: Text('英语水平 · ${preferences.level}'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const EnglishLevelScreen(),
                    ),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(
                    '关注博主 · ${preferences.followedCreators.length}',
                  ),
                  onPressed: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const FollowedCreatorsScreen(),
                      ),
                    );
                    if (mounted) unawaited(_refresh(force: true));
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading) const LinearProgressIndicator(),
            if (!loggedIn)
              ListTile(
                title: const Text('登录后获取个人推荐'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(SGRoute.login.route),
              )
            else if (feed.isEmpty && !_loading)
              const ListTile(
                title: Text('暂无推荐视频'),
                subtitle: Text('可换一组兴趣、关注博主，或稍后刷新。点开后自行导入。'),
              )
            else ...<Widget>[
              if (followed.isNotEmpty) ...<Widget>[
                Text(
                  '关注的博主 · ${followed.length} 条',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text('来自你关注的 UP / 频道，点开后自行导入。'),
                const SizedBox(height: 8),
                for (final AcquireDailyFeedItemDto item in followed)
                  _FeedCard(
                    item: item,
                    onOpen: () => _open(item),
                    onFollow: null,
                  ),
                const SizedBox(height: 16),
              ],
              Text(
                '兴趣推荐 · ${interest.length} 条',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text('每类兴趣最多约 10 条；点开后开始导入并下载到本地。'),
              const SizedBox(height: 8),
              if (interest.isEmpty)
                const ListTile(
                  title: Text('暂无兴趣推荐'),
                  subtitle: Text('试试更换兴趣标签后刷新。'),
                )
              else
                for (final AcquireDailyFeedItemDto item in interest)
                  _FeedCard(
                    item: item,
                    onOpen: () => _open(item),
                    onFollow: item.authorId == null || item.authorId!.isEmpty
                        ? null
                        : () => _followAuthor(item),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({
    required this.item,
    required this.onOpen,
    this.onFollow,
  });

  final AcquireDailyFeedItemDto item;
  final VoidCallback onOpen;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    final bool verified = item.tags.contains('抽样英语原声');
    final bool pending = item.tags.contains('原声待确认');
    return Card(
      child: ListTile(
        leading: item.coverUrl == null
            ? const Icon(Icons.ondemand_video_rounded)
            : Image.network(
                item.coverUrl!,
                width: 64,
                height: 46,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.ondemand_video_rounded),
              ),
        title: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          <String>[
            'B站',
            if (item.isFollowed) '关注',
            if (verified) '抽样英语原声',
            if (pending) '原声待确认',
            if (item.author.isNotEmpty) item.author,
            if (item.durationSec != null)
              '${(item.durationSec! / 60).ceil()} 分钟',
          ].join(' · '),
        ),
        trailing: onFollow == null
            ? const Icon(Icons.download_outlined)
            : IconButton(
                tooltip: '关注该 UP',
                icon: const Icon(Icons.person_add_alt_1_outlined),
                onPressed: onFollow,
              ),
        onTap: onOpen,
      ),
    );
  }
}
