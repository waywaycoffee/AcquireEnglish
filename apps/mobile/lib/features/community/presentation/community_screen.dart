import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../discovery/presentation/english_level_screen.dart';
import '../../discovery/presentation/followed_creators_screen.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../settings/presentation/learning_preferences_screen.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import 'community_feed_tab.dart';
import 'community_hot_tab.dart';
import 'community_leaderboard_tab.dart';
import 'community_people_tab.dart';
import 'community_provider.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait(<Future<void>>[
      ref.read(communityFeedProvider.notifier).refresh(),
      ref.read(communityLeaderboardProvider.notifier).refresh(),
      ref.read(communityPeopleProvider.notifier).refresh(),
      ref.read(communityHotProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final bool loggedIn = ref.watch(authSessionProvider).isLoggedIn;
    final AcquirePreferencesDto preferences = ref.watch(
      learningPreferencesProvider,
    );
    ref.listen(
      authSessionProvider.select(
        (AuthSessionState session) => session.isLoggedIn,
      ),
      (bool? previous, bool next) {
        if (next && previous != next) unawaited(_refreshAll());
      },
    );

    return PadScaffold(
      currentDestination: AppNavDestination.discover,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '社区',
        description: '时长榜、找搭子、分享视频，一起练英语',
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: loggedIn ? () => unawaited(_refreshAll()) : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ActionChip(
                  avatar: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('兴趣标签'),
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
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const FollowedCreatorsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const <Tab>[
              Tab(text: '动态'),
              Tab(text: '榜单'),
              Tab(text: '找人'),
              Tab(text: '热门'),
            ],
          ),
          Expanded(
            child: loggedIn
                ? TabBarView(
                    controller: _tabs,
                    children: const <Widget>[
                      CommunityFeedTab(),
                      CommunityLeaderboardTab(),
                      CommunityPeopleTab(),
                      CommunityHotTab(),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: const <Widget>[
                      Text(
                        '登录后可看学习时长榜、兴趣相近的人，发帖吐槽或分享学习视频。',
                        style: TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
