import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/today_task.dart';
import 'today_path_provider.dart';

/// Opens a today-path task. Course units go to the session shell;
/// vocab routes go to existing review session.
Future<void> openTodayPathTask(
  BuildContext context,
  WidgetRef ref,
  TodayTask task,
) async {
  await context.push(task.route);
}

/// After completing a task, mark done and optionally push the next item.
Future<void> completeTodayPathTaskAndContinue({
  required BuildContext context,
  required WidgetRef ref,
  required String taskId,
  bool autoNext = true,
}) async {
  await ref.read(todayPathProvider.notifier).markDone(taskId);
  if (!context.mounted) return;
  if (!autoNext) {
    if (context.canPop()) context.pop();
    return;
  }
  final TodayTask? next = ref.read(todayPathProvider).next;
  if (next == null) {
    if (context.canPop()) {
      context.pop();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('今日任务已全部完成')),
    );
    return;
  }
  // Replace current session with next.
  if (context.canPop()) {
    context.pop();
  }
  if (!context.mounted) return;
  await context.push(next.route);
}
