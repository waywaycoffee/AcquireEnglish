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
    // Keep in-progress downloads; only drop abandoned .part older than TTL.
    if (path.endsWith('.part')) {
      int lastMs = 0;
      try {
        lastMs = e.lastModifiedSync().millisecondsSinceEpoch;
      } catch (_) {}
      if (lastMs > cutoff) {
        continue;
      }
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
  String? preferredLocalPath,
  void Function(double? progress, String message)? onProgress,
}) async {
  final String preferred = (preferredLocalPath ?? '').trim();
  if (isUsableLocalVideoPath(preferred)) {
    final File local = File(preferred);
    unawaited(touchNetdiskMediaAccess(local));
    onProgress?.call(1, '使用已缓存本集');
    return (uri: preferred, headers: null);
  }
  final int? importId = parseNetdiskImportIdFromUrl(playUrl);
  if (importId != null) {
    final File? cached = await findCachedNetdiskMedia(importId);
    if (cached != null) {
      onProgress?.call(1, '使用已缓存本集');
      return (uri: cached.path, headers: null);
    }
  }
  final String? idKey =
      importId?.toString() ?? playUrl.hashCode.toRadixString(16);
  final NetdiskEpisodeCacheInfo? live = netdiskEpisodeCacheInfoForKey(idKey);
  if (live != null &&
      (live.isDownloading || live.isScheduled || live.phase == NetdiskEpisodeCachePhase.partial) &&
      live.progress != null) {
    onProgress?.call(
      live.progress,
      '继续下载本集 ${(live.progress! * 100).round()}%…',
    );
  } else {
    onProgress?.call(0, '正在下载本集以流畅播放…');
  }
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
  } catch (e) {
    // Incomplete download kept as .part — try stream so user can still watch;
    // next open resumes the .part.
    final String msg = '$e';
    onProgress?.call(
      null,
      msg.contains('下载未完成') ? '下载未完成，下次续传；先在线缓冲…' : '下载未完成，改用在线缓冲…',
    );
    return resolveNetdiskPlayableMedia(playUrl);
  }
}

final Set<String> _prefetchInFlightPlayUrls = <String>{};
final Map<String, Future<File>> _netdiskDownloadsInFlight =
    <String, Future<File>>{};
final Map<String, Set<void Function(double? progress)>> _netdiskProgressListeners =
    <String, Set<void Function(double? progress)>>{};
final Map<String, NetdiskEpisodeCacheInfo> _episodeCacheSeed =
    <String, NetdiskEpisodeCacheInfo>{};
NetdiskEpisodeCacheNotifier? _episodeCacheNotifier;

NetdiskEpisodeCacheInfo? netdiskEpisodeCacheInfoForKey(String? key) {
  final String id = (key ?? '').trim();
  if (id.isEmpty) return null;
  return _episodeCacheSeed[id];
}

bool isNetdiskEpisodeDownloadInFlight(String? key) {
  final String id = (key ?? '').trim();
  if (id.isEmpty) return false;
  return _netdiskDownloadsInFlight.containsKey(id);
}

enum NetdiskEpisodeCachePhase {
  remote,
  scheduled,
  partial,
  downloading,
  ready,
}

class NetdiskEpisodeCacheInfo {
  const NetdiskEpisodeCacheInfo({
    required this.phase,
    this.progress,
    this.localPath,
  });

  final NetdiskEpisodeCachePhase phase;
  /// 0–1 when known; null = indeterminate.
  final double? progress;
  final String? localPath;

  String get label {
    switch (phase) {
      case NetdiskEpisodeCachePhase.ready:
        return '已下载';
      case NetdiskEpisodeCachePhase.downloading:
        final double? p = progress;
        if (p == null) return '下载中…';
        return '下载中 ${(p * 100).round()}%';
      case NetdiskEpisodeCachePhase.partial:
        final double? p = progress;
        if (p == null) return '未下完';
        return '未下完 ${(p * 100).round()}%';
      case NetdiskEpisodeCachePhase.scheduled:
        return '已预约下载';
      case NetdiskEpisodeCachePhase.remote:
        return '未下载';
    }
  }

  bool get isReady => phase == NetdiskEpisodeCachePhase.ready;
  bool get isDownloading => phase == NetdiskEpisodeCachePhase.downloading;
  bool get isScheduled => phase == NetdiskEpisodeCachePhase.scheduled;
}

class NetdiskEpisodeCacheNotifier
    extends Notifier<Map<String, NetdiskEpisodeCacheInfo>> {
  @override
  Map<String, NetdiskEpisodeCacheInfo> build() {
    _episodeCacheNotifier = this;
    ref.onDispose(() {
      if (identical(_episodeCacheNotifier, this)) {
        _episodeCacheNotifier = null;
      }
    });
    return Map<String, NetdiskEpisodeCacheInfo>.from(_episodeCacheSeed);
  }

  void put(String key, NetdiskEpisodeCacheInfo info) {
    _episodeCacheSeed[key] = info;
    state = <String, NetdiskEpisodeCacheInfo>{...state, key: info};
  }
}

final NotifierProvider<NetdiskEpisodeCacheNotifier,
        Map<String, NetdiskEpisodeCacheInfo>> netdiskEpisodeCacheProvider =
    NotifierProvider<NetdiskEpisodeCacheNotifier,
        Map<String, NetdiskEpisodeCacheInfo>>(NetdiskEpisodeCacheNotifier.new);

void publishNetdiskEpisodeCache(String key, NetdiskEpisodeCacheInfo info) {
  if (key.trim().isEmpty) return;
  _episodeCacheSeed[key] = info;
  _episodeCacheNotifier?.put(key, info);
}

String? netdiskEpisodeCacheKey(LibraryEpisodeItem episode) {
  return parseNetdiskImportIdFromUrl(episode.videoAsset)?.toString() ??
      parseNetdiskImportIdFromUrl(episode.sourceUrl)?.toString() ??
      parseNetdiskImportIdFromUrl(episode.enSubtitleAsset)?.toString();
}

String? netdiskPlayUrlForEpisode(LibraryEpisodeItem episode) {
  for (final String? raw in <String?>[
    episode.sourceUrl,
    episode.videoAsset,
  ]) {
    final String value = (raw ?? '').trim();
    if (isNetdiskPlayUrl(value)) {
      return value;
    }
  }
  return null;
}

NetdiskEpisodeCacheInfo? netdiskEpisodeCacheOf(
  Map<String, NetdiskEpisodeCacheInfo> map,
  LibraryEpisodeItem episode,
) {
  final String? key = netdiskEpisodeCacheKey(episode);
  if (key == null) return null;
  return map[key] ?? _episodeCacheSeed[key];
}

Future<NetdiskEpisodeCacheInfo> probeNetdiskEpisodeCache(
  LibraryEpisodeItem episode,
) async {
  if (isUsableLocalVideoPath(episode.videoAsset)) {
    return NetdiskEpisodeCacheInfo(
      phase: NetdiskEpisodeCachePhase.ready,
      progress: 1,
      localPath: episode.videoAsset!.trim(),
    );
  }
  final int? importId = parseNetdiskImportIdFromUrl(episode.videoAsset) ??
      parseNetdiskImportIdFromUrl(episode.sourceUrl);
  if (importId == null) {
    return const NetdiskEpisodeCacheInfo(
      phase: NetdiskEpisodeCachePhase.remote,
    );
  }
  final String key = '$importId';
  if (_netdiskDownloadsInFlight.containsKey(key)) {
    return _episodeCacheSeed[key] ??
        const NetdiskEpisodeCacheInfo(
          phase: NetdiskEpisodeCachePhase.downloading,
        );
  }
  final File? cached = await findCachedNetdiskMedia(importId);
  if (cached != null) {
    return NetdiskEpisodeCacheInfo(
      phase: NetdiskEpisodeCachePhase.ready,
      progress: 1,
      localPath: cached.path,
    );
  }
  final Directory dir = await netdiskMediaDirectory();
  final File part = File('${dir.path}/$key.mkv.part');
  if (part.existsSync() && part.lengthSync() > 1024) {
    return NetdiskEpisodeCacheInfo(
      phase: NetdiskEpisodeCachePhase.partial,
      progress: _episodeCacheSeed[key]?.progress,
    );
  }
  // Reservation bookkeeping lives in netdisk_drama_reservation.dart; avoid
  // importing it here (cycle). Callers pass [treatAsScheduled] when known.
  return const NetdiskEpisodeCacheInfo(
    phase: NetdiskEpisodeCachePhase.remote,
  );
}

Future<void> refreshNetdiskEpisodeCacheStates(
  Iterable<LibraryEpisodeItem> episodes, {
  bool Function(LibraryEpisodeItem episode)? isScheduled,
}) async {
  for (final LibraryEpisodeItem ep in episodes) {
    final String? key = netdiskEpisodeCacheKey(ep);
    if (key == null) continue;
    // Don't overwrite live download ticks with a stale probe.
    if (_netdiskDownloadsInFlight.containsKey(key)) continue;
    final NetdiskEpisodeCacheInfo live = await probeNetdiskEpisodeCache(ep);
    if (live.phase == NetdiskEpisodeCachePhase.ready ||
        live.phase == NetdiskEpisodeCachePhase.downloading ||
        live.phase == NetdiskEpisodeCachePhase.partial) {
      publishNetdiskEpisodeCache(key, live);
      continue;
    }
    if (isScheduled?.call(ep) ?? false) {
      publishNetdiskEpisodeCache(
        key,
        const NetdiskEpisodeCacheInfo(
          phase: NetdiskEpisodeCachePhase.scheduled,
        ),
      );
      continue;
    }
    publishNetdiskEpisodeCache(key, live);
  }
}

/// Start / resume one episode from the list page (deduped with player).
Future<File?> enqueueNetdiskEpisodeDownload({
  required LibraryEpisodeItem episode,
  LibraryCatalogNotifier? catalog,
  String? courseId,
}) async {
  final String? playUrl = netdiskPlayUrlForEpisode(episode);
  if (playUrl == null) {
    return null;
  }
  final File file = await cacheNetdiskEpisodeLocally(playUrl: playUrl);
  if (catalog != null && courseId != null && courseId.isNotEmpty) {
    await catalog.updateEpisodeLocalMedia(
      courseId: courseId,
      episodeId: episode.id,
      videoAsset: file.path,
      videoMissing: false,
    );
  }
  return file;
}

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
///
/// Resumes `.part` via HTTP Range when possible, and dedupes concurrent opens
/// of the same episode so closing/reopening does not wipe progress.
Future<File> cacheNetdiskEpisodeLocally({
  required String playUrl,
  void Function(double? progress)? onProgress,
}) async {
  final int? importId = parseNetdiskImportIdFromUrl(playUrl);
  final String idKey = importId?.toString() ??
      playUrl.hashCode.toRadixString(16);

  void emit(double? p) {
    if (onProgress != null) {
      onProgress(p);
    }
  }

  final Set<void Function(double? progress)> listeners =
      _netdiskProgressListeners.putIfAbsent(
    idKey,
    () => <void Function(double? progress)>{},
  );
  listeners.add(emit);

  try {
    final Future<File>? existingJob = _netdiskDownloadsInFlight[idKey];
    if (existingJob != null) {
      // Join in-flight job and inherit current % instead of resetting to 0.
      final double? current = _episodeCacheSeed[idKey]?.progress;
      emit(current);
      publishNetdiskEpisodeCache(
        idKey,
        NetdiskEpisodeCacheInfo(
          phase: NetdiskEpisodeCachePhase.downloading,
          progress: current,
        ),
      );
      final File shared = await existingJob;
      emit(1);
      publishNetdiskEpisodeCache(
        idKey,
        NetdiskEpisodeCacheInfo(
          phase: NetdiskEpisodeCachePhase.ready,
          progress: 1,
          localPath: shared.path,
        ),
      );
      return shared;
    }

    final double? resumeProgress = _episodeCacheSeed[idKey]?.progress;
    publishNetdiskEpisodeCache(
      idKey,
      NetdiskEpisodeCacheInfo(
        phase: NetdiskEpisodeCachePhase.downloading,
        progress: resumeProgress ?? 0,
      ),
    );
    emit(resumeProgress ?? 0);

    late final Future<File> job;
    job = _cacheNetdiskEpisodeLocallyImpl(
      playUrl: playUrl,
      importId: importId,
      idKey: idKey,
      onProgress: (double? p) {
        publishNetdiskEpisodeCache(
          idKey,
          NetdiskEpisodeCacheInfo(
            phase: NetdiskEpisodeCachePhase.downloading,
            progress: p,
          ),
        );
        final Set<void Function(double? progress)>? all =
            _netdiskProgressListeners[idKey];
        if (all != null) {
          for (final void Function(double? progress) listener
              in List<void Function(double? progress)>.from(all)) {
            listener(p);
          }
        }
      },
    );
    _netdiskDownloadsInFlight[idKey] = job;
    try {
      final File file = await job;
      publishNetdiskEpisodeCache(
        idKey,
        NetdiskEpisodeCacheInfo(
          phase: NetdiskEpisodeCachePhase.ready,
          progress: 1,
          localPath: file.path,
        ),
      );
      return file;
    } catch (e) {
      final Directory dir = await netdiskMediaDirectory();
      final File part = File('${dir.path}/$idKey.mkv.part');
      if (part.existsSync() && part.lengthSync() > 1024) {
        publishNetdiskEpisodeCache(
          idKey,
          NetdiskEpisodeCacheInfo(
            phase: NetdiskEpisodeCachePhase.partial,
            progress: _episodeCacheSeed[idKey]?.progress,
          ),
        );
      } else if (_episodeCacheSeed[idKey]?.isScheduled ?? false) {
        publishNetdiskEpisodeCache(
          idKey,
          const NetdiskEpisodeCacheInfo(
            phase: NetdiskEpisodeCachePhase.scheduled,
          ),
        );
      } else {
        publishNetdiskEpisodeCache(
          idKey,
          const NetdiskEpisodeCacheInfo(
            phase: NetdiskEpisodeCachePhase.remote,
          ),
        );
      }
      rethrow;
    } finally {
      if (identical(_netdiskDownloadsInFlight[idKey], job)) {
        _netdiskDownloadsInFlight.remove(idKey);
      }
    }
  } finally {
    listeners.remove(emit);
    if (listeners.isEmpty) {
      _netdiskProgressListeners.remove(idKey);
    }
  }
}

Future<File> _cacheNetdiskEpisodeLocallyImpl({
  required String playUrl,
  required int? importId,
  required String idKey,
  void Function(double? progress)? onProgress,
}) async {
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
  if (out.existsSync() && out.lengthSync() > 64 * 1024) {
    await touchNetdiskMediaAccess(out);
    onProgress?.call(1);
    return out;
  }
  final File temp = File('${out.path}.part');
  final String url = absoluteNetdiskPlayUrl(playUrl);
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(hours: 2),
      followRedirects: true,
      maxRedirects: 10,
      headers: <String, dynamic>{...kNetdiskStreamHeaders},
      validateStatus: (int? s) => s != null && (s == 200 || s == 206),
    ),
  );

  int? expectedTotal;
  try {
    final Response<void> head = await dio.head<void>(url);
    expectedTotal = int.tryParse(
      head.headers.value(Headers.contentLengthHeader) ?? '',
    );
  } catch (_) {}

  int offset = temp.existsSync() ? temp.lengthSync() : 0;
  if (expectedTotal != null &&
      expectedTotal > 64 * 1024 &&
      offset >= expectedTotal) {
    if (out.existsSync()) {
      await out.delete();
    }
    await temp.rename(out.path);
    await touchNetdiskMediaAccess(out);
    onProgress?.call(1);
    return out;
  }
  // Surface resumed .part progress immediately (avoid UI jumping back to 0%).
  if (offset > 0 && expectedTotal != null && expectedTotal > 0) {
    onProgress?.call((offset / expectedTotal).clamp(0.0, 0.99));
  } else if (offset > 0) {
    onProgress?.call(null);
  }

  // Server ignored / rejected Range → restart clean.
  // Important: on resume we ONLY accept 206. A 200 + append would corrupt .part.
  for (int attempt = 0; attempt < 2; attempt++) {
    final bool resume = offset > 0;
    int lastPercent = -1;
    try {
      await dio.download(
        url,
        temp.path,
        options: Options(
          headers: <String, dynamic>{
            ...kNetdiskStreamHeaders,
            if (resume) 'Range': 'bytes=$offset-',
          },
          validateStatus: (int? s) {
            if (s == null) return false;
            if (resume) return s == 206;
            return s == 200 || s == 206;
          },
        ),
        deleteOnError: false,
        fileAccessMode:
            resume ? FileAccessMode.append : FileAccessMode.write,
        onReceiveProgress: (int received, int total) {
          final int got = offset + received;
          final int? full = expectedTotal ??
              (total > 0 ? (resume ? offset + total : total) : null);
          if (full == null || full <= 0) {
            onProgress?.call(null);
            return;
          }
          final int percent = ((got / full) * 100).floor().clamp(0, 100);
          if (percent == lastPercent) {
            return;
          }
          lastPercent = percent;
          onProgress?.call((got / full).clamp(0.0, 1.0));
        },
      );
      break;
    } on DioException catch (e) {
      final int? code = e.response?.statusCode;
      if (resume &&
          (code == 200 ||
              code == 416 ||
              code == 501 ||
              e.type == DioExceptionType.badResponse)) {
        try {
          if (temp.existsSync()) {
            await temp.delete();
          }
        } catch (_) {}
        offset = 0;
        continue;
      }
      // Keep .part on cancel / network drop so reopen can resume.
      rethrow;
    }
  }

  if (!temp.existsSync() || temp.lengthSync() < 64 * 1024) {
    if (temp.existsSync()) {
      await temp.delete();
    }
    throw StateError('下载文件过小或失败');
  }
  if (expectedTotal != null &&
      expectedTotal > 64 * 1024 &&
      temp.lengthSync() + 1024 < expectedTotal) {
    // Incomplete — keep .part for next resume; do not rename.
    throw StateError('下载未完成，已保存进度，下次继续');
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
  if (course.id.startsWith('netdisk-series-') ||
      course.id.startsWith('public-series-')) {
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

/// Formerly auto-opened landscape for netdisk drama; kept for call-site
/// compatibility. Portrait is the default — user rotates / taps fullscreen.
bool prefersNetdiskLandscapePlayback(LibraryCourseData? course) {
  return false;
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
  return course.episodes.where((LibraryEpisodeItem e) {
    if (isUsableLocalVideoPath(e.videoAsset)) {
      return false;
    }
    final String? key = netdiskEpisodeCacheKey(e);
    if (key != null && (_episodeCacheSeed[key]?.isReady ?? false)) {
      return false;
    }
    return true;
  }).length;
}

/// Write API softsubs for a netdisk import onto disk and catalog.
///
/// [allowOnlineFetch] triggers Shooter/Subliminal when EN is missing. Keep it
/// false on player cold-open — that path can take tens of seconds and freeze
/// 美剧（哈利波特）开播；online refill belongs in import/download flows.
Future<void> materializeNetdiskSoftsubs({
  required AcquireApiClient api,
  required LibraryCatalogNotifier catalog,
  required String courseId,
  LibraryEpisodeItem? episode,
  int? importId,
  bool allowOnlineFetch = true,
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
  String? enBody = await api.fetchPersonalImportSrt(
    importId: resolvedId,
    lang: 'en',
  );
  // Older imports may predate Subliminal — ask API to match online EN once.
  if (allowOnlineFetch && (enBody == null || enBody.trim().isEmpty)) {
    final bool filled = await api.fetchNetdiskOnlineSubtitles(
      importId: resolvedId,
    );
    if (filled) {
      enBody = await api.fetchPersonalImportSrt(
        importId: resolvedId,
        lang: 'en',
      );
    }
  }
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
  // Same resume / in-flight path as playback prepare (netdisk_media/{importId}.mkv).
  // idKey retained for call-site compatibility; cache key is import id from URL.
  assert(idKey.isNotEmpty);
  return cacheNetdiskEpisodeLocally(
    playUrl: playUrl,
    onProgress: onProgress,
  );
}
