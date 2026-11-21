import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import 'adventure_ui.dart';
import 'cafe_progress_provider.dart';
import 'community_people_tab.dart';
import 'exploration_map_screen.dart';
import 'study_desk_screen.dart';

/// Groups MVP: theme rooms + cafe adventure + study desk as first activities.
class CommunityGroupsTab extends ConsumerWidget {
  const CommunityGroupsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CafeProgress progress =
        ref.watch(cafeProgressProvider).asData?.value ??
            const CafeProgress(
              profile: 'guest',
              completed: <int>{},
              weekLevels: <int>{},
            );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        const Text(
          '主题小组',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(
          '比大广场更高效：共同素材、轻量任务、同桌互评。完整小组实体将在下一期开放。',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppDesignTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        QuestFeedCard(
          title: '街角咖啡店 · 口语闯关小组',
          meta: '${progress.stageLabel} · ${progress.progressLabel}',
          badge: '公开可加入',
          accent: AdventurePalette.pathAmber,
          onPlay: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const ExplorationMapScreen(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        QuestFeedCard(
          title: '本周同桌 · 学习桌',
          meta: '1:1 一起练；换人不丢自己的闯关进度',
          badge: '申请加入',
          accent: AppDesignTokens.brandGreen,
          showPlayChevron: false,
          onPlay: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const StudyDeskScreen(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        QuestFeedCard(
          title: '找语伴 / 词汇 PK',
          meta: '按水平与兴趣匹配；防骚扰能力沿用现有拉黑举报',
          badge: '语伴',
          accent: const Color(0xFF5B8DEF),
          showPlayChevron: false,
          onPlay: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('找语伴')),
                body: const CommunityPeopleTab(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        QuestFeedCard(
          title: 'B1 美剧精听（预告）',
          meta: '下周共同素材 + 仿写任务 · 敬请期待',
          badge: '即将开放',
          accent: const Color(0xFF8E5AA8),
          showPlayChevron: false,
          onPlay: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('正式小组与组内任务将在下一期上线')),
            );
          },
        ),
      ],
    );
  }
}
