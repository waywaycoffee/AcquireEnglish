import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/bilibili_import.dart';
import 'bilibili_import_service.dart';
import 'bilibili_multipage.dart';

/// App icon / bundled assets are not real course posters.
bool isPlaceholderCover(String cover) {
  final String value = cover.trim();
  if (value.isEmpty) {
    return true;
  }
  if (value.startsWith('assets/')) {
    return true;
  }
  if (value == 'assets/img/app_icon.png' || value.endsWith('/app_icon.png')) {
    return true;
  }
  // Keep working https covers — do not treat them as missing.
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return false;
  }
  return !File(value).existsSync();
}

bool isDisplayableCover(String cover) {
  final String value = cover.trim();
  if (value.isEmpty || value.startsWith('assets/')) {
    return false;
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return true;
  }
  return File(value).existsSync();
}

/// Prefer given episode, then any episode with a real poster, then course.
String displayCoverForCourse({
  required LibraryCourseData course,
  LibraryEpisodeItem? episode,
}) {
  final String episodeCover = episode?.coverImage.trim() ?? '';
  if (isDisplayableCover(episodeCover)) {
    return episodeCover;
  }
  for (final LibraryEpisodeItem ep in course.episodes) {
    final String cover = ep.coverImage.trim();
    if (isDisplayableCover(cover)) {
      return cover;
    }
  }
  final String courseCover = course.coverImage.trim();
  if (isDisplayableCover(courseCover)) {
    return courseCover;
  }
  return '';
}

bool _isPlaceholderCover(String cover) => isPlaceholderCover(cover);

bool _isDisplayableCover(String cover) => isDisplayableCover(cover);

bool _isLocalVideoPath(String? path) {
  final String value = path?.trim() ?? '';
  if (value.isEmpty) {
    return false;
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return false;
  }
  final File file = File(value);
  return file.existsSync() && file.lengthSync() > 64 * 1024;
}

bool _isBilibiliCourse(LibraryCourseData course) {
  return course.category == 'bilibili' ||
      course.sourceLabel.toLowerCase().contains('bilibili') ||
      course.id.startsWith('bilibili-');
}

String? _sourceForCourse(LibraryCourseData course) {
  // Prefer watch URL / BV text — local mp4 paths cannot resolve B 站 covers.
  final String description = course.description.trim();
  if (description.contains('bilibili.com') ||
      description.contains('b23.tv') ||
      description.contains('bili2233.cn') ||
      description.contains('BV') ||
      description.contains('bilibili-season-')) {
    return description;
  }
  if (course.id.startsWith('bilibili-season-')) {
    return course.id;
  }
  if (course.id.startsWith('bilibili-')) {
    final String idKey = course.id.substring('bilibili-'.length);
    if (idKey.startsWith('BV') || idKey.startsWith('av')) {
      return idKey;
    }
  }
  for (final LibraryEpisodeItem episode in course.episodes) {
    final String? sourceUrl = episode.sourceUrl?.trim();
    if (sourceUrl != null &&
        sourceUrl.isNotEmpty &&
        (BilibiliImport.isWatchPageUrl(sourceUrl) ||
            BilibiliImport.looksLikeBilibiliInput(sourceUrl))) {
      return sourceUrl;
    }
    final String? video = episode.videoAsset?.trim();
    if (video == null || video.isEmpty) {
      continue;
    }
    if (BilibiliImport.isWatchPageUrl(video) ||
        BilibiliImport.looksLikeBilibiliInput(video)) {
      return video;
    }
  }
  return null;
}

bool _courseNeedsLocalVideo(LibraryCourseData course) {
  if (!_isBilibiliCourse(course)) {
    return false;
  }
  if (course.episodes.isEmpty) {
    return false;
  }
  return course.episodes.any(
    (LibraryEpisodeItem e) => !_isLocalVideoPath(e.videoAsset),
  );
}

/// Backfill Bilibili posters + local MP4 for courses that still need them.
Future<void> refreshMissingBilibiliCovers(Ref ref) async {
  List<LibraryCourseData> courses = ref.read(libraryCatalogProvider);
  final String cookie = ref
      .read(learningSettingsProvider)
      .resolvedBilibiliCookieHeader;
  final BilibiliImportService service = BilibiliImportService.withCookie(
    cookie,
  );
  // One-shot: rewrite force-uppercased BV urls via UGC season archives.
  try {
    final List<LibraryCourseData> repaired =
        await repairUppercasedBilibiliCourses(
          service: service,
          courses: courses,
        );
    int fixed = 0;
    for (final LibraryCourseData course in repaired) {
      LibraryCourseData? previous;
      for (final LibraryCourseData c in courses) {
        if (c.id == course.id) {
          previous = c;
          break;
        }
      }
      if (previous == null) {
        continue;
      }
      final bool descriptionChanged =
          previous.description.trim() != course.description.trim();
      bool episodeChanged = false;
      for (final LibraryEpisodeItem ep in course.episodes) {
        LibraryEpisodeItem? old;
        for (final LibraryEpisodeItem e in previous.episodes) {
          if (e.id == ep.id) {
            old = e;
            break;
          }
        }
        if (old == null) {
          continue;
        }
        if ((old.sourceUrl ?? '') != (ep.sourceUrl ?? '') ||
            (old.videoAsset ?? '') != (ep.videoAsset ?? '')) {
          episodeChanged = true;
          break;
        }
      }
      if (!descriptionChanged && !episodeChanged) {
        continue;
      }
      await ref.read(libraryCatalogProvider.notifier).importCourse(course);
      fixed += 1;
    }
    if (fixed > 0) {
      courses = ref.read(libraryCatalogProvider);
      // ignore: avoid_print
      print('bilibili.backfill repaired $fixed uppercased BV course(s)');
    }
  } catch (e, st) {
    developer.log(
      'catalog BV case repair failed: $e',
      name: 'bilibili.backfill',
      error: e,
      stackTrace: st,
    );
  }
  for (final LibraryCourseData course in courses) {
    if (!_isBilibiliCourse(course)) {
      continue;
    }
    final String? rawSource = _sourceForCourse(course);
    if (rawSource == null || rawSource.isEmpty) {
      developer.log(
        'skip bilibili course ${course.id}: no source',
        name: 'bilibili.backfill',
      );
      continue;
    }
    String source = rawSource;
    try {
      source = await repairBilibiliSourceCase(
        service: service,
        source: source,
        course: course,
        episode: course.episodes.isNotEmpty ? course.episodes.first : null,
      );
    } catch (_) {}

    final bool courseNeedsCover = _isPlaceholderCover(course.coverImage);
    if (courseNeedsCover) {
      try {
        final String? cover = await service.resolveCoverImage(source);
        if (cover != null &&
            cover.isNotEmpty &&
            _isDisplayableCover(cover)) {
          await ref
              .read(libraryCatalogProvider.notifier)
              .updateCourseCover(courseId: course.id, coverImage: cover);
          developer.log(
            'cover updated ${course.id} -> $cover',
            name: 'bilibili.backfill',
          );
        } else {
          developer.log(
            'cover resolve empty for ${course.id}',
            name: 'bilibili.backfill',
          );
        }
      } catch (e, st) {
        developer.log(
          'cover failed ${course.id}: $e',
          name: 'bilibili.backfill',
          error: e,
          stackTrace: st,
        );
      }
    }

    // Per-episode covers for 合集/分P — avoid stamping one season poster onto
    // every member when each episode already has (or can resolve) its own.
    if (course.episodes.length > 1) {
      for (final LibraryEpisodeItem episode in course.episodes) {
        if (!_isPlaceholderCover(episode.coverImage)) {
          continue;
        }
        final String? episodeSource = bilibiliSourceForEpisode(
          course: course,
          episode: episode,
          videoAsset: episode.videoAsset,
        );
        if (episodeSource == null || episodeSource.isEmpty) {
          continue;
        }
        try {
          final String? cover = await service.resolveCoverImage(episodeSource);
          if (cover == null ||
              cover.isEmpty ||
              !_isDisplayableCover(cover)) {
            continue;
          }
          await ref
              .read(libraryCatalogProvider.notifier)
              .updateEpisodeLocalMedia(
                courseId: course.id,
                episodeId: episode.id,
                coverImage: cover,
              );
          developer.log(
            'episode cover updated ${episode.id} -> $cover',
            name: 'bilibili.backfill',
          );
        } catch (e, st) {
          developer.log(
            'episode cover failed ${episode.id}: $e',
            name: 'bilibili.backfill',
            error: e,
            stackTrace: st,
          );
        }
      }
    } else if (course.episodes.isNotEmpty &&
        _isPlaceholderCover(course.episodes.first.coverImage) &&
        !_isPlaceholderCover(course.coverImage)) {
      // Single episode: mirror course cover onto the episode if needed.
      await ref.read(libraryCatalogProvider.notifier).updateEpisodeLocalMedia(
            courseId: course.id,
            episodeId: course.episodes.first.id,
            coverImage: course.coverImage,
          );
    }

    // Single-episode courses only — never stamp one MP4 onto a whole 合集.
    if (_courseNeedsLocalVideo(course) && course.episodes.length <= 1) {
      try {
        developer.log(
          'downloading local video for ${course.id}',
          name: 'bilibili.backfill',
        );
        final String localPath = await service.ensureLocalCacheForAsr(source);
        if (_isLocalVideoPath(localPath)) {
          await ref
              .read(libraryCatalogProvider.notifier)
              .updateCourseVideoAsset(
                courseId: course.id,
                videoAsset: localPath,
              );
          developer.log(
            'video updated ${course.id} -> $localPath',
            name: 'bilibili.backfill',
          );
        }
      } catch (e, st) {
        developer.log(
          'video download failed ${course.id}: $e',
          name: 'bilibili.backfill',
          error: e,
          stackTrace: st,
        );
        // ignore: avoid_print
        print('bilibili.backfill video download failed ${course.id}: $e');
      }
    }
  }
}

/// Keep-alive so long video downloads are not cancelled when leaving Home.
final FutureProvider<void> bilibiliCoverRefreshProvider =
    FutureProvider<void>((Ref ref) async {
      await refreshMissingBilibiliCovers(ref);
    });
