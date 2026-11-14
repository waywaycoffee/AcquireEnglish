import 'dart:developer' as developer;
import 'dart:io';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import 'bilibili_import_service.dart';
import 'bilibili_multipage.dart';

bool _isMissingEpisodeCover(String cover) {
  final String value = cover.trim();
  if (value.isEmpty || value.startsWith('assets/')) {
    return true;
  }
  if (value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('//')) {
    return false;
  }
  try {
    return !File(value).existsSync();
  } catch (_) {
    return true;
  }
}

bool _isUsableCover(String cover) {
  return !_isMissingEpisodeCover(cover);
}

bool _isBilibiliCourse(LibraryCourseData course) {
  return course.category == 'bilibili' ||
      course.sourceLabel.toLowerCase().contains('bilibili') ||
      course.id.startsWith('bilibili-');
}

/// Fill missing episode posters for a Bilibili course.
///
/// 1. Immediately stamp the course cover onto empty episode covers (UI win).
/// 2. Then resolve each episode's own cover from its BV/watch URL.
Future<void> backfillBilibiliEpisodeCovers({
  required LibraryCatalogNotifier catalog,
  required List<LibraryCourseData> Function() readCourses,
  required String courseId,
  required BilibiliImportService service,
}) async {
  LibraryCourseData? target;
  for (final LibraryCourseData course in readCourses()) {
    if (course.id == courseId) {
      target = course;
      break;
    }
  }
  if (target == null || !_isBilibiliCourse(target)) {
    return;
  }

  final String courseCover = target.coverImage.trim();
  if (_isUsableCover(courseCover)) {
    for (final LibraryEpisodeItem episode in target.episodes) {
      if (!_isMissingEpisodeCover(episode.coverImage)) {
        continue;
      }
      await catalog.updateEpisodeLocalMedia(
        courseId: courseId,
        episodeId: episode.id,
        coverImage: courseCover,
      );
    }
  }

  // Re-read after course-cover stamp.
  target = null;
  for (final LibraryCourseData course in readCourses()) {
    if (course.id == courseId) {
      target = course;
      break;
    }
  }
  if (target == null) {
    return;
  }

  for (final LibraryEpisodeItem episode in target.episodes) {
    final String? source = bilibiliSourceForEpisode(
      course: target,
      episode: episode,
      videoAsset: episode.videoAsset,
    );
    if (source == null || source.trim().isEmpty) {
      continue;
    }
    try {
      final String? cover = await service.resolveCoverImage(source);
      if (cover == null || !_isUsableCover(cover)) {
        continue;
      }
      // Skip write when already the same usable cover.
      if (episode.coverImage.trim() == cover.trim()) {
        continue;
      }
      await catalog.updateEpisodeLocalMedia(
        courseId: courseId,
        episodeId: episode.id,
        coverImage: cover,
      );
      developer.log(
        'episode cover backfill ${episode.id} -> $cover',
        name: 'bilibili.cover',
      );
    } catch (e, st) {
      developer.log(
        'episode cover backfill failed ${episode.id}: $e',
        name: 'bilibili.cover',
        error: e,
        stackTrace: st,
      );
    }
  }

  // If course cover itself is missing, lift the first usable episode cover.
  LibraryCourseData? live;
  for (final LibraryCourseData course in readCourses()) {
    if (course.id == courseId) {
      live = course;
      break;
    }
  }
  if (live == null || _isUsableCover(live.coverImage)) {
    return;
  }
  for (final LibraryEpisodeItem episode in live.episodes) {
    if (!_isUsableCover(episode.coverImage)) {
      continue;
    }
    await catalog.updateCourseCover(
      courseId: courseId,
      coverImage: episode.coverImage,
    );
    break;
  }
}
