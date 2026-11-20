import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community_models.dart';
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

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('我在找英语学习搭子'),
                subtitle: const Text('开启后，兴趣相近的人更容易发现你'),
                value: profile?.lookingForPartner ?? false,
                onChanged: (bool v) => unawaited(
                  ref
                      .read(communityPeopleProvider.notifier)
                      .setLookingForPartner(v),
                ),
              ),
              if (profile != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '我的词汇量 · ${profile.vocabCount}'
                    '${profile.englishLevel == null ? '' : ' · ${profile.englishLevel}'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              if (pendingForMe.isNotEmpty) ...<Widget>[
                Text(
                  '待应战的词汇 PK',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final VocabPkDto pk in pendingForMe)
                  Card(
                    child: ListTile(
                      title: Text('${pk.challengerName} 向你发起 PK'),
                      subtitle: Text('对方词汇量 ${pk.challengerVocab}'),
                      trailing: FilledButton(
                        onPressed: () => unawaited(_accept(context, ref, pk)),
                        child: const Text('应战'),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              Text(
                '兴趣相近的人',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (data.similar.isEmpty)
                const Text('暂无匹配。先在上方设置兴趣标签与英语水平。')
              else
                for (final SimilarUserDto user in data.similar)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(user.displayName),
                    subtitle: Text(
                      [
                        if (user.englishLevel != null) user.englishLevel!,
                        if (user.sharedTags.isNotEmpty)
                          '共同兴趣 ${user.sharedTags.join('、')}',
                        '词汇 ${user.vocabCount}',
                        if (user.lookingForPartner) '在找搭子',
                      ].join(' · '),
                    ),
                    trailing: TextButton(
                      onPressed: () =>
                          unawaited(_challenge(context, ref, user)),
                      child: const Text('词汇 PK'),
                    ),
                  ),
              if (data.challenges.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                Text(
                  '最近 PK',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final VocabPkDto pk in data.challenges.take(8))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '${pk.challengerName} vs ${pk.opponentName}',
                    ),
                    subtitle: Text(
                      pk.status == 'completed'
                          ? (pk.winnerId == null
                              ? '平局 · ${pk.challengerVocab}:${pk.opponentVocab}'
                              : '胜者 ${pk.winnerId == pk.challengerId ? pk.challengerName : pk.opponentName}'
                                  ' · ${pk.challengerVocab}:${pk.opponentVocab}')
                          : '等待应战',
                    ),
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
