import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/hub_ui.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../domain/cafe_adventure.dart';
import 'adventure_ui.dart';
import 'cafe_progress_provider.dart';
import 'community_adventure_tab.dart';
import 'community_feed_tab.dart';
import 'community_hot_tab.dart';
import 'community_me_tab.dart';
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
    ref.listen(
      authSessionProvider.select(
        (AuthSessionState session) => session.isLoggedIn,
      ),
      (bool? previous, bool next) {
        if (next && previous != next) unawaited(_refreshAll());
      },
    );

    final List<Widget> pages = <Widget>[
      const CommunityAdventureTab(),
      const CommunityHotTab(),
      const CommunityFeedTab(
        kinds: <String>{
          'learning_result',
          'method',
          'team_invite',
          'share_bilibili',
          'feedback',
        },
        emptyTitle: '发一条练习成果',
        emptyMeta: '仿写、跟读、闯关成果都会出现在这里',
        emptyHint: '练习区承接输出与反馈；闯关地图请看「冒险」。',
      ),
      const CommunityFeedTab(
        kinds: <String>{'question'},
        emptyTitle: '还没有英语问答',
        emptyMeta: '可贴台词时间戳或词条提问',
        emptyHint: '问答聚焦发音、词汇、语法与表达辨析。',
      ),
      const CommunityMeTab(),
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
        title: '学习社区',
        description: '冒险闯关 · 素材协作 · 输出互评',
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
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Cap hero so tabs + feed always get room above the bottom nav.
          final double heroMax = (constraints.maxHeight * 0.42).clamp(200.0, 320.0);
          return Column(
            children: <Widget>[
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: heroMax),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: AdventureHeroBanner(
                    edgeToEdge: true,
                    chapterTitle: '街角咖啡店',
                    chapterIndex: 1,
                    stageLabel: progress.stageLabel,
                    progressLabel: progress.progressLabel,
                    nodeCount: progress.nodeCount,
                    clearedCount: progress.clearedCount,
                    nodeLabels: kCafeLevels
                        .map((CafeLevel e) => e.title)
                        .toList(growable: false),
                    onContinue: _openAdventure,
                    partnerLabel:
                        loggedIn ? '同桌加分 · 打开学习桌' : '登录后可保存闯关进度',
                    onPartner: loggedIn ? _openDesk : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppDesignTokens.softGray,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: <Widget>[
                      for (final (int i, String label) in <(int, String)>[
                        (0, '冒险'),
                        (1, '素材'),
                        (2, '练习'),
                        (3, '问答'),
                        (4, '我的'),
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
                            meta: '登录后可保存进度、换装并分享闯关成果',
                            badge: '游客可练',
                            accent: AdventurePalette.pathAmber,
                            onPlay: _openAdventure,
                          ),
                          const SizedBox(height: 12),
                          HubSurface(
                            child: Text(
                              '游戏化：咖啡店闯关地图、同桌学习桌、积分换装扮都在「冒险」。'
                              '素材与问答是协作社区；不做连续打卡灌水榜。',
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
          );
        },
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
          boxShadow: selected
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            color: selected
                ? AppDesignTokens.brandGreenDark
                : AppDesignTokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
