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
    return PadScaffold(
      currentDestination: AppNavDestination.discover,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '发现',
        description: '按兴趣与英语水平挑选每日学习视频',
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
                title: Text('暂未找到通过英文原声抽样的视频'),
                subtitle: Text('正在筛选英文原声候选。可以稍后刷新，或换一组兴趣。'),
              )
            else ...<Widget>[
              Text(
                '今日推荐 · ${feed.length} 条',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text('点开视频后开始导入并下载到本地。'),
              const SizedBox(height: 8),
              for (final AcquireDailyFeedItemDto item in feed)
                Card(
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
                        '抽样英语原声',
                        if (item.author.isNotEmpty) item.author,
                        if (item.durationSec != null)
                          '${(item.durationSec! / 60).ceil()} 分钟',
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.download_outlined),
                    onTap: () => _open(item),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
