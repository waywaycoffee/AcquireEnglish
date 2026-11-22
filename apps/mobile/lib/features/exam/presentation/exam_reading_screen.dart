import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../membership/presentation/module_gate.dart';
import '../data/exam_reading_paper_store.dart';
import '../domain/exam_reading_paper.dart';
import '../domain/exam_reading_strategy.dart';

class ExamReadingScreen extends ConsumerWidget {
  const ExamReadingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExamReadingPaperState state = ref.watch(examReadingPaperProvider);
    return ModuleGate(
      moduleCode: 'exam',
      title: '考试模块',
      softBrowse: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('考试·阅读理解')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: <Widget>[
            Text(
              '带着问题找答案，而不是读完再想答案。',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              state.skillDone
                  ? '已学三步走技巧。可导入试卷，或用技巧/模考模式开练。'
                  : '建议先完成技巧课，再用示范卷走通「先题干→略读→定位」。',
              style: TextStyle(color: Theme.of(context).hintColor, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                if (!state.skillDone) {
                  context.push('/exam/reading/skill');
                  return;
                }
                context.push('/exam/reading/import');
              },
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(state.skillDone ? '导入试卷' : '先学技巧课'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push('/exam/reading/skill'),
              icon: const Icon(Icons.auto_stories_outlined),
              label: const Text('技巧课·三步走'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push(
                '/exam/reading/paper?paperId=${Uri.encodeComponent(kExamRcDemoPaper.id)}',
              ),
              icon: const Icon(Icons.school_outlined),
              label: const Text('示范卷 · 技巧/模考'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => context.push('/exam/session?skill=reading'),
              child: const Text('题库包阅读练习（原入口）'),
            ),
            TextButton(
              onPressed: () => context.push('/reading'),
              child: const Text('打开爱快阅读（泛读）'),
            ),
            const SizedBox(height: 20),
            Text(
              '五大题型',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final ExamRcQuestionType t in ExamRcQuestionType.values)
                  if (t != ExamRcQuestionType.unknown)
                    ActionChip(
                      label: Text(t.labelCn),
                      onPressed: () => context.push(
                        '/exam/reading/type?type=${t.storageValue}',
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '我的试卷',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            for (final ExamRcPaper paper in state.papers)
              Card(
                child: ListTile(
                  title: Text(paper.title),
                  subtitle: Text(
                    '${paper.questions.length} 题 · ${paper.source == 'demo' ? '示范' : (paper.source == 'drill' ? '专项' : '导入')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    '/exam/reading/paper?paperId=${Uri.encodeComponent(paper.id)}',
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/exam/reading/import'),
          icon: const Icon(Icons.add),
          label: const Text('导入'),
        ),
      ),
    );
  }
}
