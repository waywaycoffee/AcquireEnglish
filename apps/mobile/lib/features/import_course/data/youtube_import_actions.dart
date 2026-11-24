import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../membership/domain/module_access.dart';
import '../../sync/presentation/user_assets_provider.dart';
import '../domain/youtube_import.dart';
import 'youtube_import_service.dart';

/// Open an existing YouTube lesson or import it and open the player.
Future<bool> importYoutubeVideoById(
  BuildContext context,
  WidgetRef ref, {
  required String videoId,
  String level = 'A2',
}) async {
  final String? id = YoutubeImport.extractVideoId(videoId) ??
      (RegExp(r'^[A-Za-z0-9_-]{6,}$').hasMatch(videoId) ? videoId : null);
  if (id == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无效的 YouTube 视频')),
      );
    }
    return false;
  }

  final YoutubeImportService service = const YoutubeImportService();
  try {
    final existing = ref.read(libraryCatalogProvider).where(
      (course) => course.id == 'youtube-$id',
    ).firstOrNull;
    if (existing != null && existing.episodes.isNotEmpty) {
      if (context.mounted) context.push('/episodes/${existing.episodes.first.id}');
      return true;
    }
    final YoutubeImportResult meta = await service.fetch(id).timeout(
      const Duration(seconds: 25),
    );
    if (!context.mounted) return false;
    final String courseId = 'youtube-${meta.videoId}';
    final bool hasEn = meta.enSubtitlePath != null;
    final bool hasZh = meta.cnSubtitlePath != null;
    final String videoAsset = meta.localVideoPath ?? meta.watchUrl;
    final LibraryCourseData course = LibraryCourseData(
      id: courseId,
      title: meta.title,
      description: meta.author == null
          ? meta.watchUrl
          : '${meta.author} · ${meta.watchUrl}',
      sourceLabel: 'YouTube',
      coverImage: 'assets/img/app_icon.png',
      level: level,
      category: 'youtube',
      progressPercent: 0,
      totalWords: 0,
      completedEpisodes: 0,
      totalEpisodes: 1,
      lastStudiedStr: '未学习',
      rating: 0,
      episodes: <LibraryEpisodeItem>[
        LibraryEpisodeItem(
          id: '$courseId-01',
          numberStr: '01',
          title: meta.title,
          durationMinutes: meta.durationMinutes,
          hasChineseSubtitles: hasZh,
          hasEnglishSubtitles: hasEn,
          completed: false,
          progressPercent: 0,
          coverImage: 'assets/img/app_icon.png',
          videoAsset: videoAsset,
          sourceUrl: meta.watchUrl,
          enSubtitleAsset: meta.enSubtitlePath,
          cnSubtitleAsset: meta.cnSubtitlePath,
          subtitleTracks: <LibrarySubtitleTrackItem>[
            if (hasEn)
              LibrarySubtitleTrackItem(
                languageCode: 'en',
                languageLabel: 'English',
                path: meta.enSubtitlePath!,
              ),
            if (hasZh)
              LibrarySubtitleTrackItem(
                languageCode: 'zh',
                languageLabel: '中文',
                path: meta.cnSubtitlePath!,
              ),
          ],
        ),
      ],
    );
    try {
      await ref.read(userAssetsProvider.notifier).refresh();
    } catch (_) {}
    final bool unlimited = await resolveModuleUnlocked(ref, 'video');
    final bool ok = await ref
        .read(libraryCatalogProvider.notifier)
        .importCourse(course, unlimitedPersonalLibrary: unlimited);
    if (!context.mounted) return ok;
    if (ok) {
      context.push('/episodes/$courseId-01');
    }
    return ok;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '导入失败（需可用梯子访问 YouTube）：$e',
          ),
        ),
      );
    }
    return false;
  }
}
