import 'package:flutter/material.dart';

import '../../community/presentation/study_desk_screen.dart';
import '../../community/presentation/study_pk_screen.dart';
import '../../community/presentation/study_play_screen.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import 'navigation_destination.dart';

/// Top-level 对战 hub — real destinations already exist under community;
/// this screen is the bottom-nav entry that wires them together.
class BattleHubScreen extends StatelessWidget {
  const BattleHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PadScaffold(
      currentDestination: AppNavDestination.battle,
      showContinueLearning: false,
      topBar: const PadTopBar(
        title: '学习对战',
        description: '打卡比武与单词 PK',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Text(
            '和同桌比一比最近学的词，或者一起打卡大比武。没有同桌也能先寻找练习搭子。',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _BattleEntryCard(
            key: const Key('battle-hub-desk'),
            icon: Icons.groups_2_rounded,
            title: '寻找同桌',
            subtitle: '优先真人配对；无人可配时分配练习搭子。',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const StudyDeskScreen(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _BattleEntryCard(
            key: const Key('battle-hub-pk'),
            icon: Icons.flash_on_rounded,
            title: '近期单词 PK',
            subtitle: '约定题库，限时作答，看谁记得更牢。',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const StudyPkScreen(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _BattleEntryCard(
            key: const Key('battle-hub-play'),
            icon: Icons.emoji_events_outlined,
            title: '一起练 · 打卡与大比武',
            subtitle: '完成复习打卡，参与服务器大比武。',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const StudyPlayScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BattleEntryCard extends StatelessWidget {
  const _BattleEntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppDesignTokens.skyLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(icon, color: AppDesignTokens.primaryBlueDark),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppDesignTokens.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
