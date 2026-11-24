import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../membership/domain/module_access.dart';
import '../../sync/presentation/user_assets_provider.dart';
import '../domain/youtube_import.dart';
import 'bilibili_episode_prepare.dart' show isUsableLocalVideoPath;
import 'youtube_import_service.dart';

/// Import only source metadata, then open the first episode for streaming.
Future<bool> importYoutubeVideoById(
  BuildContext context,
  WidgetRef ref, {
  required String videoId,
  String level = 'A2',
  bool closeSheetOnSuccess = false,
}) async {
  final playlist = YoutubeImport.extractPlaylistId(videoId);
  final id = YoutubeImport.extractVideoId(videoId);
  if (id == null && playlist == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无效的 YouTube 视频或合集')));
    return false;
  }

  final router = GoRouter.of(context);
  void open(String episodeId) {
    if (!context.mounted) return;
    if (closeSheetOnSuccess) Navigator.of(context).pop();
    router.push('/episodes/$episodeId?preview=1');
  }

  final courseId = playlist == null
      ? 'youtube-$id'
      : 'youtube-playlist-$playlist';
  final service = const YoutubeImportService();
  try {
    final existing = ref
        .read(libraryCatalogProvider)
        .where((course) => course.id == courseId)
        .firstOrNull;
    if (existing != null && existing.episodes.isNotEmpty) {
      open(existing.episodes.first.id);
      return true;
    }
    final String title;
    final List<YoutubeImportResult> videos;
    if (playlist == null) {
      final video = await service
          .fetch(id!, includeSubtitles: false)
          .timeout(const Duration(seconds: 25));
      title = video.title;
      videos = [video];
    } else {
      final result = await service
          .fetchPlaylist(playlist)
          .timeout(const Duration(seconds: 35));
      title = result.title;
      videos = result.videos;
    }
    if (!context.mounted) return false;
    if (videos.isEmpty) throw StateError('此合集没有可播放的公开视频');
    const cover = 'assets/img/app_icon.png';
    final course = LibraryCourseData(
      id: courseId,
      title: title,
      description: playlist == null ? videos.first.watchUrl : videoId,
      sourceLabel: 'YouTube',
      coverImage: cover,
      level: level,
      category: 'youtube',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: videos.length,
      lastStudiedStr: '未学习',
      rating: 0,
      episodes: [
        for (final (index, video) in videos.indexed)
          LibraryEpisodeItem(
            id: '$courseId-${(index + 1).toString().padLeft(2, '0')}',
            numberStr: (index + 1).toString().padLeft(2, '0'),
            title: video.title,
            durationMinutes: video.durationMinutes,
            hasChineseSubtitles: false,
            hasEnglishSubtitles: false,
            completed: false,
            progressPercent: 0,
            coverImage: cover,
            videoAsset: video.watchUrl,
            sourceUrl: video.watchUrl,
          ),
      ],
    );
    try {
      await ref.read(userAssetsProvider.notifier).refresh();
    } catch (_) {}
    if (!context.mounted) return false;
    final unlimited = await resolveModuleUnlocked(ref, 'video');
    if (!context.mounted) return false;
    final ok = await ref
        .read(libraryCatalogProvider.notifier)
        .importCourse(course, unlimitedPersonalLibrary: unlimited);
    if (ok) open(course.episodes.first.id);
    return ok;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开 YouTube，请确认网络可访问 YouTube。$error')),
      );
    }
    return false;
  }
}

final Set<String> _downloadingYoutubeCollections = {};

Future<void> downloadYoutubeCollection(
  BuildContext context,
  WidgetRef ref,
  LibraryCourseData course,
) async {
  if (!_downloadingYoutubeCollections.add(course.id)) return;
  final messenger = ScaffoldMessenger.of(context);
  final catalog = ref.read(libraryCatalogProvider.notifier);
  final service = const YoutubeImportService();
  var failed = 0;
  messenger.showSnackBar(const SnackBar(content: Text('开始下载 YouTube 合集')));
  try {
    for (final episode in course.episodes) {
      if (isUsableLocalVideoPath(episode.videoAsset)) continue;
      final id = YoutubeImport.extractVideoId(episode.sourceUrl ?? '');
      try {
        final local = id == null ? null : await service.downloadLocalVideo(id);
        if (local == null) {
          failed++;
          continue;
        }
        await catalog.updateEpisodeLocalMedia(
          courseId: course.id,
          episodeId: episode.id,
          videoAsset: local,
          videoMissing: false,
        );
      } catch (_) {
        failed++;
      }
    }
    if (messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(failed == 0 ? '合集已下载' : '下载结束，$failed 集未成功，可重试'),
        ),
      );
    }
  } finally {
    _downloadingYoutubeCollections.remove(course.id);
  }
}
