import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../subtitle_completion/subtitle_completion_enqueue.dart';
import 'bilibili_episode_prepare.dart';
import 'bilibili_import_service.dart';
import 'bilibili_multipage.dart';

final Set<String> _inFlightCourseIds = <String>{};

class BilibiliCollectionDownloadProgress {
  const BilibiliCollectionDownloadProgress({
    required this.courseId,
    required this.message,
    required this.progress,
    this.done = false,
    this.successCount = 0,
    this.failedCount = 0,
  });

  final String courseId;
  final String message;
  final double progress;
  final bool done;
  final int successCount;
  final int failedCount;
}

class BilibiliCollectionDownloadProgressNotifier
    extends Notifier<BilibiliCollectionDownloadProgress?> {
  @override
  BilibiliCollectionDownloadProgress? build() => null;

  void update(BilibiliCollectionDownloadProgress? next) {
    state = next;
  }
}

final NotifierProvider<
  BilibiliCollectionDownloadProgressNotifier,
  BilibiliCollectionDownloadProgress?
>
bilibiliCollectionDownloadProgressProvider =
    NotifierProvider<
      BilibiliCollectionDownloadProgressNotifier,
      BilibiliCollectionDownloadProgress?
    >(BilibiliCollectionDownloadProgressNotifier.new);

bool _isMultiEpisodeBilibili(LibraryCourseData course) {
  if (course.episodes.length <= 1) {
    return false;
  }
  return course.category == 'bilibili' ||
      course.sourceLabel.toLowerCase().contains('bilibili') ||
      course.id.startsWith('bilibili-');
}

bool isBilibiliCollectionDownloadInFlight(String courseId) {
  return _inFlightCourseIds.contains(courseId);
}

/// Download remaining 合集/分P episodes that still only have a watch URL.
Future<void> downloadRemainingBilibiliEpisodes({
  required LibraryCatalogNotifier catalog,
  required List<LibraryCourseData> Function() readCourses,
  required String courseId,
  required BilibiliImportService service,
  void Function(String message, double? progress)? onProgress,
  BilibiliCollectionDownloadProgressNotifier? progressNotifier,
}) async {
  if (!_inFlightCourseIds.add(courseId)) {
    onProgress?.call('合集下载进行中…', null);
    return;
  }
  try {
    LibraryCourseData? target;
    for (final LibraryCourseData course in readCourses()) {
      if (course.id == courseId) {
        target = course;
        break;
      }
    }
    if (target == null || !_isMultiEpisodeBilibili(target)) {
      return;
    }

    final List<LibraryEpisodeItem> pending = target.episodes
        .where(
          (LibraryEpisodeItem e) =>
              e.videoMissing || !isUsableLocalVideoPath(e.videoAsset),
        )
        .toList(growable: false);
    if (pending.isEmpty) {
      return;
    }

    int success = 0;
    int failed = 0;
    for (int i = 0; i < pending.length; i++) {
      LibraryCourseData? live;
      for (final LibraryCourseData course in readCourses()) {
        if (course.id == courseId) {
          live = course;
          break;
        }
      }
      live ??= target;

      final LibraryEpisodeItem episode = pending[i];
      final LibraryEpisodeItem current = live.episodes.firstWhere(
        (LibraryEpisodeItem e) => e.id == episode.id,
        orElse: () => episode,
      );
      if (isUsableLocalVideoPath(current.videoAsset) && !current.videoMissing) {
        success += 1;
        continue;
      }

      final String? source = bilibiliSourceForEpisode(
        course: live,
        episode: current,
        videoAsset: current.videoAsset,
      );
      if (source == null || source.trim().isEmpty) {
        failed += 1;
        continue;
      }
      final double progress = (i + 1) / pending.length;
      final String message =
          '正在下载第 ${current.numberStr} 集（${i + 1}/${pending.length}）…';
      onProgress?.call(message, progress);
      progressNotifier?.update(
        BilibiliCollectionDownloadProgress(
          courseId: courseId,
          message: message,
          progress: progress,
          successCount: success,
          failedCount: failed,
        ),
      );
      try {
        final BilibiliEpisodePrepareResult prepared =
            await prepareBilibiliEpisode(
              service: service,
              source: source,
              currentVideoAsset: current.videoAsset,
              existingEnSubtitlePath: current.enSubtitleAsset,
              existingZhSubtitlePath: current.cnSubtitleAsset,
              onProgress: (String detail) {
                final String detailMessage =
                    '第 ${current.numberStr} 集：$detail';
                onProgress?.call(detailMessage, progress);
                progressNotifier?.update(
                  BilibiliCollectionDownloadProgress(
                    courseId: courseId,
                    message: detailMessage,
                    progress: progress,
                    successCount: success,
                    failedCount: failed,
                  ),
                );
              },
            );
        if (!isUsableLocalVideoPath(prepared.localVideoPath)) {
          failed += 1;
          continue;
        }
        String cover = current.coverImage.trim();
        // Always try to pin a durable cover for this episode BV.
        try {
          final String? pinned = await service.resolveCoverImage(source);
          if (pinned != null && pinned.trim().isNotEmpty) {
            cover = pinned.trim();
          }
        } catch (_) {}

        await catalog.updateEpisodeLocalMedia(
          courseId: courseId,
          episodeId: current.id,
          videoAsset: prepared.localVideoPath,
          sourceUrl: source,
          enSubtitlePath: prepared.enSubtitlePath,
          zhSubtitlePath: prepared.zhSubtitlePath,
          coverImage: cover.isEmpty ? null : cover,
          videoMissing: false,
        );
        await enqueueSubtitleCompletionForEpisode(
          episodeId: current.id,
          videoPath: prepared.localVideoPath,
          zhSubtitlePath: prepared.zhSubtitlePath,
          enSubtitlePath: prepared.enSubtitlePath,
          sourceUrl: source,
        );
        success += 1;
        developer.log(
          'collection download ok ${current.id} '
          'video=${prepared.localVideoPath}',
          name: 'bilibili.collection',
        );
      } catch (e, st) {
        failed += 1;
        developer.log(
          'collection download failed ${current.id}: $e',
          name: 'bilibili.collection',
          error: e,
          stackTrace: st,
        );
      }
    }
    final String doneMessage = failed == 0
        ? '合集下载完成（$success 集）'
        : '合集下载完成（成功 $success，失败 $failed）';
    onProgress?.call(doneMessage, 1);
    progressNotifier?.update(
      BilibiliCollectionDownloadProgress(
        courseId: courseId,
        message: doneMessage,
        progress: 1,
        done: true,
        successCount: success,
        failedCount: failed,
      ),
    );
  } finally {
    _inFlightCourseIds.remove(courseId);
  }
}
