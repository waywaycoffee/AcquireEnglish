import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../subtitle_completion/subtitle_completion_enqueue.dart';
import 'bilibili_episode_prepare.dart';
import 'bilibili_import_service.dart';
import 'bilibili_multipage.dart';

final Set<String> _inFlightCourseIds = <String>{};

/// Episodes that failed recently — skip for a while so one stuck CDN URL
/// cannot restart forever and spam「正在下载视频 0%」.
final Map<String, DateTime> _episodeDownloadCooldownUntil = <String, DateTime>{};
const Duration _episodeFailCooldown = Duration(minutes: 12);

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

    final DateTime now = DateTime.now();
    _episodeDownloadCooldownUntil.removeWhere(
      (_, DateTime until) => !until.isAfter(now),
    );
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
    int skippedCooldown = 0;
    String? lastUiMessage;
    DateTime lastUiAt = DateTime.fromMillisecondsSinceEpoch(0);
    void publish({
      required String message,
      required double progress,
      bool force = false,
    }) {
      final DateTime tick = DateTime.now();
      if (!force &&
          message == lastUiMessage &&
          tick.difference(lastUiAt) < const Duration(milliseconds: 700)) {
        return;
      }
      lastUiMessage = message;
      lastUiAt = tick;
      onProgress?.call(message, progress);
      progressNotifier?.update(
        BilibiliCollectionDownloadProgress(
          courseId: courseId,
          message: message,
          progress: progress.clamp(0.0, 1.0),
          successCount: success,
          failedCount: failed,
        ),
      );
    }

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

      final DateTime? coolUntil = _episodeDownloadCooldownUntil[current.id];
      if (coolUntil != null && coolUntil.isAfter(DateTime.now())) {
        skippedCooldown += 1;
        publish(
          message:
              '第 ${current.numberStr} 集下载失败冷却中，先跳过（稍后自动重试）',
          progress: (i + 1) / pending.length,
          force: true,
        );
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
      final double episodeBase = i / pending.length;
      final double episodeSpan = 1 / pending.length;
      publish(
        message: '正在下载第 ${current.numberStr} 集（${i + 1}/${pending.length}）…',
        progress: episodeBase + episodeSpan * 0.05,
        force: true,
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
                // Prefer byte % from "正在下载视频 N%" when present.
                final RegExpMatch? pct = RegExp(
                  r'正在下载视频\s+(\d+)%',
                ).firstMatch(detail);
                double local = 0.15;
                if (pct != null) {
                  local = ((int.tryParse(pct.group(1)!) ?? 0) / 100.0).clamp(
                    0.0,
                    0.95,
                  );
                } else if (detail.contains('完成') || detail.contains('本地')) {
                  local = 0.98;
                }
                publish(
                  message: '第 ${current.numberStr} 集：$detail',
                  progress: episodeBase + episodeSpan * local,
                );
              },
            ).timeout(
              const Duration(minutes: 8),
              onTimeout: () => throw TimeoutException(
                '第 ${current.numberStr} 集下载超时',
              ),
            );
        if (!isUsableLocalVideoPath(prepared.localVideoPath)) {
          failed += 1;
          _episodeDownloadCooldownUntil[current.id] =
              DateTime.now().add(_episodeFailCooldown);
          publish(
            message: '第 ${current.numberStr} 集下载失败，已跳过',
            progress: (i + 1) / pending.length,
            force: true,
          );
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
        _episodeDownloadCooldownUntil.remove(current.id);
        await enqueueSubtitleCompletionForEpisode(
          episodeId: current.id,
          videoPath: prepared.localVideoPath,
          zhSubtitlePath: prepared.zhSubtitlePath,
          enSubtitlePath: prepared.enSubtitlePath,
          sourceUrl: source,
          title: current.title,
          course: catalog.state
              .where((LibraryCourseData c) => c.id == courseId)
              .firstOrNull,
          episode: current,
        );
        success += 1;
        publish(
          message: '第 ${current.numberStr} 集下载完成（${i + 1}/${pending.length}）',
          progress: (i + 1) / pending.length,
          force: true,
        );
        developer.log(
          'collection download ok ${current.id} '
          'video=${prepared.localVideoPath}',
          name: 'bilibili.collection',
        );
      } catch (e, st) {
        failed += 1;
        _episodeDownloadCooldownUntil[current.id] =
            DateTime.now().add(_episodeFailCooldown);
        publish(
          message: '第 ${current.numberStr} 集下载失败，已跳过：$e',
          progress: (i + 1) / pending.length,
          force: true,
        );
        developer.log(
          'collection download failed ${current.id}: $e',
          name: 'bilibili.collection',
          error: e,
          stackTrace: st,
        );
      }
    }
    final String doneMessage = failed == 0 && skippedCooldown == 0
        ? '合集下载完成（$success 集）'
        : '合集下载完成（成功 $success，失败 $failed'
            '${skippedCooldown > 0 ? '，冷却跳过 $skippedCooldown' : ''}）';
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
