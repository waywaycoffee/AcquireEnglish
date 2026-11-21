import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/hub_ui.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import 'community_feed_tab.dart';
import 'community_hot_tab.dart';
import 'community_me_tab.dart';
import 'community_provider.dart';
import 'community_social_screen.dart';
import 'exam_assets_tab.dart';
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
      const ExamAssetsTab(),
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
        emptyMeta: '仿写、跟读、模考成果都会出现在这里',
        emptyHint: '练习区承接输出与反馈；真题资料请看「考试」。',
      ),
      const CommunityFeedTab(
        kinds: <String>{'question'},
        emptyTitle: '还没有英语问答',
        emptyMeta: '可贴台词时间戳或词条提问',
        emptyHint: '问答聚焦发音、词汇、语法、考试题型辨析。',
      ),
      const CommunityMeTab(),
    ];

    return PadScaffold(
      currentDestination: AppNavDestination.discover,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '学习社区',
        description: '真题共享 · 素材协作 · 输出互评',
        actions: <Widget>[
          IconButton(
            tooltip: '同桌学习桌',
            icon: const Icon(Icons.table_restaurant_outlined),
            onPressed: loggedIn ? _openDesk : null,
          ),
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
            onPressed: loggedIn ? () => unawaited(_refreshAll()) : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
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
                    (0, '考试'),
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
                      HubSurface(
                        child: Text(
                          '登录后可浏览与上传考试真题资料（音频、脚本、词表），'
                          '以及同桌学习、练习互评与问答。',
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
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: selected
                  ? AppDesignTokens.textPrimary
                  : AppDesignTokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
