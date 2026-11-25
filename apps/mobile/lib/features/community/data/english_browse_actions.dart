import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../import_course/data/bilibili_course_builder.dart';
import '../../import_course/data/bilibili_episode_prepare.dart';
import '../../import_course/data/bilibili_import_service.dart';
import '../../import_course/data/bilibili_multipage.dart';
import '../../import_course/data/bilibili_open_or_import.dart';
import '../../import_course/domain/bilibili_import.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../membership/domain/free_trial_seeds.dart';
import '../../membership/domain/module_access.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../../router/app_router.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../subtitle_completion/shared_bilibili_subtitle_sync.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/user_assets_provider.dart';
import 'english_browse_store.dart';

/// Silent metadata import (no download) then online preview.
Future<String?> ensureEnglishBrowseEpisode(
  WidgetRef ref, {
  required AcquireDailyFeedItemDto item,
}) async {
  final String url = item.watchUrl.trim();
  if (url.isEmpty) return null;

  final Map<String, String>? ids = BilibiliImport.extractIds(url);
  final String bvid = (ids?['bvid'] ?? item.bvid).trim();
  final bool seedFree = bvid.isNotEmpty && isFreeTrialBilibiliBvid(bvid);
  if (!seedFree) {
    final bool unlocked = await resolveModuleUnlocked(ref, 'video');
    if (!unlocked) return null;
  }

  final hit = findLibraryEpisodeForBilibiliInput(
    ref.read(libraryCatalogProvider),
    url,
  );
  if (hit != null) return hit.episode.id;

  final LearningSettingsState settings = ref.read(learningSettingsProvider);
  final BilibiliImportService service = BilibiliImportService.withCookie(
    settings.resolvedBilibiliCookieHeader,
  );
  final BilibiliImportResult meta = await service.fetch(
    url,
    includeSubtitles: false,
  );
  final LibraryCourseData course = buildLibraryCourseFromBilibiliImport(meta);
  final LibraryEpisodeItem? episode = course.episodes.firstOrNull;
  if (episode == null) return null;
  try {
    await ref.read(userAssetsProvider.notifier).refresh();
  } catch (_) {}
  final bool unlimited = await resolveModuleUnlocked(ref, 'video');
  final bool ok = await ref.read(libraryCatalogProvider.notifier).importCourse(
        course,
        unlimitedPersonalLibrary: unlimited,
      );
  if (!ok) return null;
  return episode.id;
}

/// 全英可逛：默认在线播 → 退出问是否喜欢 → 喜欢则下载并预约字幕。
Future<void> openEnglishBrowsePreview(
  BuildContext context,
  WidgetRef ref, {
  required AcquireDailyFeedItemDto item,
}) async {
  final String url = item.watchUrl.trim();
  if (url.isEmpty) return;

  final Map<String, String>? ids = BilibiliImport.extractIds(url);
  final String bvid = (ids?['bvid'] ?? item.bvid).trim();
  final bool seedFree = bvid.isNotEmpty && isFreeTrialBilibiliBvid(bvid);
  if (!seedFree) {
    final bool unlocked = await resolveModuleUnlocked(ref, 'video');
    if (!unlocked) {
      if (context.mounted) {
        await showModulePaywall(context, moduleCode: 'video');
      }
      return;
    }
  }

  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('正在打开在线试看…'),
            ],
          ),
        ),
      ),
    ),
  );

  String? episodeId;
  try {
    episodeId = await ensureEnglishBrowseEpisode(ref, item: item);
  } catch (error) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开失败：$error')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  if (episodeId == null || episodeId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暂时无法打开这集，请稍后重试')),
    );
    return;
  }

  String courseId = '';
  for (final LibraryCourseData c in ref.read(libraryCatalogProvider)) {
    if (c.episodes.any((LibraryEpisodeItem e) => e.id == episodeId)) {
      courseId = c.id;
      break;
    }
  }

  await ref.read(englishBrowseStoreProvider.notifier).recordPlay(
        EnglishBrowseEntry.fromFeed(
          item,
          episodeId: episodeId,
          courseId: courseId,
        ),
      );
  ref.read(lastLearningEpisodeProvider.notifier).record(episodeId);

  if (!context.mounted) return;
  await context.pushNamed<void>(
    SGRoute.player.name,
    pathParameters: <String, String>{'episodeId': episodeId},
    queryParameters: <String, String>{'preview': '1', 'autoplay': '1'},
  );
  if (!context.mounted) return;

  final bool? liked = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: AppDesignTokens.appWhite,
        title: const Text('喜欢这集吗？'),
        content: Text(
          '喜欢会下载本集并自动预约中英字幕，加入长期学习列表。\n不喜欢只保留在播放记录里。',
          style: TextStyle(color: AppDesignTokens.textSecondary, height: 1.4),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('不喜欢'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('喜欢'),
          ),
        ],
      );
    },
  );

  if (!context.mounted) return;
  if (liked == true) {
    await promoteEnglishBrowseToStudy(
      context,
      ref,
      item: item,
      episodeId: episodeId,
      courseId: courseId,
    );
  } else if (liked == false) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已记入播放记录')),
    );
  }
}

Future<void> promoteEnglishBrowseToStudy(
  BuildContext context,
  WidgetRef ref, {
  required AcquireDailyFeedItemDto item,
  required String episodeId,
  required String courseId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(content: Text('正在下载本集并预约字幕…')),
  );

  await ref.read(englishBrowseStoreProvider.notifier).markStudy(
        watchUrl: item.watchUrl,
        liked: true,
        favorited: true,
        episodeId: episodeId,
        courseId: courseId,
        title: item.title,
        bvid: item.bvid,
        coverUrl: item.coverUrl,
        author: item.author,
      );

  LibraryCourseData? course;
  LibraryEpisodeItem? episode;
  for (final LibraryCourseData c in ref.read(libraryCatalogProvider)) {
    for (final LibraryEpisodeItem e in c.episodes) {
      if (e.id == episodeId) {
        course = c;
        episode = e;
        break;
      }
    }
  }

  // Download current episode locally (keep watch URL as sourceUrl).
  try {
    if (course != null && episode != null) {
      final LearningSettingsState settings = ref.read(learningSettingsProvider);
      final BilibiliImportService service = BilibiliImportService.withCookie(
        settings.resolvedBilibiliCookieHeader,
      );
      final String source = bilibiliSourceForEpisode(
            course: course,
            episode: episode,
            videoAsset: episode.videoAsset,
          ) ??
          episode.sourceUrl ??
          item.watchUrl;
      final String localPath = await service.ensureLocalCacheForAsr(source);
      if (isUsableLocalVideoPath(localPath)) {
        await ref.read(libraryCatalogProvider.notifier).updateEpisodeLocalMedia(
              courseId: course.id,
              episodeId: episode.id,
              videoAsset: localPath,
              sourceUrl: source,
              videoMissing: false,
            );
      }
    }
  } catch (_) {}

  // Auto-reserve bilingual softsubs for this page.
  try {
    await _reserveCurrentPage(
      ref,
      watchUrl: item.watchUrl,
      episodeId: episodeId,
    );
    await ref.read(englishBrowseStoreProvider.notifier).markStudy(
          watchUrl: item.watchUrl,
          reserved: true,
          episodeId: episodeId,
          courseId: courseId,
        );
  } catch (_) {}

  if (!context.mounted) return;
  messenger.showSnackBar(
    const SnackBar(content: Text('已加入学习列表：本集下载中，字幕已预约')),
  );
}

Future<void> favoriteEnglishBrowseItem(
  WidgetRef ref, {
  required AcquireDailyFeedItemDto item,
  String episodeId = '',
  String courseId = '',
}) async {
  await ref.read(englishBrowseStoreProvider.notifier).markStudy(
        watchUrl: item.watchUrl,
        favorited: true,
        episodeId: episodeId,
        courseId: courseId,
        title: item.title,
        bvid: item.bvid,
        coverUrl: item.coverUrl,
        author: item.author,
      );
}

Future<void> _reserveCurrentPage(
  WidgetRef ref, {
  required String watchUrl,
  required String episodeId,
}) async {
  if (!ref.read(authSessionProvider).isLoggedIn) {
    throw StateError('请先登录再预约字幕');
  }
  final api = ref.read(acquireApiClientProvider);
  final service = BilibiliImportService.withCookie(
    ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader,
  );
  LibraryCourseData? course;
  LibraryEpisodeItem? episode;
  for (final LibraryCourseData c in ref.read(libraryCatalogProvider)) {
    for (final LibraryEpisodeItem e in c.episodes) {
      if (e.id == episodeId) {
        course = c;
        episode = e;
        break;
      }
    }
  }
  final String source = episode == null
      ? watchUrl
      : (bilibiliSourceForEpisode(
            course: course!,
            episode: episode,
            videoAsset: episode.videoAsset,
          ) ??
          episode.sourceUrl ??
          watchUrl);
  final identity = course == null || episode == null
      ? null
      : resolveBilibiliSharedSubtitleIds(
          course: course,
          episode: episode,
          sourceUrl: source,
        );
  final String? bvid =
      identity?.bvid ??
      (BilibiliImport.extractIds(source)?['bvid']) ??
      (await service.resolveIds(source))?['bvid'];
  if (bvid == null || bvid.isEmpty) {
    throw StateError('无法识别视频 BV');
  }
  final int page = identity?.page ?? BilibiliImport.extractPage(source) ?? 1;
  final SharedSubtitleGpuJob? job = await api.enqueueSharedSubtitleJob(
    bvid: bvid,
    page: page,
    reserve: true,
    reportErrors: true,
  );
  if (job == null || job.id.isEmpty || job.isTerminalFailure) {
    throw StateError('预约字幕未提交');
  }
  if (Hive.isBoxOpen('prefs')) {
    final String email =
        ref.read(authSessionProvider).email.trim().toLowerCase();
    final String key = 'bilibili-reservation:$email:src:bili:$bvid:$page';
    await Hive.box<String>('prefs').put(key, job.id);
    if (job.state == 'completed') {
      await Hive.box<String>('prefs').put('$key:ready', '1');
    }
  }
}
