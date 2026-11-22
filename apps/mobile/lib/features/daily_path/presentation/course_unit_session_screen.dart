import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/course_plan.dart';
import 'course_plan_provider.dart';
import 'daily_path_runner.dart';

String _formatClock(int ms) {
  final int totalSec = (ms / 1000).floor().clamp(0, 24 * 3600);
  final int m = totalSec ~/ 60;
  final int s = totalSec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class CourseUnitSessionScreen extends ConsumerWidget {
  const CourseUnitSessionScreen({
    super.key,
    required this.courseId,
    required this.unitId,
    this.mode = 'new',
  });

  final String courseId;
  final String unitId;
  final String mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CoursePlanCatalog catalog = ref.watch(coursePlanProvider);
    CoursePlan? plan;
    for (final CoursePlan p in catalog.plans) {
      if (p.courseId == courseId) {
        plan = p;
        break;
      }
    }
    plan ??= catalog.active;
    final CourseUnit? unit = plan?.unitById(unitId);

    if (plan == null || unit == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('课程单元')),
        body: const Center(child: Text('找不到该单元，请回首页刷新路径')),
      );
    }

    final bool isReview = mode == 'review';
    final bool isVideo = plan.type == CoursePlanType.video;
    final String taskId = isReview
        ? 'course-review:${plan.courseId}:${unit.unitId}'
        : 'course-new:${plan.courseId}:${unit.unitId}';

    final List<String> shadowLines = plan.params.practice.shadow
        ? unit.sentences
            .where((String s) => s.trim().isNotEmpty)
            .take(isVideo ? 8 : 6)
            .toList(growable: false)
        : const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(isReview ? '复习 · ${unit.unitId}' : '新课 · ${unit.unitId}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: <Widget>[
          Text(
            plan.title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            unit.topic,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 16),
          if (isVideo) ...<Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timelapse),
              title: Text(
                '${_formatClock(unit.startMs ?? 0)} – ${_formatClock(unit.endMs ?? 0)}',
              ),
              subtitle: const Text('按字幕区间播放，不切半句'),
            ),
            FilledButton.icon(
              onPressed: () {
                final String start =
                    _formatClock(unit.startMs ?? 0);
                context.push(
                  '/episodes/${Uri.encodeComponent(plan!.sourceId)}'
                  '?startTime=${Uri.encodeComponent(start)}&autoplay=1',
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('播放本节区间'),
            ),
          ] else ...<Widget>[
            Text(
              '阅读块 · ${unit.sentences.length} 句',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...unit.sentences.map(
              (String s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(s, style: const TextStyle(fontSize: 16, height: 1.5)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                context.push(
                  '/reading/${Uri.encodeComponent(plan!.sourceId)}',
                );
              },
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('在阅读器中打开全文'),
            ),
          ],
          if (unit.wordIds.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text('本节生词', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: unit.wordIds
                  .map((String w) => Chip(label: Text(w)))
                  .toList(),
            ),
          ],
          if (shadowLines.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text('跟读抽句', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...shadowLines.asMap().entries.map(
              (MapEntry<int, String> e) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 12,
                  child: Text('${e.key + 1}', style: const TextStyle(fontSize: 11)),
                ),
                title: Text(e.value, style: const TextStyle(height: 1.35)),
              ),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => completeTodayPathTaskAndContinue(
              context: context,
              ref: ref,
              taskId: taskId,
            ),
            child: const Text('完成本节 · 进入下一项'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => completeTodayPathTaskAndContinue(
              context: context,
              ref: ref,
              taskId: taskId,
              autoNext: false,
            ),
            child: const Text('完成本节并返回'),
          ),
        ],
      ),
    );
  }
}
