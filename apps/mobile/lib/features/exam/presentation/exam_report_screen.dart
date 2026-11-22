import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/exam_error_book_store.dart';
import '../data/exam_progress_store.dart';
import '../domain/exam_profile.dart';
import 'exam_profile_provider.dart';

/// P2 learning report: practice counts + error skill mix.
class ExamReportScreen extends ConsumerWidget {
  const ExamReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamProfile profile = ref.watch(examProfileProvider);
    final String familyId = profile.familyId ?? '';
    final Map<String, int> progress =
        ref.watch(examProgressProvider).forFamily(familyId);
    final List<ExamErrorItem> errors =
        ref.read(examErrorBookProvider.notifier).forFamily(familyId);
    final Map<String, int> bySkill = <String, int>{};
    for (final ExamErrorItem e in errors) {
      bySkill[e.skill] = (bySkill[e.skill] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('学习报告')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            profile.family?.label ?? '未选考试',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            '练习 ${progress['practiced'] ?? 0} · 对 ${progress['correct'] ?? 0} · '
            '错 ${progress['wrong'] ?? 0} · 模考 ${progress['mocks'] ?? 0}',
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
          ),
          const SizedBox(height: 20),
          Text(
            '错题题型分布',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          if (bySkill.isEmpty)
            const Text('暂无错题，先完成专项或完形/听力练习。')
          else
            for (final MapEntry<String, int> e in bySkill.entries)
              ListTile(
                title: Text(e.key),
                trailing: Text('${e.value}'),
                onTap: () {
                  if (e.key == 'cloze') {
                    context.push('/exam/cloze');
                  } else if (e.key == 'grammar' || e.key == 'reading_guided') {
                    context.push('/exam/grammar');
                  } else {
                    context.push('/exam/session?skill=${e.key}');
                  }
                },
              ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => context.push('/exam/errorbook'),
            child: const Text('打开错题本'),
          ),
          OutlinedButton(
            onPressed: () => context.push('/writing'),
            child: const Text('用写作巩固语法错题'),
          ),
        ],
      ),
    );
  }
}
