import 'package:flutter/material.dart';

import '../../library/presentation/library_mock_data.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../data/today_journey_store.dart';

/// Estimated watch minutes for a course / series (sum of episode lengths).
int libraryCourseDurationMinutes(LibraryCourseData course) {
  int total = 0;
  for (final LibraryEpisodeItem ep in course.episodes) {
    total += ep.durationMinutes.clamp(0, 24 * 60);
  }
  return total;
}

String libraryWatchPlanRoute(String watchUrl) => Uri(
      path: '/library',
      queryParameters: <String, String>{'watchUrl': watchUrl.trim()},
    ).toString();

String libraryCoursePlanRoute(String courseId) => Uri(
      path: '/library',
      queryParameters: <String, String>{'courseId': courseId.trim()},
    ).toString();

bool isVideoInTodayPlan({
  required String account,
  String? route,
  String? watchUrl,
  String? courseId,
}) {
  final List<JourneyActivity> items =
      TodayJourneyStore(account, DateTime.now())
          .selectedMaterials(TodayStudyTrack.video);
  if (items.isEmpty) return false;
  final String? normalizedRoute = route?.trim();
  final String? normalizedUrl = watchUrl?.trim();
  final String? normalizedCourse = courseId?.trim();
  for (final JourneyActivity item in items) {
    if (normalizedRoute != null &&
        normalizedRoute.isNotEmpty &&
        item.route == normalizedRoute) {
      return true;
    }
    if (normalizedCourse != null &&
        normalizedCourse.isNotEmpty &&
        item.route.contains('courseId=$normalizedCourse')) {
      return true;
    }
    if (normalizedUrl != null && normalizedUrl.isNotEmpty) {
      if (item.route.contains(Uri.encodeQueryComponent(normalizedUrl)) ||
          item.route.contains(normalizedUrl)) {
        return true;
      }
    }
  }
  return false;
}

/// Soft gate when today's video list would get long.
///
/// Triggers only when **after** adding, count **> 2** and total minutes **> 30**.
Future<bool> confirmLongVideoTodayPlan({
  required BuildContext context,
  required List<JourneyActivity> existing,
  required JourneyActivity candidate,
}) async {
  if (existing.any((JourneyActivity e) => e.route == candidate.route)) {
    return true;
  }
  final int nextCount = existing.length + 1;
  final int totalMinutes = existing.fold<int>(
        0,
        (int sum, JourneyActivity e) => sum + e.durationMinutes,
      ) +
      candidate.durationMinutes;
  if (nextCount <= 2 || totalMinutes <= 30) {
    return true;
  }
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      backgroundColor: AppDesignTokens.appWhite,
      title: Text(
        '确认加入今日计划？',
        style: TextStyle(color: AppDesignTokens.textPrimary),
      ),
      content: Text(
        '今天你预估视频学习的时间会比较长（约 $totalMinutes 分钟，共 $nextCount 个视频），确认加入吗？',
        style: TextStyle(color: AppDesignTokens.textSecondary, height: 1.4),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('确认加入'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<String> addVideoToTodayPlan({
  required BuildContext context,
  required String account,
  required JourneyActivity item,
}) async {
  final TodayJourneyStore store = TodayJourneyStore(account, DateTime.now());
  final List<JourneyActivity> existing =
      store.selectedMaterials(TodayStudyTrack.video);
  if (existing.any((JourneyActivity e) => e.route == item.route)) {
    return '已在今日计划里 · ${item.title}';
  }
  final bool ok = await confirmLongVideoTodayPlan(
    context: context,
    existing: existing,
    candidate: item,
  );
  if (!ok) return '';
  await store.addSelectedMaterial(TodayStudyTrack.video, item);
  return '已加入今日计划 · ${item.title}';
}

Future<String> addReadingToTodayPlan({
  required String account,
  required JourneyActivity item,
}) async {
  final TodayJourneyStore store = TodayJourneyStore(account, DateTime.now());
  final List<JourneyActivity> existing =
      store.selectedMaterials(TodayStudyTrack.reading);
  if (existing.any((JourneyActivity e) => e.route == item.route)) {
    return '已在今日计划里 · ${item.title}';
  }
  await store.addSelectedMaterial(TodayStudyTrack.reading, item);
  return '已加入今日计划 · ${item.title}';
}

/// Compact join / joined control for library browse cards.
class TodayPlanJoinChip extends StatelessWidget {
  const TodayPlanJoinChip({
    required this.joined,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final bool joined;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (joined) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppDesignTokens.brandGreen.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppDesignTokens.brandGreen),
        ),
        child: Text(
          '已加入',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppDesignTokens.brandGreen,
          ),
        ),
      );
    }
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppDesignTokens.brandGreen,
        foregroundColor: AppDesignTokens.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        busy ? '…' : '加入今日计划',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}
