import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../domain/cafe_adventure.dart';
import 'cafe_progress_provider.dart';
import 'community_feed_tab.dart';
import 'community_people_tab.dart';
import 'exploration_map_screen.dart';
import 'study_desk_screen.dart';
import 'study_play_screen.dart';

/// First-class gamification surface: cafe map, credits/play, desk, quest feed.
///
/// Must scroll as one surface — hero+tabs above leave little height on phones.
class CommunityAdventureTab extends ConsumerWidget {
  const CommunityAdventureTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CafeProgress progress =
        ref.watch(cafeProgressProvider).asData?.value ??
            const CafeProgress(
              profile: 'guest',
              completed: <int>{},
              weekLevels: <int>{},
            );

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '${progress.stageLabel} · ${progress.progressLabel}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _MiniGameCard(
                        title: '闯关地图',
                        meta: '${progress.clearedCount}/${progress.nodeCount}',
                        color: const Color(0xFFE8A838),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const ExplorationMapScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniGameCard(
                        title: '学习桌',
                        meta: '同桌加分',
                        color: AppDesignTokens.brandGreen,
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const StudyDeskScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniGameCard(
                        title: '一起练',
                        meta: '积分装扮',
                        color: const Color(0xFF5B8DEF),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const StudyPlayScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniGameCard(
                        title: '找语伴',
                        meta: '词汇 PK',
                        color: const Color(0xFF8E5AA8),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('找语伴')),
                              body: const CommunityPeopleTab(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '可开练任务',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverFillRemaining(
          hasScrollBody: true,
          child: CommunityFeedTab(
            kinds: <String>{
              'learning_result',
              'method',
              'team_invite',
            },
            emptyTitle: '试玩 · 街角咖啡店「看懂菜单」',
            emptyMeta: '通关后可发成果卡，邀人练同一关',
            emptyHint: '任务流优先展示可开练的成果卡与咖啡店关卡。',
          ),
        ),
      ],
    );
  }
}

class _MiniGameCard extends StatelessWidget {
  const _MiniGameCard({
    required this.title,
    required this.meta,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String meta;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
