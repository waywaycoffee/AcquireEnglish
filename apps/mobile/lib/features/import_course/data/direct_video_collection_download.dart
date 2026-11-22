import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import 'bilibili_episode_prepare.dart';

class DirectVideoCollectionProgress {
  const DirectVideoCollectionProgress({
    required this.courseId,
    required this.message,
    required this.progress,
    this.done = false,
  });

  final String courseId;
  final String message;
  final double progress;
  final bool done;
}

class DirectVideoCollectionProgressNotifier
    extends Notifier<DirectVideoCollectionProgress?> {
  @override
  DirectVideoCollectionProgress? build() => null;

  void update(DirectVideoCollectionProgress? next) => state = next;
}

final NotifierProvider<
  DirectVideoCollectionProgressNotifier,
  DirectVideoCollectionProgress?
> directVideoCollectionProgressProvider =
    NotifierProvider<
      DirectVideoCollectionProgressNotifier,
      DirectVideoCollectionProgress?
    >(DirectVideoCollectionProgressNotifier.new);

final Map<String, CancelToken> _activeDownloads = <String, CancelToken>{};

bool isDirectVideoCollection(LibraryCourseData course) =>
    course.episodes.length > 1 &&
    course.episodes.any(
      (LibraryEpisodeItem episode) => _directVideoUri(episode) != null,
    );

Uri? _directVideoUri(LibraryEpisodeItem episode) {
  if (episode.videoMissing) return null;
  final Uri? uri = Uri.tryParse(
    (episode.sourceUrl ?? episode.videoAsset ?? '').trim(),
  );
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  final String host = uri.host.toLowerCase();
  if (host.endsWith('bilibili.com') ||
      host.endsWith('youtube.com') ||
      host == 'youtu.be' ||
      host.endsWith('example.com')) {
    return null;
  }
  return uri;
}

int pendingDirectVideoEpisodes(LibraryCourseData course) => course.episodes
    .where(
      (LibraryEpisodeItem episode) =>
          !isUsableLocalVideoPath(episode.videoAsset) &&
          _directVideoUri(episode) != null,
    )
    .length;

void cancelDirectVideoCollectionDownload(String courseId) {
  _activeDownloads[courseId]?.cancel('用户取消下载');
}

Future<void> downloadDirectVideoCollection({
  required LibraryCatalogNotifier catalog,
  required List<LibraryCourseData> Function() readCourses,
  required String courseId,
  required DirectVideoCollectionProgressNotifier progressNotifier,
  Dio? dio,
}) async {
  if (_activeDownloads.containsKey(courseId)) return;
  final CancelToken token = CancelToken();
  _activeDownloads[courseId] = token;
  final Dio client = dio ?? Dio();
  void publish(String message, double progress, {bool done = false}) {
    progressNotifier.update(
      DirectVideoCollectionProgress(
        courseId: courseId,
        message: message,
        progress: progress.clamp(0, 1),
        done: done,
      ),
    );
  }

  try {
    final LibraryCourseData? course = readCourses()
        .where((LibraryCourseData item) => item.id == courseId)
        .firstOrNull;
    if (course == null || !isDirectVideoCollection(course)) return;
    final List<LibraryEpisodeItem> pending = course.episodes
        .where(
          (LibraryEpisodeItem episode) =>
              !isUsableLocalVideoPath(episode.videoAsset) &&
              _directVideoUri(episode) != null,
        )
        .toList(growable: false);
    final Directory root = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(
      '${root.path}/course_media/${_safeName(courseId)}',
    )..createSync(recursive: true);
    int success = 0;
    int failed = 0;
    for (int i = 0; i < pending.length; i++) {
      if (token.isCancelled) break;
      final LibraryEpisodeItem episode = pending[i];
      final Uri uri = _directVideoUri(episode)!;
      final String source = uri.toString();
      final File file = File('${dir.path}/${_safeName(episode.id)}.mp4');
      final File partial = File('${file.path}.part');
      try {
        if (isUsableLocalVideoPath(file.path)) {
          await catalog.updateEpisodeLocalMedia(
            courseId: courseId,
            episodeId: episode.id,
            videoAsset: file.path,
            sourceUrl: source,
            videoMissing: false,
          );
          success++;
          continue;
        }
        publish(
          '正在下载第 ${episode.numberStr} 集（${i + 1}/${pending.length}）',
          i / pending.length,
        );
        await client.downloadUri(
          uri,
          partial.path,
          cancelToken: token,
          onReceiveProgress: (int received, int total) {
            if (total > 0) {
              publish(
                '第 ${episode.numberStr} 集：${(received / total * 100).round()}%',
                (i + received / total) / pending.length,
              );
            }
          },
        );
        if (partial.lengthSync() <= 64 * 1024) {
          throw StateError('下载内容过小');
        }
        if (file.existsSync()) file.deleteSync();
        partial.renameSync(file.path);
        await catalog.updateEpisodeLocalMedia(
          courseId: courseId,
          episodeId: episode.id,
          videoAsset: file.path,
          sourceUrl: source,
          videoMissing: false,
        );
        success++;
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) break;
        failed++;
      } catch (_) {
        failed++;
      } finally {
        if (partial.existsSync()) partial.deleteSync();
      }
    }
    publish(
      token.isCancelled
          ? '已停止下载（完成 $success 集）'
          : '合集下载完成（成功 $success，失败 $failed）',
      1,
      done: true,
    );
  } finally {
    _activeDownloads.remove(courseId);
    if (dio == null) client.close();
  }
}

String _safeName(String value) =>
    value.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
