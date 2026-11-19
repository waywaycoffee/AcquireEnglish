import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../sync/data/acquire_api_client.dart';
import 'bilibili_episode_prepare.dart';

class NetdiskDownloadProgress {
  const NetdiskDownloadProgress({
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

class NetdiskDownloadProgressNotifier extends Notifier<NetdiskDownloadProgress?> {
  @override
  NetdiskDownloadProgress? build() => null;

  void update(NetdiskDownloadProgress? next) {
    state = next;
  }
}

final NotifierProvider<NetdiskDownloadProgressNotifier, NetdiskDownloadProgress?>
netdiskDownloadProgressProvider =
    NotifierProvider<NetdiskDownloadProgressNotifier, NetdiskDownloadProgress?>(
      NetdiskDownloadProgressNotifier.new,
    );

final Set<String> _inFlightCourseIds = <String>{};

bool isNetdiskCourse(LibraryCourseData course) {
  final String category = course.category.trim().toLowerCase();
  if (category.endsWith('_netdisk')) {
    return true;
  }
  if (course.id.startsWith('link-') &&
      (category.contains('baidu') || category.contains('quark'))) {
    return true;
  }
  return course.id.startsWith('link-') && category.contains('netdisk');
}

bool isNetdiskDownloadInFlight(String courseId) =>
    _inFlightCourseIds.contains(courseId);

int? parseLinkImportId(String courseId) {
  final String id = courseId.trim();
  if (!id.startsWith('link-')) {
    return null;
  }
  return int.tryParse(id.substring('link-'.length));
}

int pendingNetdiskEpisodes(LibraryCourseData course) {
  if (!isNetdiskCourse(course)) {
    return 0;
  }
  return course.episodes
      .where(
        (LibraryEpisodeItem e) =>
            e.videoMissing || !isUsableLocalVideoPath(e.videoAsset),
      )
      .length;
}

/// Write API softsubs for a netdisk `link-{id}` course onto disk and catalog.
Future<void> materializeNetdiskSoftsubs({
  required AcquireApiClient api,
  required LibraryCatalogNotifier catalog,
  required String courseId,
  LibraryEpisodeItem? episode,
}) async {
  final int? importId = parseLinkImportId(courseId);
  if (importId == null) {
    return;
  }
  final String? enBody = await api.fetchPersonalImportSrt(
    importId: importId,
    lang: 'en',
  );
  final String? zhBody = await api.fetchPersonalImportSrt(
    importId: importId,
    lang: 'zh',
  );
  if ((enBody == null || enBody.trim().isEmpty) &&
      (zhBody == null || zhBody.trim().isEmpty)) {
    return;
  }
  final Directory docs = await getApplicationDocumentsDirectory();
  final Directory dir = Directory('${docs.path}/netdisk/$importId');
  await dir.create(recursive: true);
  String? enPath;
  String? zhPath;
  if (enBody != null && enBody.trim().isNotEmpty) {
    final File file = File('${dir.path}/en.srt');
    await file.writeAsString(enBody, flush: true);
    enPath = file.path;
  }
  if (zhBody != null && zhBody.trim().isNotEmpty) {
    final File file = File('${dir.path}/zh.srt');
    await file.writeAsString(zhBody, flush: true);
    zhPath = file.path;
  }
  final String episodeId = episode?.id ?? '$courseId-01';
  await catalog.updateEpisodeLocalMedia(
    courseId: courseId,
    episodeId: episodeId,
    enSubtitlePath: enPath,
    zhSubtitlePath: zhPath,
  );
}

/// Download OpenList-signed play URL to local storage, then switch playback.
Future<void> downloadNetdiskCourseToLocal({
  required AcquireApiClient api,
  required LibraryCatalogNotifier catalog,
  required List<LibraryCourseData> Function() readCourses,
  required String courseId,
  NetdiskDownloadProgressNotifier? progressNotifier,
}) async {
  if (!_inFlightCourseIds.add(courseId)) {
    progressNotifier?.update(
      NetdiskDownloadProgress(
        courseId: courseId,
        message: '网盘下载进行中…',
        progress: 0.05,
      ),
    );
    return;
  }
  void publish(String message, double progress, {bool done = false}) {
    progressNotifier?.update(
      NetdiskDownloadProgress(
        courseId: courseId,
        message: message,
        progress: progress.clamp(0.0, 1.0),
        done: done,
      ),
    );
  }

  try {
    LibraryCourseData? found;
    for (final LibraryCourseData course in readCourses()) {
      if (course.id == courseId) {
        found = course;
        break;
      }
    }
    if (found == null || !isNetdiskCourse(found)) {
      return;
    }
    LibraryCourseData target = found;

    publish('正在刷新播放地址…', 0.02);
    final List<AcquireCourseDto> remote = await api.courses();
    AcquireCourseDto? remoteCourse;
    for (final AcquireCourseDto c in remote) {
      if (c.id == courseId) {
        remoteCourse = c;
        break;
      }
    }
    if (remoteCourse == null || remoteCourse.lessons.isEmpty) {
      throw StateError('云端课程不存在或已失效');
    }

    final int total = remoteCourse.lessons.length;
    int index = 0;
    for (final AcquireLessonDto lesson in remoteCourse.lessons) {
      index += 1;
      final double base = (index - 1) / total;
      final double span = 1 / total;
      publish('正在下载第 $index/$total 集…', base + span * 0.05);

      final String playUrl = lesson.videoUrl.trim();
      if (playUrl.isEmpty) {
        continue;
      }
      final int? importId = parseLinkImportId(courseId);
      final String idKey =
          importId?.toString() ?? courseId.replaceAll('/', '_');
      final File local = await _downloadPlayUrlToCache(
        playUrl: playUrl,
        idKey: idKey,
        onProgress: (double? p) {
          final double localP = p ?? 0;
          publish(
            '正在下载第 $index/$total 集 ${(localP * 100).clamp(0, 100).round()}%',
            base + span * (0.1 + localP * 0.8),
          );
        },
      );

      LibraryEpisodeItem? ep;
      for (final LibraryEpisodeItem e in target.episodes) {
        if (e.id == lesson.id) {
          ep = e;
          break;
        }
      }
      await catalog.updateEpisodeLocalMedia(
        courseId: courseId,
        episodeId: lesson.id,
        videoAsset: local.path,
        sourceUrl: playUrl,
      );
      await materializeNetdiskSoftsubs(
        api: api,
        catalog: catalog,
        courseId: courseId,
        episode: ep ??
            (target.episodes.isNotEmpty ? target.episodes.first : null),
      );
      for (final LibraryCourseData course in readCourses()) {
        if (course.id == courseId) {
          target = course;
          break;
        }
      }
    }
    publish('下载完成，可离线播放', 1, done: true);
  } catch (e) {
    publish('下载失败：$e', 1, done: true);
    rethrow;
  } finally {
    _inFlightCourseIds.remove(courseId);
  }
}

Future<File> _downloadPlayUrlToCache({
  required String playUrl,
  required String idKey,
  void Function(double? progress)? onProgress,
}) async {
  final Directory docs = await getApplicationDocumentsDirectory();
  final Directory dir = Directory('${docs.path}/netdisk_media');
  await dir.create(recursive: true);
  final String safe = idKey.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
  final File out = File('${dir.path}/$safe.mp4');
  if (out.existsSync() && out.lengthSync() > 64 * 1024) {
    onProgress?.call(1);
    return out;
  }
  final File temp = File('${out.path}.part');
  if (temp.existsSync()) {
    await temp.delete();
  }

  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(hours: 2),
      followRedirects: true,
      maxRedirects: 8,
      headers: <String, dynamic>{
        // Baidu rejects browser UA for many large-file links.
        'User-Agent': 'pan.baidu.com',
        'Referer': 'https://pan.baidu.com/',
      },
    ),
  );

  int lastPercent = -1;
  await dio.download(
    playUrl,
    temp.path,
    onReceiveProgress: (int received, int total) {
      if (total <= 0) {
        onProgress?.call(null);
        return;
      }
      final int percent = ((received / total) * 100).floor();
      if (percent == lastPercent) {
        return;
      }
      lastPercent = percent;
      onProgress?.call((received / total).clamp(0.0, 1.0));
    },
  );
  if (!temp.existsSync() || temp.lengthSync() < 64 * 1024) {
    if (temp.existsSync()) {
      await temp.delete();
    }
    throw StateError('下载文件过小或失败');
  }
  if (out.existsSync()) {
    await out.delete();
  }
  await temp.rename(out.path);
  onProgress?.call(1);
  return out;
}
