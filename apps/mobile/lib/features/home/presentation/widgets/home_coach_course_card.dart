import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../daily_path/domain/course_plan.dart';
import '../../../daily_path/presentation/course_plan_provider.dart';
import '../../../daily_path/presentation/source_coach_lesson_preview.dart';

class HomeCoachCourseCard extends ConsumerWidget {
  const HomeCoachCourseCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CoursePlan? plan = ref.watch(coursePlanProvider).active;
    final CourseUnit? unit = plan?.units.isNotEmpty == true ? plan!.units.first : null;
    final List<String> lines = unit == null
        ? const <String>[]
        : <String>[...unit.shadowLines, ...unit.sentences]
            .where((String line) => line.trim().isNotEmpty)
            .toList(growable: false);
    final bool canStart = plan != null && unit != null && lines.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.record_voice_over_outlined),
              const SizedBox(width: 10),
              Text('AI 外教课', style: Theme.of(context).textTheme.titleLarge),
            ]),
            const SizedBox(height: 8),
            Text(canStart
                ? '用「${plan.title}」里的真实句子，完成六步口语课'
                : '从一节自我介绍体验课开始，练习如何用英语介绍自己。'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => SourceCoachLessonPreview(
                    isSample: !canStart,
                    sourceTitle: canStart ? plan.title : '内置口语体验课',
                    topic: canStart ? unit.topic : '初次见面与自我介绍',
                    sourceLines: canStart ? lines : const <String>[
                      'Hi, I’m Alex. Nice to meet you!',
                      'I live in Shanghai. How about you?',
                    ],
                    isVideo: canStart && (plan.type == CoursePlanType.video ||
                        plan.type == CoursePlanType.videoSeries),
                  ),
                ));
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(canStart ? '进入外教课' : '体验外教课'),
            ),
          ],
        ),
      ),
    );
  }
}
