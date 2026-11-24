import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

import '../../idle_jobs/idle_job_queue.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import 'bilibili_episode_prepare.dart';
import 'netdisk_local_download.dart';

const String kNetdiskDramaReservationsKey = 'netdisk_drama_reservations_v1';

/// Persisted booking so idle drain can resolve play URL without UI context.
class NetdiskDramaReservation {
  const NetdiskDramaReservation({
    required this.episodeId,
    required this.courseId,
    required this.playUrl,
    this.title = '',
    this.importId,
  });

  factory NetdiskDramaReservation.fromJson(Map<String, dynamic> json) {
    return NetdiskDramaReservation(
      episodeId: (json['episodeId'] as String? ?? '').trim(),
      courseId: (json['courseId'] as String? ?? '').trim(),
      playUrl: (json['playUrl'] as String? ?? '').trim(),
      title: (json['title'] as String? ?? '').trim(),
      importId: (json['importId'] as num?)?.toInt(),
    );
  }

  final String episodeId;
  final String courseId;
  final String playUrl;
  final String title;
  final int? importId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'episodeId': episodeId,
        'courseId': courseId,
        'playUrl': playUrl,
        'title': title,
        if (importId != null) 'importId': importId,
      };
}

Map<String, NetdiskDramaReservation> loadNetdiskDramaReservations() {
  if (!Hive.isBoxOpen('prefs')) {
    return <String, NetdiskDramaReservation>{};
  }
  final String raw =
      Hive.box<String>('prefs').get(kNetdiskDramaReservationsKey) ?? '';
  if (raw.trim().isEmpty) {
    return <String, NetdiskDramaReservation>{};
  }
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <String, NetdiskDramaReservation>{};
    }
    final Map<String, NetdiskDramaReservation> out =
        <String, NetdiskDramaReservation>{};
    decoded.forEach((Object? key, Object? value) {
      if (key == null || value is! Map) return;
      final NetdiskDramaReservation row = NetdiskDramaReservation.fromJson(
        value.map((Object? k, Object? v) => MapEntry('$k', v)),
      );
      if (row.episodeId.isEmpty || row.playUrl.isEmpty) return;
      out[row.episodeId] = row;
    });
    return out;
  } catch (_) {
    return <String, NetdiskDramaReservation>{};
  }
}

Future<void> _saveNetdiskDramaReservations(
  Map<String, NetdiskDramaReservation> map,
) async {
  if (!Hive.isBoxOpen('prefs')) return;
  await Hive.box<String>('prefs').put(
    kNetdiskDramaReservationsKey,
    jsonEncode(
      map.map(
        (String k, NetdiskDramaReservation v) => MapEntry(k, v.toJson()),
      ),
    ),
  );
}

bool isNetdiskDramaEpisodeReserved(String episodeId) {
  final String id = episodeId.trim();
  if (id.isEmpty) return false;
  if (IdleJobQueue.shared.isPending(
    kind: IdleJobKind.netdiskDrama,
    key: id,
  )) {
    return true;
  }
  return loadNetdiskDramaReservations().containsKey(id);
}

/// Book one episode for idle / resume download (does not block on netdisk).
Future<bool> scheduleNetdiskDramaEpisode({
  required LibraryEpisodeItem episode,
  required String courseId,
}) async {
  final String? playUrl = netdiskPlayUrlForEpisode(episode);
  if (playUrl == null || playUrl.isEmpty) {
    return false;
  }
  if (isUsableLocalVideoPath(episode.videoAsset)) {
    final String? key = netdiskEpisodeCacheKey(episode);
    if (key != null) {
      publishNetdiskEpisodeCache(
        key,
        NetdiskEpisodeCacheInfo(
          phase: NetdiskEpisodeCachePhase.ready,
          progress: 1,
          localPath: episode.videoAsset!.trim(),
        ),
      );
    }
    return true;
  }
  final int? importId = parseNetdiskImportIdFromUrl(playUrl) ??
      parseNetdiskImportIdFromUrl(episode.videoAsset);
  final Map<String, NetdiskDramaReservation> map =
      loadNetdiskDramaReservations();
  map[episode.id] = NetdiskDramaReservation(
    episodeId: episode.id,
    courseId: courseId,
    playUrl: playUrl,
    title: episode.title,
    importId: importId,
  );
  await _saveNetdiskDramaReservations(map);
  await IdleJobQueue.shared.enqueue(
    kind: IdleJobKind.netdiskDrama,
    key: episode.id,
  );
  final String? key = netdiskEpisodeCacheKey(episode) ??
      (importId != null ? '$importId' : null);
  if (key != null) {
    publishNetdiskEpisodeCache(
      key,
      const NetdiskEpisodeCacheInfo(
        phase: NetdiskEpisodeCachePhase.scheduled,
      ),
    );
  }
  return true;
}

Future<void> cancelNetdiskDramaEpisode(String episodeId) async {
  final String id = episodeId.trim();
  if (id.isEmpty) return;
  final Map<String, NetdiskDramaReservation> map =
      loadNetdiskDramaReservations();
  final NetdiskDramaReservation? row = map.remove(id);
  await _saveNetdiskDramaReservations(map);
  await IdleJobQueue.shared.cancel('${IdleJobKind.netdiskDrama.name}:$id');
  final String? cacheKey = row?.importId?.toString() ??
      (row != null ? parseNetdiskImportIdFromUrl(row.playUrl)?.toString() : null);
  if (cacheKey != null) {
    publishNetdiskEpisodeCache(
      cacheKey,
      const NetdiskEpisodeCacheInfo(
        phase: NetdiskEpisodeCachePhase.remote,
      ),
    );
  }
}

/// Drain one reserved episode (idle / app resume). Returns true if work ran.
Future<bool> drainOneNetdiskDramaReservation({
  required IdleJob job,
  LibraryCatalogNotifier? catalog,
}) async {
  if (job.kind != IdleJobKind.netdiskDrama) {
    return false;
  }
  final String episodeId = job.key.trim();
  final Map<String, NetdiskDramaReservation> map =
      loadNetdiskDramaReservations();
  NetdiskDramaReservation? row = map[episodeId];
  String? playUrl = row?.playUrl;
  String courseId = row?.courseId ?? '';

  if ((playUrl == null || playUrl.isEmpty) && catalog != null) {
    for (final LibraryCourseData course in catalog.state) {
      for (final LibraryEpisodeItem ep in course.episodes) {
        if (ep.id != episodeId) continue;
        playUrl = netdiskPlayUrlForEpisode(ep);
        courseId = course.id;
        break;
      }
      if (playUrl != null && playUrl.isNotEmpty) break;
    }
  }
  if (playUrl == null || playUrl.isEmpty) {
    map.remove(episodeId);
    await _saveNetdiskDramaReservations(map);
    await IdleJobQueue.shared.markFailed(job.id, 'missing play url');
    return true;
  }

  final String? cacheKey =
      parseNetdiskImportIdFromUrl(playUrl)?.toString() ??
          row?.importId?.toString();
  try {
    if (cacheKey != null) {
      publishNetdiskEpisodeCache(
        cacheKey,
        const NetdiskEpisodeCacheInfo(
          phase: NetdiskEpisodeCachePhase.downloading,
          progress: 0,
        ),
      );
    }
    final File file = await cacheNetdiskEpisodeLocally(playUrl: playUrl);
    if (catalog != null && courseId.isNotEmpty) {
      await catalog.updateEpisodeLocalMedia(
        courseId: courseId,
        episodeId: episodeId,
        videoAsset: file.path,
        videoMissing: false,
      );
    }
    map.remove(episodeId);
    await _saveNetdiskDramaReservations(map);
    await IdleJobQueue.shared.markDone(job.id);
    return true;
  } catch (e) {
    if (cacheKey != null) {
      publishNetdiskEpisodeCache(
        cacheKey,
        const NetdiskEpisodeCacheInfo(
          phase: NetdiskEpisodeCachePhase.scheduled,
        ),
      );
    }
    await IdleJobQueue.shared.markFailed(job.id, '$e');
    // Keep reservation so a later idle pass can retry.
    await IdleJobQueue.shared.enqueue(
      kind: IdleJobKind.netdiskDrama,
      key: episodeId,
    );
    return true;
  }
}

