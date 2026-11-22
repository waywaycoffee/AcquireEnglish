import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/exam_reading_paper_store.dart';
import '../domain/exam_reading_paper.dart';
import '../domain/exam_reading_strategy.dart';

class ExamReadingPaperDetailScreen extends ConsumerWidget {
  const ExamReadingPaperDetailScreen({required this.paperId, super.key});

  final String paperId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(examReadingPaperProvider);
    final ExamRcPaper? resolved =
        ref.read(examReadingPaperProvider.notifier).byId(paperId);
    if (resolved == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('试卷')),
        body: const Center(child: Text('未找到试卷')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(resolved.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            '${resolved.questions.length} 题 · ${resolved.source == 'demo' ? '示范卷' : '导入卷'}',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 12),
          Text(
            resolved.passage,
            maxLines: 8,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final q in resolved.questions)
                Chip(label: Text(q.resolvedType.labelCn)),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.push(
              '/exam/reading/guided?paperId=${Uri.encodeComponent(resolved.id)}',
            ),
            icon: const Icon(Icons.school_outlined),
            label: const Text('技巧模式 · 三步走'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.push(
              '/exam/reading/mock?paperId=${Uri.encodeComponent(resolved.id)}',
            ),
            icon: const Icon(Icons.timer_outlined),
            label: const Text('限时模考'),
          ),
          if (resolved.source != 'demo') ...<Widget>[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => context.push(
                '/exam/reading/import?editId=${Uri.encodeComponent(resolved.id)}',
              ),
              child: const Text('校对题目'),
            ),
            TextButton(
              onPressed: () async {
                await ref
                    .read(examReadingPaperProvider.notifier)
                    .remove(resolved.id);
                if (context.mounted) context.pop();
              },
              child: const Text(
                '删除试卷',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
