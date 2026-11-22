import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/today_task.dart';
import 'daily_path_runner.dart';
import 'today_path_provider.dart';

class TodayPathCard extends ConsumerWidget {
  const TodayPathCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TodayPathState path = ref.watch(todayPathProvider);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = dark ? const Color(0xFFB7D894) : const Color(0xFF284F39);
    final Color ink = dark ? const Color(0xFFEEEEEE) : const Color(0xFF292929);
    final Color muted = dark ? const Color(0xFFAAAAAA) : const Color(0xFF737373);
    final Color surface = dark ? const Color(0xFF242424) : Colors.white;

    if (path.status == TodayPathStatus.idle && !path.hasActiveCourse) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '今日课程路径',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在视频或阅读页点「开启课程学习模式」，会把长素材拆成每日单元，并与词书复习合成一条任务链。',
              style: TextStyle(fontSize: 13, color: muted, height: 1.4),
            ),
            if (path.tasks.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _taskPreview(context, ref, path, accent, ink, muted),
              const SizedBox(height: 12),
              _primaryButton(context, ref, path, accent, dark),
            ],
          ],
        ),
      );
    }

    final String statusLabel = switch (path.status) {
      TodayPathStatus.pending => '待开始',
      TodayPathStatus.inProgress => '进行中',
      TodayPathStatus.completed => '今日已完成',
      TodayPathStatus.overdue => '有逾期',
      TodayPathStatus.ended => '已结束',
      TodayPathStatus.idle => '待开启',
    };

    final String cta = switch (path.status) {
      TodayPathStatus.completed => '今日已完成',
      TodayPathStatus.inProgress => '继续',
      TodayPathStatus.overdue => '开始逾期复习',
      TodayPathStatus.ended => '查看',
      _ => path.doneCount > 0 ? '学下一节' : '开始',
    };

    final double progress =
        path.total == 0 ? 0 : path.doneCount / path.total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  path.courseTitle.isEmpty ? '今日课程路径' : path.courseTitle,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            path.total == 0
                ? '今日暂无任务'
                : '今日共 ${path.total} 项 · 已完成 ${path.doneCount}',
            style: TextStyle(fontSize: 13, color: muted),
          ),
          if (path.total > 0) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 6,
                color: accent,
                backgroundColor:
                    dark ? const Color(0xFF444444) : const Color(0xFFE5E5E5),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _primaryButton(
            context,
            ref,
            path,
            accent,
            dark,
            label: cta,
            enabled: path.next != null,
          ),
          if (path.tasks.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            _taskPreview(context, ref, path, accent, ink, muted),
          ],
        ],
      ),
    );
  }

  Widget _primaryButton(
    BuildContext context,
    WidgetRef ref,
    TodayPathState path,
    Color accent,
    bool dark, {
    String? label,
    bool enabled = true,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: dark ? const Color(0xFF203A27) : Colors.white,
          disabledBackgroundColor: accent.withValues(alpha: 0.35),
        ),
        onPressed: !enabled || path.next == null
            ? null
            : () => openTodayPathTask(context, ref, path.next!),
        child: Text(label ?? '开始'),
      ),
    );
  }

  Widget _taskPreview(
    BuildContext context,
    WidgetRef ref,
    TodayPathState path,
    Color accent,
    Color ink,
    Color muted,
  ) {
    final List<TodayTask> show = path.tasks.take(4).toList(growable: false);
    final int more = path.tasks.length - show.length;
    return Column(
      children: <Widget>[
        ...show.map((TodayTask t) {
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              t.doneToday
                  ? Icons.check_circle
                  : (t.overdue
                      ? Icons.warning_amber_rounded
                      : Icons.radio_button_unchecked),
              color: t.doneToday
                  ? accent
                  : (t.overdue ? Colors.orange : muted),
              size: 22,
            ),
            title: Text(
              t.title,
              style: TextStyle(
                fontSize: 14,
                color: ink,
                decoration:
                    t.doneToday ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: t.subtitle.isEmpty
                ? null
                : Text(t.subtitle, style: TextStyle(fontSize: 12, color: muted)),
            onTap: t.doneToday
                ? null
                : () => openTodayPathTask(context, ref, t),
          );
        }),
        if (more > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '还有 $more 项',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
      ],
    );
  }
}
