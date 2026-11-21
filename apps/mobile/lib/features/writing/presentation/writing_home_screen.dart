import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/writing_draft_store.dart';
import '../domain/writing_models.dart';

class WritingHomeScreen extends ConsumerWidget {
  const WritingHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<WritingDraft> drafts = ref.watch(writingDraftsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('写作训练')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final String id = 'w_${DateTime.now().millisecondsSinceEpoch}';
          context.push('/writing/$id');
        },
        icon: const Icon(Icons.add),
        label: const Text('新作文'),
      ),
      body: drafts.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '还没有作文草稿。先写一篇通用英语短文，获取结构化批改；考试族评分模板将在下一阶段接入。',
                style: TextStyle(height: 1.5, fontWeight: FontWeight.w700),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: drafts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int i) {
                final WritingDraft d = drafts[i];
                return Card(
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
                );
              },
            ),
    );
  }
}
