import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../discovery/presentation/english_level_screen.dart';
import '../../discovery/presentation/followed_creators_screen.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../settings/presentation/learning_preferences_screen.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/hub_ui.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import 'community_feed_tab.dart';
import 'community_hot_tab.dart';
import 'community_leaderboard_tab.dart';
import 'community_people_tab.dart';
import 'community_provider.dart';
import 'study_desk_screen.dart';

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  int _tab = 0;

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

    final List<Widget> pages = <Widget>[
      const CommunityFeedTab(),
      const CommunityHotTab(),
      const CommunityPeopleTab(),
      const CommunityLeaderboardTab(),
    ];

    return PadScaffold(
      currentDestination: AppNavDestination.discover,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '社区',
        description: '分享 B 站视频，找搭子一起练',
        actions: <Widget>[
          TextButton.icon(
            icon: const Icon(Icons.groups_outlined),
            label: const Text('一起练'),
            onPressed: loggedIn
                ? () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const StudyDeskScreen(),
                    ),
                  )
                : null,
          ),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '一起学，更容易坚持',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        const Text('发现一个好表达，开始今天的学习。'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => context.go('/library'),
                    child: const Text('去学习'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.softGray,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: <Widget>[
                      for (final (int i, String label) in <(int, String)>[
                        (0, '动态'),
                        (1, '热门'),
                        (2, '搭子'),
                        (3, '排行'),
                      ])
                        Expanded(
                          child: _SegTab(
                            label: label,
                            selected: _tab == i,
                            onTap: () => setState(() => _tab = i),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      HubPill(
                        label: '找搭子',
                        background: const Color(0xFFE8F8D8),
                        foreground: AppDesignTokens.brandGreenDark,
                        onTap: () {
                          setState(() => _tab = 2);
                          unawaited(
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => const FollowedCreatorsScreen(),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      HubPill(
                        label: '英语水平 · ${preferences.level}',
                        background: const Color(0xFFFFF1D6),
                        foreground: AppDesignTokens.orange,
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const EnglishLevelScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      HubPill(
                        label: '兴趣标签',
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const LearningPreferencesScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      HubPill(
                        label: '关注博主 · ${preferences.followedCreators.length}',
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const FollowedCreatorsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: loggedIn
                ? IndexedStack(index: _tab, children: pages)
                : ListView(
                    padding: const EdgeInsets.all(24),
                    children: <Widget>[
                      HubSurface(
                        child: Text(
                          '登录后可看学习时长榜、兴趣相近的人，发帖吐槽，或分享你喜欢的 B 站视频与博主。',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SegTab extends StatelessWidget {
  const _SegTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppDesignTokens.appWhite : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            color: selected
                ? AppDesignTokens.textPrimary
                : AppDesignTokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
