import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../avatar/presentation/avatar_preview.dart';
import '../../avatar/presentation/avatar_provider.dart';
import '../../avatar/presentation/avatar_shop_screen.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import 'adventure_ui.dart';
import 'community_leaderboard_tab.dart';
import 'community_social_screen.dart';
import 'study_play_screen.dart';

/// Personal asset homepage shell: 2D avatar + works / social / shop.
class CommunityMeTab extends ConsumerWidget {
  const CommunityMeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, String> loadout =
        ref.watch(avatarMeProvider).asData?.value.loadout ??
            const <String, String>{'body': 'body.cartoon1'};

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppDesignTokens.appWhite,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppDesignTokens.toyCardShadow,
          ),
          child: Row(
            children: <Widget>[
              AvatarPreview(loadout: loadout, height: 120),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '我的学习形象',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '公开主页展示你的素材、仿写与精选回答；词库与复习记录默认私有。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const AvatarShopScreen(),
                        ),
                      ),
                      child: const Text('换装 / 形象商店'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        QuestFeedCard(
          title: '我的分享与关注',
          meta: '收藏素材、关注流、消息与管理',
          badge: '社交',
          accent: const Color(0xFF5B8DEF),
          showPlayChevron: false,
          authorAvatar: loadout,
          onPlay: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const CommunitySocialScreen(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        QuestFeedCard(
          title: '一起练 · 积分与装扮',
          meta: '温和信用：用贡献换装扮，不做打卡段位',
          badge: '资产',
          accent: AppDesignTokens.brandGreen,
          showPlayChevron: false,
          authorAvatar: loadout,
          onPlay: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const StudyPlayScreen(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        QuestFeedCard(
          title: '作品集（预告）',
          meta: '短文、跟读录音、优质点评将汇总到这里',
          badge: '即将开放',
          accent: AdventurePalette.pathAmber,
          showPlayChevron: false,
          onPlay: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('作品集将在仿写 / 跟读投稿上线后开放')),
            );
          },
        ),
        const SizedBox(height: 12),
        QuestFeedCard(
          title: '学习榜（自愿）',
          meta: '可关闭上榜；不做打卡段位主叙事',
          badge: '可选',
          accent: const Color(0xFF4A5568),
          showPlayChevron: false,
          onPlay: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('学习榜')),
                body: const CommunityLeaderboardTab(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
