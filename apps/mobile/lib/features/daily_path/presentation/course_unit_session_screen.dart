import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/course_plan.dart';
import '../domain/oral_core_series.dart';
import 'course_plan_provider.dart';
import 'course_unit_quiz_screen.dart';
import 'daily_path_runner.dart';
import 'source_coach_lesson_preview.dart';

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

    final CoursePlan resolvedPlan = plan;
    final CourseUnit resolvedUnit = unit;
    final bool isReview = mode == 'review';
    final bool isVideo = resolvedPlan.type == CoursePlanType.video ||
        resolvedPlan.type == CoursePlanType.videoSeries;
    final bool isSeries = resolvedPlan.type == CoursePlanType.videoSeries;
    final String taskId = isReview
        ? 'course-review:${resolvedPlan.courseId}:${resolvedUnit.unitId}'
        : 'course-new:${resolvedPlan.courseId}:${resolvedUnit.unitId}';

    final List<String> shadowSource = resolvedUnit.shadowLines.isNotEmpty
        ? resolvedUnit.shadowLines
        : resolvedUnit.sentences;
    final List<String> shadowLines = resolvedPlan.params.practice.shadow
        ? shadowSource
            .where((String s) => s.trim().isNotEmpty)
            .take(isVideo ? 10 : 6)
            .toList(growable: false)
        : const <String>[];

    final List<String> phrases = resolvedUnit.targetPhrases.isNotEmpty
        ? resolvedUnit.targetPhrases
        : resolvedUnit.wordIds;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isReview
              ? '复习 · ${resolvedUnit.topic}'
              : '新课 · ${resolvedUnit.topic}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: <Widget>[
          Text(
            resolvedPlan.title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            resolvedUnit.topic,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (resolvedUnit.goal.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              resolvedUnit.goal,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 16),
          if (isVideo) ...<Widget>[
            if (!isSeries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timelapse),
                title: Text(
                  '${_formatClock(resolvedUnit.startMs ?? 0)} – ${_formatClock(resolvedUnit.endMs ?? 0)}',
                ),
                subtitle: const Text('按字幕区间播放，不切半句'),
              ),
            if (isSeries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.videocam_outlined),
                title: Text(
                  'B站 · ${resolvedUnit.episodeBvid ?? 'BV1CS4y1v7sQ'}'
                  ' P${resolvedUnit.episodePage ?? 1}',
                ),
                subtitle: const Text('整集播放（官方课一集一课）'),
              ),
            FilledButton.icon(
              onPressed: () =>
                  _openVideo(context, resolvedPlan, resolvedUnit),
              icon: const Icon(Icons.play_arrow),
              label: Text(isSeries ? '播放本集视频' : '播放本节区间'),
            ),
          ] else ...<Widget>[
            Text(
              '阅读块 · ${resolvedUnit.sentences.length} 句',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...resolvedUnit.sentences.map(
              (String s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(s, style: const TextStyle(fontSize: 16, height: 1.5)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                context.push(
                  '/reading/${Uri.encodeComponent(resolvedPlan.sourceId)}',
                );
              },
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('在阅读器中打开全文'),
            ),
          ],
          if (phrases.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text('本节句型', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  phrases.map((String w) => Chip(label: Text(w))).toList(),
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
                  child: Text(
                    '${e.key + 1}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                title: Text(e.value, style: const TextStyle(height: 1.35)),
              ),
            ),
          ],
          if (resolvedPlan.params.practice.quiz) ...<Widget>[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                final List<CourseQuizItem> quiz =
                    resolvedUnit.quiz.isNotEmpty
                        ? resolvedUnit.quiz
                        : _fallbackQuiz(resolvedUnit);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CourseUnitQuizScreen(
                      topic: resolvedUnit.topic,
                      quiz: quiz,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.quiz_outlined),
              label: Text(
                resolvedUnit.quiz.isEmpty
                    ? '练习题（规则题）'
                    : 'AI / 预置练习题',
              ),
            ),
          ],
          if (resolvedPlan.params.practice.oral) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                final List<String> sourceLines = <String>[
                  ...resolvedUnit.shadowLines,
                  ...resolvedUnit.sentences,
                ].where((String s) => s.trim().isNotEmpty).toList();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SourceCoachLessonPreview(
                      sourceTitle: resolvedPlan.title,
                      topic: resolvedUnit.topic,
                      sourceLines: sourceLines,
                      isVideo: isVideo,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.record_voice_over_outlined),
              label: const Text('生成外教课'),
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

  void _openVideo(BuildContext context, CoursePlan plan, CourseUnit unit) {
    if (plan.type == CoursePlanType.videoSeries) {
      final int page = unit.episodePage ?? 1;
      final String episodeId =
          '${OralCoreSeries.kSeriesId}-${page.toString().padLeft(2, '0')}';
      context.push(
        '/episodes/${Uri.encodeComponent(episodeId)}?autoplay=1',
      );
      return;
    }
    final String start = _formatClock(unit.startMs ?? 0);
    context.push(
      '/episodes/${Uri.encodeComponent(plan.sourceId)}'
      '?startTime=${Uri.encodeComponent(start)}&autoplay=1',
    );
  }

  List<CourseQuizItem> _fallbackQuiz(CourseUnit unit) {
    final String phrase = unit.targetPhrases.isNotEmpty
        ? unit.targetPhrases.first
        : (unit.sentences.isNotEmpty ? unit.sentences.first : unit.topic);
    return <CourseQuizItem>[
      CourseQuizItem(
        type: 'mcq',
        stem: '本课主题是？',
        options: <String>[unit.topic, '无关主题 A', '无关主题 B', '无关主题 C'],
        answer: 0,
      ),
      CourseQuizItem(
        type: 'mcq',
        stem: '下列哪一句更贴近本课？',
        options: <String>[phrase, 'Hello, goodbye.', 'See you never.', 'Ok.'],
        answer: 0,
      ),
      CourseQuizItem(
        type: 'mcq',
        stem: '学习目标更接近？',
        options: <String>[
          unit.goal.isNotEmpty ? unit.goal : '掌握本课情景句型',
          '只背单词表',
          '只看中文翻译',
          '不开口',
        ],
        answer: 0,
      ),
    ];
  }
}
