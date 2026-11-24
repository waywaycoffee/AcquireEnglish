import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../../constants/endpoints.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../subtitle_completion/subtitle_completion_enqueue.dart';
import '../../subtitle_completion/subtitle_completion_scheduler.dart';
import '../../sync/data/acquire_api_client.dart';
import 'bilibili_episode_prepare.dart';

/// Local drama cache TTL — unused files under Documents/netdisk_media are removed.
const Duration kNetdiskMediaUnusedTtl = Duration(days: 10);
const String _netdiskMediaAccessKey = 'netdisk_media_last_access_v1';

/// Baidu CDN often rejects anonymous media_kit fetches; always send these.
const Map<String, String> kNetdiskStreamHeaders = <String, String>{
  'User-Agent': 'pan.baidu.com',
  'Referer': 'https://pan.baidu.com/',
};

bool isNetdiskPlayUrl(String? path) {
  final String value = (path ?? '').trim().toLowerCase();
  if (value.isEmpty) {
    return false;
  }
  return value.contains('/api/netdisk/play/') ||
      value.contains('netdisk/play/');
}

Future<Directory> netdiskMediaDirectory() async {
  final Directory docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}/netdisk_media');
}

String _accessKeyForFile(File file) {
  final String name = file.uri.pathSegments.isEmpty
      ? file.path
      : file.uri.pathSegments.last;
  final int dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

Map<String, int> _readAccessMap() {
  if (!Hive.isBoxOpen('prefs')) {
    return <String, int>{};
  }
  final String raw =
      Hive.box<String>('prefs').get(_netdiskMediaAccessKey) ?? '';
  if (raw.trim().isEmpty) {
    return <String, int>{};
  }
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <String, int>{};
    }
    final Map<String, int> out = <String, int>{};
    decoded.forEach((Object? key, Object? value) {
      final int? ms = value is int
          ? value
          : (value is num ? value.toInt() : int.tryParse('$value'));
      if (key != null && ms != null && ms > 0) {
        out['$key'] = ms;
      }
    });
    return out;
  } catch (_) {
    return <String, int>{};
  }
}

Future<void> _writeAccessMap(Map<String, int> map) async {
  if (!Hive.isBoxOpen('prefs')) {
    return;
  }
  await Hive.box<String>('prefs').put(
    _netdiskMediaAccessKey,
    jsonEncode(map),
  );
}

/// Mark a local netdisk video as recently used (playback / download / hit).
Future<void> touchNetdiskMediaAccess(File file) async {
  if (!file.existsSync()) {
    return;
  }
  final Map<String, int> map = _readAccessMap();
  map[_accessKeyForFile(file)] = DateTime.now().millisecondsSinceEpoch;
  await _writeAccessMap(map);
}

Future<File?> findCachedNetdiskMedia(int importId) async {
  final Directory dir = await netdiskMediaDirectory();
  if (!dir.existsSync()) {
    return null;
  }
  for (final String ext in <String>['.mkv', '.mp4', '.bin', '.ts', '.webm']) {
    final File f = File('${dir.path}/$importId$ext');
    if (f.existsSync() && f.lengthSync() > 64 * 1024) {
      unawaited(touchNetdiskMediaAccess(f));
      return f;
    }
  }
  // Legacy downloadNetdiskCourseToLocal used sanitized names.
  await for (final FileSystemEntity e in dir.list()) {
    if (e is! File) {
      continue;
    }
    final String name = e.uri.pathSegments.isEmpty
        ? ''
        : e.uri.pathSegments.last;
    if (name.startsWith('$importId') && e.lengthSync() > 64 * 1024) {
      unawaited(touchNetdiskMediaAccess(e));
      return e;
    }
  }
  return null;
}

class NetdiskMediaPurgeResult {
  const NetdiskMediaPurgeResult({
    required this.deletedFiles,
    required this.freedBytes,
  });

  final List<String> deletedFiles;
  final int freedBytes;
}

/// Delete `Documents/netdisk_media` files not touched for [maxAge] (default 10d).
///
/// Returns deleted absolute paths so the library can point episodes back to the
/// netdisk play URL instead of a missing local file.
Future<NetdiskMediaPurgeResult> purgeStaleNetdiskMedia({
  Duration maxAge = kNetdiskMediaUnusedTtl,
}) async {
  final Directory dir = await netdiskMediaDirectory();
  if (!dir.existsSync()) {
    return const NetdiskMediaPurgeResult(deletedFiles: <String>[], freedBytes: 0);
  }
  final Map<String, int> access = _readAccessMap();
  final int cutoff =
      DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
  final List<String> deleted = <String>[];
  int freed = 0;
  final Set<String> keepKeys = <String>{};

  await for (final FileSystemEntity e in dir.list()) {
    if (e is! File) {
      continue;
    }
    final String path = e.path;
    if (path.endsWith('.part')) {
      try {
        final int len = e.lengthSync();
        await e.delete();
        deleted.add(path);
        freed += len;
      } catch (_) {}
      continue;
    }
    final String key = _accessKeyForFile(e);
    int lastMs = access[key] ?? 0;
    if (lastMs <= 0) {
      try {
        lastMs = e.lastModifiedSync().millisecondsSinceEpoch;
      } catch (_) {
        lastMs = 0;
      }
    }
    if (lastMs > cutoff) {
      keepKeys.add(key);
      access[key] = lastMs;
      continue;
    }
    try {
      final int len = e.lengthSync();
      await e.delete();
      deleted.add(path);
      freed += len;
    } catch (_) {}
  }

  access.removeWhere((String k, int _) => !keepKeys.contains(k));
  await _writeAccessMap(access);
  return NetdiskMediaPurgeResult(deletedFiles: deleted, freedBytes: freed);
}

String absoluteNetdiskPlayUrl(String playUrl) {
  final String trimmed = playUrl.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final String base = Endpoints.normalizeBaseUrl(Endpoints.baseUrl)
      .replaceAll(RegExp(r'/$'), '');
  if (trimmed.startsWith('/')) {
    return '$base$trimmed';
  }
  return '$base/$trimmed';
}

/// Prefer local cache; else follow API→Baidu redirects and return CDN URL + headers.
///
/// Opening the bare `/api/netdisk/play/...` 302 in media_kit without Baidu UA
/// commonly yields audio-only / long black video on phone.
Future<({String uri, Map<String, String>? headers})> resolveNetdiskPlayableMedia(
  String playUrl,
) async {
  final int? importId = parseNetdiskImportIdFromUrl(playUrl);
  if (importId != null) {
    final File? cached = await findCachedNetdiskMedia(importId);
    if (cached != null) {
      return (uri: cached.path, headers: null);
    }
  }

  final String startUrl = absoluteNetdiskPlayUrl(playUrl);
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 10,
      headers: <String, dynamic>{...kNetdiskStreamHeaders},
      validateStatus: (int? s) => s != null && s >= 200 && s < 400,
    ),
  );
  try {
    // Tiny ranged GET so we land on the final CDN URL without downloading the film.
    final Response<List<int>> resp = await dio.get<List<int>>(
      startUrl,
      options: Options(
        responseType: ResponseType.bytes,
        headers: <String, dynamic>{
          ...kNetdiskStreamHeaders,
          'Range': 'bytes=0-2047',
        },
      ),
    );
    final String finalUrl = resp.realUri.toString();
    if (finalUrl.isNotEmpty) {
      return (uri: finalUrl, headers: kNetdiskStreamHeaders);
    }
  } catch (_) {
    // Fall through — media_kit may still open the API redirect with headers.
  }
  return (uri: startUrl, headers: kNetdiskStreamHeaders);
}

/// Drama MKV over Baidu progressive HTTP stutters and often blacks out video.
/// Prefer a full local file before playback; fall back to CDN stream on failure.
Future<({String uri, Map<String, String>? headers})>
    prepareNetdiskEpisodeForSmoothPlayback({
  required String playUrl,
  void Function(double? progress, String message)? onProgress,
}) async {
  final int? importId = parseNetdiskImportIdFromUrl(playUrl);
  if (importId != null) {
    final File? cached = await findCachedNetdiskMedia(importId);
    if (cached != null) {
      onProgress?.call(1, '使用已缓存本集');
      return (uri: cached.path, headers: null);
    }
  }
  onProgress?.call(0, '正在下载本集以流畅播放…');
  try {
    final File local = await cacheNetdiskEpisodeLocally(
      playUrl: playUrl,
      onProgress: (double? p) {
        if (p == null) {
          onProgress?.call(null, '正在下载本集…');
        } else {
          onProgress?.call(p, '正在下载本集 ${(p * 100).round()}%…');
        }
      },
    );
    onProgress?.call(1, '本集已就绪');
    return (uri: local.path, headers: null);
  } catch (_) {
    onProgress?.call(null, '下载未完成，改用在线缓冲…');
    return resolveNetdiskPlayableMedia(playUrl);
  }
}

final Set<String> _prefetchInFlightPlayUrls = <String>{};

/// Warm the next episode while the current one plays from local cache.
void prefetchNetdiskPlayUrl(String? playUrl) {
  final String trimmed = (playUrl ?? '').trim();
  if (!isNetdiskPlayUrl(trimmed)) {
    return;
  }
  if (!_prefetchInFlightPlayUrls.add(trimmed)) {
    return;
  }
  unawaited(() async {
    try {
      await cacheNetdiskEpisodeLocally(playUrl: trimmed);
    } catch (_) {
    } finally {
      _prefetchInFlightPlayUrls.remove(trimmed);
    }
  }());
}

/// Download one episode into netdisk_media/{importId}.mkv for smooth local play.
Future<File> cacheNetdiskEpisodeLocally({
  required String playUrl,
  void Function(double? progress)? onProgress,
}) async {
  final int? importId = parseNetdiskImportIdFromUrl(playUrl);
  final String idKey = importId?.toString() ??
      playUrl.hashCode.toRadixString(16);
  final File? existing =
      importId == null ? null : await findCachedNetdiskMedia(importId);
  if (existing != null) {
    await touchNetdiskMediaAccess(existing);
    onProgress?.call(1);
    return existing;
  }
  final Directory dir = await netdiskMediaDirectory();
  await dir.create(recursive: true);
  final File out = File('${dir.path}/$idKey.mkv');
  final File temp = File('${out.path}.part');
  if (temp.existsSync()) {
    await temp.delete();
  }
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(hours: 2),
      followRedirects: true,
      maxRedirects: 10,
      headers: <String, dynamic>{...kNetdiskStreamHeaders},
    ),
  );
  int lastPercent = -1;
  await dio.download(
    absoluteNetdiskPlayUrl(playUrl),
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
  await touchNetdiskMediaAccess(out);
  onProgress?.call(1);
  return out;
}

class NetdiskDownloadProgress {
  const NetdiskDownloadProgress({
    required this.courseId,
    required this.message,
    required this.progress,
    this.done = false,
    this.current = 0,
    this.total = 0,
  });

  final String courseId;
  final String message;
  final double progress;
  final bool done;
  final int current;
  final int total;
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
  if (course.id.startsWith('netdisk-series-')) {
    return true;
  }
  if (category.endsWith('_netdisk') || category == 'netdisk') {
    return true;
  }
  if (course.id.startsWith('link-') &&
      (category.contains('baidu') ||
          category.contains('quark') ||
          category.contains('aliyun') ||
          category.contains('pan115') ||
          category.contains('netdisk'))) {
    return true;
  }
  return false;
}

/// 美剧 / 网盘剧集：默认横屏全屏内嵌在线播，不先下本地。
bool prefersNetdiskLandscapePlayback(LibraryCourseData? course) {
  if (course == null) {
    return false;
  }
  if (!isNetdiskCourse(course)) {
    return false;
  }
  // Multi-episode series, or explicitly tagged as series / drama.
  if (course.id.startsWith('netdisk-series-')) {
    return true;
  }
  if (course.episodes.length > 1) {
    return true;
  }
  final String hay =
      '${course.category} ${course.sourceLabel} ${course.title}'.toLowerCase();
  return hay.contains('series') ||
      hay.contains('美剧') ||
      hay.contains('drama') ||
      hay.contains('剧集');
}

bool isRemoteStreamVideoAsset(String? path) {
  final String value = path?.trim() ?? '';
  return value.startsWith('http://') || value.startsWith('https://');
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

int? parseNetdiskImportIdFromUrl(String? url) {
  if (url == null || url.trim().isEmpty) {
    return null;
  }
  final RegExp play = RegExp(r'/api/netdisk/play/(\d+)');
  final Match? m1 = play.firstMatch(url);
  if (m1 != null) {
    return int.tryParse(m1.group(1)!);
  }
  final RegExp srt = RegExp(r'/api/imports/(\d+)/srt/');
  final Match? m2 = srt.firstMatch(url);
  if (m2 != null) {
    return int.tryParse(m2.group(1)!);
  }
  return null;
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

/// Write API softsubs for a netdisk import onto disk and catalog.
Future<void> materializeNetdiskSoftsubs({
  required AcquireApiClient api,
  required LibraryCatalogNotifier catalog,
  required String courseId,
  LibraryEpisodeItem? episode,
  int? importId,
}) async {
  final int? resolvedId = importId ??
      parseLinkImportId(courseId) ??
      parseNetdiskImportIdFromUrl(episode?.enSubtitleAsset) ??
      parseNetdiskImportIdFromUrl(episode?.cnSubtitleAsset) ??
      parseNetdiskImportIdFromUrl(episode?.videoAsset) ??
      parseNetdiskImportIdFromUrl(episode?.sourceUrl);
  if (resolvedId == null) {
    return;
  }
  final String? enBody = await api.fetchPersonalImportSrt(
    importId: resolvedId,
    lang: 'en',
  );
  final String? zhBody = await api.fetchPersonalImportSrt(
    importId: resolvedId,
    lang: 'zh',
  );
  if ((enBody == null || enBody.trim().isEmpty) &&
      (zhBody == null || zhBody.trim().isEmpty)) {
    return;
  }
  final Directory docs = await getApplicationDocumentsDirectory();
  final Directory dir = Directory('${docs.path}/netdisk/$resolvedId');
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
  bool preferMissingSubtitlesFirst = true,
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
  void publish(
    String message,
    double progress, {
    bool done = false,
    int current = 0,
    int total = 0,
  }) {
    progressNotifier?.update(
      NetdiskDownloadProgress(
        courseId: courseId,
        message: message,
        progress: progress.clamp(0.0, 1.0),
        done: done,
        current: current,
        total: total,
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

    final List<AcquireLessonDto> lessons = List<AcquireLessonDto>.from(
      remoteCourse.lessons,
    );
    if (preferMissingSubtitlesFirst) {
      lessons.sort((AcquireLessonDto a, AcquireLessonDto b) {
        final bool aMissing = a.subtitleEn.trim().isEmpty;
        final bool bMissing = b.subtitleEn.trim().isEmpty;
        if (aMissing == bMissing) {
          return a.index.compareTo(b.index);
        }
        return aMissing ? -1 : 1;
      });
    }

    final int total = lessons.length;
    int index = 0;
    for (final AcquireLessonDto lesson in lessons) {
      index += 1;
      final double base = (index - 1) / total;
      final double span = 1 / total;
      publish(
        '正在下载第 $index/$total 集…',
        base + span * 0.05,
        current: index,
        total: total,
      );

      final String playUrl = lesson.videoUrl.trim();
      if (playUrl.isEmpty) {
        continue;
      }
      final int? importId =
          parseNetdiskImportIdFromUrl(playUrl) ??
          parseNetdiskImportIdFromUrl(lesson.subtitleEn) ??
          parseLinkImportId(courseId);
      final String idKey =
          importId?.toString() ??
          '${courseId}_${lesson.id}'.replaceAll('/', '_');
      final File local = await _downloadPlayUrlToCache(
        playUrl: playUrl,
        idKey: idKey,
        onProgress: (double? p) {
          final double localP = p ?? 0;
          publish(
            '正在下载第 $index/$total 集 ${(localP * 100).clamp(0, 100).round()}%',
            base + span * (0.1 + localP * 0.8),
            current: index,
            total: total,
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
        importId: importId,
        episode: ep ??
            (target.episodes.isNotEmpty ? target.episodes.first : null),
      );

      for (final LibraryCourseData course in readCourses()) {
        if (course.id == courseId) {
          target = course;
          break;
        }
      }
      LibraryEpisodeItem? refreshed;
      for (final LibraryEpisodeItem e in target.episodes) {
        if (e.id == lesson.id) {
          refreshed = e;
          break;
        }
      }
      if (refreshed != null) {
        await enqueueSubtitleCompletionForEpisode(
          episodeId: refreshed.id,
          videoPath: local.path,
          zhSubtitlePath: refreshed.cnSubtitleAsset,
          enSubtitlePath: refreshed.enSubtitleAsset,
          course: target,
          episode: refreshed,
        );
        SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
      }
    }
    publish('下载完成，可离线播放', 1, done: true, current: total, total: total);
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
