import 'dart:async';

import 'package:flutter/material.dart';
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
import 'adventure_ui.dart';
import 'cafe_progress_provider.dart';
import 'community_feed_tab.dart';
import 'community_hot_tab.dart';
import 'community_leaderboard_tab.dart';
import 'community_people_tab.dart';
import 'community_provider.dart';
import 'community_social_screen.dart';
import 'exploration_map_screen.dart';
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

  void _openAdventure() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const ExplorationMapScreen(),
      ),
    );
  }

  void _openDesk() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const StudyDeskScreen(),
      ),
    );
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
    final CafeProgress progress =
        ref.watch(cafeProgressProvider).asData?.value ??
            const CafeProgress(
              profile: 'guest',
              completed: <int>{},
              weekLevels: <int>{},
            );

    return PadScaffold(
      currentDestination: AppNavDestination.discover,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '冒险广场',
        description: '单人闯关为主 · 同桌加分为辅',
        actions: <Widget>[
          IconButton(
            tooltip: '消息、收藏与管理',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: loggedIn
                ? () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const CommunitySocialScreen(),
                      ),
                    )
                : null,
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: loggedIn
                ? () async {
                    await _refreshAll();
                    await ref.read(cafeProgressProvider.notifier).refresh();
                  }
                : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: AdventureHeroBanner(
              chapterTitle: '街角咖啡店',
              stageLabel: progress.stageLabel,
              progressLabel: progress.progressLabel,
              nodeCount: progress.nodeCount,
              clearedCount: progress.clearedCount,
              onContinue: _openAdventure,
              partnerLabel: loggedIn
                  ? progress.partnerLabel(hasPeer: progress.peerWeekCount != null)
                  : '登录后可邀同桌加分',
              onPartner: loggedIn ? _openDesk : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                        (0, '任务'),
                        (1, '热门'),
                        (2, '找人'),
                        (3, '榜'),
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
                        label: '打开地图',
                        background: AdventurePalette.pathAmber,
                        foreground: const Color(0xFF3A2A00),
                        onTap: _openAdventure,
                      ),
                      const SizedBox(width: 8),
                      HubPill(
                        label: '学习桌',
                        background: const Color(0xFFE8F8D8),
                        foreground: AppDesignTokens.brandGreenDark,
                        onTap: loggedIn ? _openDesk : null,
                      ),
                      const SizedBox(width: 8),
                      HubPill(
                        label: '水平 · ${preferences.level}',
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
                        label: '兴趣',
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const LearningPreferencesScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      HubPill(
                        label: '博主 · ${preferences.followedCreators.length}',
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
                      QuestFeedCard(
                        title: '试玩 · 街角咖啡店「看懂菜单」',
                        meta: '登录后可保存进度并分享成果卡',
                        badge: '游客可练',
                        accent: AdventurePalette.pathAmber,
                        onPlay: _openAdventure,
                      ),
                      const SizedBox(height: 12),
                      HubSurface(
                        child: Text(
                          '单人冒险进度永远属于你。同桌只是本周加分，换人不丢关卡。',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            fontWeight: FontWeight.w700,
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
