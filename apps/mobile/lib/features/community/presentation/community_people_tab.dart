import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/community_models.dart';
import 'adventure_ui.dart';
import 'community_provider.dart';

class CommunityPeopleTab extends ConsumerWidget {
  const CommunityPeopleTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CommunityPeopleBundle> async =
        ref.watch(communityPeopleProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(communityPeopleProvider.notifier).refresh(),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: <Widget>[Text('加载失败：$e')],
        ),
        data: (CommunityPeopleBundle data) {
          final CommunityProfileDto? profile = data.profile;
          final List<VocabPkDto> pendingForMe = data.challenges
              .where(
                (VocabPkDto c) => c.status == 'pending' && c.iAmOpponent,
              )
              .toList(growable: false);
          final bool looking = profile?.lookingForPartner ?? false;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '找人组队',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '一起练咖啡店，互相进步',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppDesignTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: <Widget>[
                      Switch(
                        value: looking,
                        activeThumbColor: Colors.white,
                        activeTrackColor: AppDesignTokens.brandGreen,
                        onChanged: (bool v) => unawaited(
                          ref
                              .read(communityPeopleProvider.notifier)
                              .setLookingForPartner(v),
                        ),
                      ),
                      Text(
                        looking ? '在找搭子' : '暂不找人',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: looking
                              ? AppDesignTokens.brandGreenDark
                              : AppDesignTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (profile != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '我的词汇量 · ${profile.vocabCount}'
                  '${profile.englishLevel == null ? '' : ' · ${profile.englishLevel}'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.textSecondary,
                  ),
                ),
              ],
              if (pendingForMe.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                const Text(
                  '待应战的词汇 PK',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 10),
                for (final VocabPkDto pk in pendingForMe) ...<Widget>[
                  AdventureBuddyCard(
                    name: pk.challengerName,
                    meta: '词汇 PK · 对方 ${pk.challengerVocab} 词',
                    actionLabel: '应战',
                    onAction: () => unawaited(_accept(context, ref, pk)),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 16),
              const Text(
                '兴趣相近的人',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 10),
              if (data.similar.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF6E8),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AdventurePalette.pathAmber.withValues(alpha: 0.55),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.table_restaurant_rounded,
                        size: 36,
                        color: AdventurePalette.pathAmberDeep,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        looking ? '正在寻找同桌…' : '打开「在找搭子」更容易被发现',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '暂无匹配。先设置兴趣标签与英语水平。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppDesignTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final bool wide = c.maxWidth > 360;
                    final List<Widget> cards = <Widget>[
                      for (final SimilarUserDto user in data.similar)
                        AdventureBuddyCard(
                          name: user.displayName,
                          meta: <String>[
                            if (user.englishLevel != null) user.englishLevel!,
                            '词汇 ${user.vocabCount}',
                            if (user.sharedTags.isNotEmpty)
                              '共同 ${user.sharedTags.take(2).join('、')}',
                            if (user.lookingForPartner) '想一起练咖啡店',
                          ].join(' · '),
                          actionLabel: '邀请同桌',
                          onAction: () =>
                              unawaited(_challenge(context, ref, user)),
                        ),
                    ];
                    if (!wide) {
                      return Column(
                        children: <Widget>[
                          for (int i = 0; i < cards.length; i++) ...<Widget>[
                            cards[i],
                            if (i < cards.length - 1) const SizedBox(height: 10),
                          ],
                        ],
                      );
                    }
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        for (final Widget card in cards)
                          SizedBox(
                            width: (c.maxWidth - 10) / 2,
                            child: card,
                          ),
                      ],
                    );
                  },
                ),
              if (data.challenges.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                const Text(
                  '最近 PK',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 10),
                for (final (int i, VocabPkDto pk)
                    in data.challenges.take(8).indexed)
                  AdventureRankRow(
                    rank: i + 1,
                    name: '${pk.challengerName} vs ${pk.opponentName}',
                    subtitle: pk.status == 'completed'
                        ? (pk.winnerId == null
                            ? '平局 · ${pk.challengerVocab}:${pk.opponentVocab}'
                            : '胜者 ${pk.winnerId == pk.challengerId ? pk.challengerName : pk.opponentName}'
                                ' · ${pk.challengerVocab}:${pk.opponentVocab}')
                        : '等待应战',
                    valueLabel: pk.status == 'completed' ? '完结' : '待战',
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _challenge(
    BuildContext context,
    WidgetRef ref,
    SimilarUserDto user,
  ) async {
    try {
      final VocabPkDto pk =
          await ref.read(communityPeopleProvider.notifier).challenge(user.userId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已向 ${pk.opponentName} 发起词汇 PK')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发起失败：$e')),
      );
    }
  }

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    VocabPkDto pk,
  ) async {
    try {
      final VocabPkDto result =
          await ref.read(communityPeopleProvider.notifier).accept(pk.id);
      if (!context.mounted) return;
      final String msg = result.winnerId == null
          ? '平局！${result.challengerVocab} : ${result.opponentVocab}'
          : (result.winnerId == result.opponentId
              ? '你赢了！${result.challengerVocab} : ${result.opponentVocab}'
              : '对方胜出 ${result.challengerVocab} : ${result.opponentVocab}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('应战失败：$e')),
      );
    }
  }
}
