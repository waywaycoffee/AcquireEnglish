import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/exam_reading_paper_store.dart';
import '../domain/exam_reading_paper.dart';
import '../domain/exam_reading_strategy.dart';

class ExamReadingSkillCourseScreen extends ConsumerStatefulWidget {
  const ExamReadingSkillCourseScreen({super.key});

  @override
  ConsumerState<ExamReadingSkillCourseScreen> createState() =>
      _ExamReadingSkillCourseScreenState();
}

class _ExamReadingSkillCourseScreenState
    extends ConsumerState<ExamReadingSkillCourseScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final ExamRcSkillLesson lesson = kExamRcSkillLessons[_index];
    final bool last = _index >= kExamRcSkillLessons.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text('技巧课 ${_index + 1}/${kExamRcSkillLessons.length}'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LinearProgressIndicator(
              value: (_index + 1) / kExamRcSkillLessons.length,
            ),
            const SizedBox(height: 20),
            Text(
              lesson.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              lesson.body,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: <Widget>[
                  for (final String b in lesson.bullets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('·  ', style: TextStyle(fontSize: 18)),
                          Expanded(
                            child: Text(
                              b,
                              style: const TextStyle(fontSize: 15, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: <Widget>[
                if (_index > 0)
                  TextButton(
                    onPressed: () => setState(() => _index -= 1),
                    child: const Text('上一节'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    if (!last) {
                      setState(() => _index += 1);
                      return;
                    }
                    await ref
                        .read(examReadingPaperProvider.notifier)
                        .markSkillDone();
                    if (!context.mounted) return;
                    await context.push(
                      '/exam/reading/guided?paperId=${kExamRcDemoPaper.id}',
                    );
                    if (context.mounted) context.pop();
                  },
                  child: Text(last ? '去做示范卷' : '下一节'),
                ),
              ],
            ),
            if (last)
              TextButton(
                onPressed: () async {
                  await ref
                      .read(examReadingPaperProvider.notifier)
                      .markSkillDone();
                  if (context.mounted) context.pop();
                },
                child: const Text('先标记已学，稍后再练'),
              ),
          ],
        ),
      ),
    );
  }
}
