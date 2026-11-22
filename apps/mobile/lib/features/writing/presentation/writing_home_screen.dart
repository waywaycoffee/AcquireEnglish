import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../exam/presentation/exam_profile_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/writing_draft_store.dart';
import '../domain/writing_models.dart';
import '../domain/writing_tracks.dart';

class WritingHomeScreen extends ConsumerWidget {
  const WritingHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<WritingDraft> drafts = ref.watch(writingDraftsProvider);
    final String? familyId = ref.watch(examProfileProvider).familyId;
    final WritingTrackId suggested = writingTrackForFamily(familyId);

    return Scaffold(
      appBar: AppBar(title: const Text('写作训练')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final WritingTrack t = writingTrackById(suggested);
          final String id = 'w_${DateTime.now().millisecondsSinceEpoch}';
          context.push(
            '/writing/$id'
            '?rubric=${Uri.encodeComponent(t.defaultRubric)}'
            '&track=${t.storageId}',
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('按当前考试开写'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: <Widget>[
          Text(
            '中考 / 高考 / 雅思 · 三级分轨',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '当前考试族建议：${writingTrackById(suggested).title}',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 14),
          for (final WritingTrack track in kWritingTracks)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    track.id == WritingTrackId.zhongkao
                        ? '1'
                        : track.id == WritingTrackId.gaokao
                            ? '2'
                            : '3',
                  ),
                ),
                title: Text(
                  track.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(track.oneLiner),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/writing/track/${track.storageId}'),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            '我的草稿',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          if (drafts.isEmpty)
            const Text(
              '还没有草稿。从上方选择一级后开始练习。',
              style: TextStyle(height: 1.45),
            )
          else
            for (final WritingDraft d in drafts)
              Card(
                child: ListTile(
                  title: Text(
                    d.title.isEmpty ? '未命名作文' : d.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${d.wordCount} 词 · '
                    '${DateTime.fromMillisecondsSinceEpoch(d.updatedAtMs)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppDesignTokens.textSecondary,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/writing/${d.id}'),
                  onLongPress: () =>
                      ref.read(writingDraftsProvider.notifier).remove(d.id),
                ),
              ),
        ],
      ),
    );
  }
}
