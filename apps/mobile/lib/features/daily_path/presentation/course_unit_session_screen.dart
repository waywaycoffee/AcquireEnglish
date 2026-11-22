import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repository/network_repository.dart';
import '../data/course_unit_progress.dart';
import '../domain/course_plan.dart';
import '../../player/domain/pronunciation_assessment.dart';
import '../../player/presentation/widgets/pronunciation_assessment_dialog.dart';
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

class CourseUnitSessionScreen extends ConsumerStatefulWidget {
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
  ConsumerState<CourseUnitSessionScreen> createState() =>
      _CourseUnitSessionScreenState();
}

class _CourseUnitSessionScreenState
    extends ConsumerState<CourseUnitSessionScreen> {
  CourseUnitProgress _progress = const CourseUnitProgress();
  bool _loadingQuiz = false;
  String? _quizError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final CourseUnitProgress next = await CourseUnitProgress.load(
      widget.courseId,
      widget.unitId,
    );
    if (mounted) setState(() => _progress = next);
  }

  @override
  Widget build(BuildContext context) {
    final String courseId = widget.courseId;
    final String unitId = widget.unitId;
    final String mode = widget.mode;
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
    final bool isVideo =
        resolvedPlan.type == CoursePlanType.video ||
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
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
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
              onPressed: () async {
                await _openVideo(context, resolvedPlan, resolvedUnit);
                await _reload();
              },
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
                child: Text(
                  s,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
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
              children: phrases
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
                  child: Text(
                    '${e.key + 1}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                title: Text(e.value, style: const TextStyle(height: 1.35)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await showPronunciationAssessmentDialog(
                  context,
                  target: PronunciationAssessmentTarget.wordOnly(
                    shadowLines.first,
                  ),
                  onResult: (PronunciationAssessmentResult result) async {
                    final int? score =
                        (result.suggestedScore ?? result.accuracy)?.round();
                    if (score == null) return;
                    await CourseUnitProgress.saveShadow(
                      courseId,
                      unitId,
                      score,
                    );
                    await _reload();
                  },
                );
              },
              icon: const Icon(Icons.mic_none),
              label: Text(
                _progress.shadowScore == null
                    ? '跟读首句并测评'
                    : '跟读得分 ${_progress.shadowScore} · 再练一次',
              ),
            ),
          ],
          if (!isVideo || resolvedPlan.params.practice.quiz) ...<Widget>[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                if (_loadingQuiz) return;
                List<CourseQuizItem> quiz = resolvedUnit.quiz;
                if (quiz.isEmpty && !isVideo) {
                  setState(() { _loadingQuiz = true; _quizError = null; });
                  try {
                    final response = await ref.read(networkRepositoryProvider.notifier)
                        .post<Map<String, dynamic>>('/api/course/quiz/reading',
                          data: <String, dynamic>{
                            'sentences': resolvedUnit.sentences,
                            'target_words': resolvedUnit.wordIds,
                          });
                    quiz = (response.data?['quiz'] as List<dynamic>? ?? <dynamic>[])
                        .map((dynamic item) => CourseQuizItem.fromJson(
                            Map<String, dynamic>.from(item as Map)))
                        .toList();
                  } catch (_) {
                    if (mounted) setState(() => _quizError = '暂时无法生成可核对原文的题目，请稍后重试');
                    return;
                  } finally {
                    if (mounted) setState(() => _loadingQuiz = false);
                  }
                }
                if (quiz.isEmpty && isVideo) quiz = _fallbackQuiz(resolvedUnit);
                if (quiz.isEmpty || !mounted) return;
                final CourseQuizResult? result = await Navigator.of(context)
                    .push(
                      MaterialPageRoute<CourseQuizResult>(
                        builder: (_) => CourseUnitQuizScreen(
                          topic: resolvedUnit.topic,
                          quiz: quiz,
                          sentences: resolvedUnit.sentences,
                        ),
                      ),
                    );
                if (result != null) {
                  await CourseUnitProgress.saveQuiz(
                    courseId,
                    unitId,
                    result.correct,
                    result.total,
                  );
                  await _reload();
                }
              },
              icon: const Icon(Icons.quiz_outlined),
              label: Text(
                _loadingQuiz ? '正在生成题目…' :
                (!isVideo ? '阅读理解 · 原文证据题' : '本节练习题'),
              ),
            ),
            if (_quizError != null) Text(_quizError!),
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
                      onConfirmedLearnerTurn: (String text) async {
                        if (!RegExp(r'[A-Za-z]').hasMatch(text)) return;
                        final CourseUnitProgress current = await CourseUnitProgress.load(
                            courseId, unitId);
                        await CourseUnitProgress.saveOralTurns(
                            courseId, unitId, current.oralTurns + 1);
                        await _reload();
                      },
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.record_voice_over_outlined),
              label: const Text('生成外教课'),
            ),
          ],
          const SizedBox(height: 28),
          if (isVideo)
            Text(
              '已播放 ${(_progress.watchedMs / 1000).floor()} 秒 / '
              '${(((resolvedUnit.endMs ?? 0) - (resolvedUnit.startMs ?? 0)) / 1000).floor()} 秒',
            ),
          if ((!isVideo || resolvedPlan.params.practice.quiz) && _progress.quizTotal != null)
            Text('答题 ${_progress.quizCorrect}/${_progress.quizTotal}'),
          if (resolvedPlan.params.practice.oral)
            Text('外教对话 ${_progress.oralTurns}/2 轮'),
          FilledButton(
            onPressed: _canComplete(resolvedPlan, resolvedUnit, shadowLines)
                ? () => completeTodayPathTaskAndContinue(
                    context: context,
                    ref: ref,
                    taskId: taskId,
                  )
                : null,
            child: const Text('完成本节 · 进入下一项'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _canComplete(resolvedPlan, resolvedUnit, shadowLines)
                ? () => completeTodayPathTaskAndContinue(
                    context: context,
                    ref: ref,
                    taskId: taskId,
                    autoNext: false,
                  )
                : null,
            child: const Text('完成本节并返回'),
          ),
          if (!_canComplete(resolvedPlan, resolvedUnit, shadowLines))
            const Text('完成本节内容与已开启的练习后，才能进入下一项。'),
        ],
      ),
    );
  }

  bool _canComplete(
    CoursePlan plan,
    CourseUnit unit,
    List<String> shadowLines,
  ) {
    final bool isReview = widget.mode == 'review';
    final bool isVideo = plan.type == CoursePlanType.video ||
        plan.type == CoursePlanType.videoSeries;
    // Spaced review of an already-watched video unit: open the clip (or any
    // shadow take) once, then allow finish — don't re-impose 80% + shadow≥60.
    if (isReview && isVideo) {
      return _progress.watchedMs > 0 || (_progress.shadowScore ?? 0) > 0;
    }
    if (isVideo &&
        unit.startMs != null &&
        unit.endMs != null &&
        unit.endMs! > unit.startMs!) {
      final int duration = unit.endMs! - unit.startMs!;
      if (_progress.watchedMs < duration * 0.8) return false;
    }
    if (shadowLines.isNotEmpty && (_progress.shadowScore ?? 0) < 60) return false;
    if ((plan.type == CoursePlanType.reading || plan.params.practice.quiz) &&
        (_progress.quizTotal == null || _progress.quizTotal == 0 ||
         (_progress.quizCorrect ?? 0) / _progress.quizTotal! < 0.75)) return false;
    if (plan.params.practice.oral && _progress.oralTurns < 2) return false;
    return true;
  }

  Future<void> _openVideo(
    BuildContext context,
    CoursePlan plan,
    CourseUnit unit,
  ) async {
    if (plan.type == CoursePlanType.videoSeries) {
      final int page = unit.episodePage ?? 1;
      final String episodeId =
          '${OralCoreSeries.kSeriesId}-${page.toString().padLeft(2, '0')}';
      await context.push(
        '/episodes/${Uri.encodeComponent(episodeId)}?autoplay=1'
        '&courseId=${Uri.encodeComponent(plan.courseId)}'
        '&unitId=${Uri.encodeComponent(unit.unitId)}'
        '&courseStartMs=0&courseEndMs=${unit.endMs ?? 0}',
      );
      return;
    }
    final String start = _formatClock(unit.startMs ?? 0);
    await context.push(
      '/episodes/${Uri.encodeComponent(plan.sourceId)}'
      '?startTime=${Uri.encodeComponent(start)}&autoplay=1'
      '&courseId=${Uri.encodeComponent(plan.courseId)}'
      '&unitId=${Uri.encodeComponent(unit.unitId)}'
      '&courseStartMs=${unit.startMs ?? 0}&courseEndMs=${unit.endMs ?? 0}',
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
