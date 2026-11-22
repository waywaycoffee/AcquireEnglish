import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/presentation/player_mock_state.dart';
import '../domain/course_plan.dart';
import '../domain/reading_course_splitter.dart';
import '../domain/video_course_splitter.dart';
import 'course_plan_provider.dart';

Future<bool> showEnableCourseModeSheet({
  required BuildContext context,
  required WidgetRef ref,
  required CoursePlanType type,
  required String sourceId,
  required String title,
  String? plainText,
  List<PlayerSubtitleLine>? subtitleLines,
}) async {
  final CoursePlan? existing = ref.read(coursePlanProvider).active;
  if (existing != null && existing.sourceId != sourceId) {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('切换激活课程？'),
        content: Text(
          '当前已有激活课程「${existing.title}」。开启后将切换为本课（保留旧课进度，但首页只跟一门）。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('切换并开启'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
  }

  if (type == CoursePlanType.video) {
    final List<PlayerSubtitleLine> lines =
        subtitleLines ?? const <PlayerSubtitleLine>[];
    final bool hasEn =
        lines.any((PlayerSubtitleLine l) => l.english.trim().isNotEmpty);
    if (!hasEn) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缺少字幕，暂不支持课程化')),
        );
      }
      return false;
    }
  }

  if (!context.mounted) return false;

  final _EnableResult? result = await showModalBottomSheet<_EnableResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => _EnableCourseModeSheet(
      type: type,
      title: title,
    ),
  );
  if (result == null) return false;

  try {
    final List<CourseUnit> units;
    final int unitSize;
    if (type == CoursePlanType.video) {
      units = splitVideoIntoUnits(
        lines: subtitleLines!,
        dailyMinutes: result.dailyMinutes,
      );
      unitSize = result.dailyMinutes * 60;
    } else {
      units = splitReadingIntoUnits(
        plainText: plainText ?? '',
        dailySentences: result.dailySentences,
      );
      unitSize = result.dailySentences;
    }
    if (units.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法切分内容，请检查素材')),
        );
      }
      return false;
    }

    final CoursePlan plan = CoursePlan(
      courseId: '${type.name}_$sourceId',
      type: type,
      sourceId: sourceId,
      title: title,
      unitSize: unitSize,
      params: CoursePlanParams(
        dailyMinutes: result.dailyMinutes,
        dailySentences: result.dailySentences,
        practice: CoursePracticeParams(
          shadow: result.shadow,
          quiz: result.quiz,
          oral: result.oral,
        ),
      ),
      active: true,
      units: units,
      createdAt: DateTime.now(),
    );
    await ref.read(coursePlanProvider.notifier).activatePlan(plan);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已开启课程学习 · ${units.length} 个单元，回首页看今日路径',
          ),
        ),
      );
    }
    return true;
  } on VideoCourseSplitException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开启失败：$e')),
      );
    }
    return false;
  }
}

class _EnableResult {
  const _EnableResult({
    required this.dailyMinutes,
    required this.dailySentences,
    required this.shadow,
    required this.quiz,
    required this.oral,
  });

  final int dailyMinutes;
  final int dailySentences;
  final bool shadow;
  final bool quiz;
  final bool oral;
}

class _EnableCourseModeSheet extends StatefulWidget {
  const _EnableCourseModeSheet({
    required this.type,
    required this.title,
  });

  final CoursePlanType type;
  final String title;

  @override
  State<_EnableCourseModeSheet> createState() => _EnableCourseModeSheetState();
}

class _EnableCourseModeSheetState extends State<_EnableCourseModeSheet> {
  int _minutes = 10;
  int _sentences = 20;
  bool _shadow = true;
  bool _quiz = false;
  bool _oral = false;

  @override
  void initState() {
    super.initState();
    _quiz = widget.type == CoursePlanType.reading;
  }

  @override
  Widget build(BuildContext context) {
    final bool isVideo = widget.type == CoursePlanType.video;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '开启课程学习模式',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          if (isVideo) ...<Widget>[
            Text('每日时长', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <int>[5, 10, 15]
                  .map(
                    (int m) => ChoiceChip(
                      label: Text('$m 分钟'),
                      selected: _minutes == m,
                      onSelected: (_) => setState(() => _minutes = m),
                    ),
                  )
                  .toList(),
            ),
          ] else ...<Widget>[
            Text('每日句数', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <int>[10, 15, 20, 30]
                  .map(
                    (int n) => ChoiceChip(
                      label: Text('$n 句'),
                      selected: _sentences == n,
                      onSelected: (_) => setState(() => _sentences = n),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('跟读练习'),
            value: _shadow,
            onChanged: (bool v) => setState(() => _shadow = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('理解题（P0 可关）'),
            value: _quiz,
            onChanged: (bool v) => setState(() => _quiz = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('口语话题（P0 可关）'),
            value: _oral,
            onChanged: (bool v) => setState(() => _oral = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                context,
                _EnableResult(
                  dailyMinutes: _minutes,
                  dailySentences: _sentences,
                  shadow: _shadow,
                  quiz: _quiz,
                  oral: _oral,
                ),
              );
            },
            child: const Text('生成课程并激活'),
          ),
        ],
      ),
    );
  }
}
