import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../membership/domain/module_access.dart';
import '../../subtitle_completion/subtitle_completion_enqueue.dart';
import '../../subtitle_completion/subtitle_completion_scheduler.dart';
import '../../sync/presentation/user_assets_provider.dart';
import '../domain/youtube_import.dart';
import 'bilibili_episode_prepare.dart';
import 'youtube_import_service.dart';

/// Import a YouTube video by id (requires working YouTube access / VPN).
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
    YoutubeImportResult meta = await service.fetch(id);
    final String courseId = 'youtube-${meta.videoId}';
    final bool hasEn = meta.enSubtitlePath != null;
    final bool hasZh = meta.cnSubtitlePath != null;
    if (!hasEn || !hasZh) {
      final String? local = await service.downloadLocalVideo(meta.videoId);
      if (local != null) {
        meta = meta.copyWith(localVideoPath: local);
      }
    }
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
    final bool canLocalAsr = course.episodes.any(
      (LibraryEpisodeItem ep) => isUsableLocalVideoPath(ep.videoAsset),
    );
    if (ok && (!hasEn || !hasZh) && canLocalAsr) {
      await enqueueSubtitleCompletionForCourse(course: course);
      SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
    }
    if (!context.mounted) return ok;
    final String subtitleHint;
    if (hasEn && hasZh) {
      subtitleHint = '中英字幕已就绪。';
    } else if (!canLocalAsr) {
      subtitleHint = !hasEn && !hasZh
          ? '缺中英字幕；未能下载本地视频，请稍后重试补全。'
          : (!hasEn ? '缺英文字幕；未能下载本地视频。' : '缺中文字幕；未能下载本地视频。');
    } else {
      subtitleHint = !hasEn && !hasZh
          ? '缺中英字幕，已下载并开始后台 ASR 补全。'
          : (!hasEn
              ? '缺英文字幕，已下载并开始后台 ASR 补全。'
              : '缺中文字幕，已下载并开始后台 ASR 补全。');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '已加入书库。$subtitleHint'
              : '该书库中已有此 YouTube 课程',
        ),
      ),
    );
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
