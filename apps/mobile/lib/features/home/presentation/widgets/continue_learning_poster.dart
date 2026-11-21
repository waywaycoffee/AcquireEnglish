import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../import_course/data/bilibili_cover_refresh.dart';
import '../../../import_course/data/bilibili_import_service.dart';
import '../../../import_course/domain/bilibili_import.dart';
import '../../../library/presentation/library_catalog_provider.dart';
import '../../../library/presentation/library_mock_data.dart';
import '../../../library/presentation/widgets/library_course_poster.dart';
import '../../../player/presentation/learning_resume_provider.dart';
import '../../../settings/presentation/settings_provider.dart';

/// Home "继续学习" poster: prefers episode cover, backfills Bilibili posters.
class ContinueLearningPoster extends ConsumerStatefulWidget {
  const ContinueLearningPoster({
    required this.target,
    required this.borderRadius,
    super.key,
  });

  final ContinueLearningTarget target;
  final BorderRadius borderRadius;

  @override
  ConsumerState<ContinueLearningPoster> createState() =>
      _ContinueLearningPosterState();
}

class _ContinueLearningPosterState
    extends ConsumerState<ContinueLearningPoster> {
  String? _fetchedCover;
  String? _fetchKey;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureCover());
  }

  @override
  void didUpdateWidget(covariant ContinueLearningPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.course.id != widget.target.course.id ||
        oldWidget.target.episode.id != widget.target.episode.id ||
        oldWidget.target.course.coverImage != widget.target.course.coverImage ||
        oldWidget.target.episode.coverImage !=
            widget.target.episode.coverImage) {
      unawaited(_ensureCover());
    }
  }

  String get _catalogCover => displayCoverForCourse(
        course: widget.target.course,
        episode: widget.target.episode,
      );

  Future<void> _ensureCover() async {
    final String existing = _catalogCover;
    if (isDisplayableCover(existing)) {
      if (mounted) {
        setState(() => _fetchedCover = existing);
      }
      // Still pin a local copy for remote https when possible.
      if (!existing.startsWith('http')) {
        return;
      }
    }

    final LibraryCourseData course = widget.target.course;
    if (!_isBilibiliCourse(course)) {
      return;
    }
    final String? source = _bilibiliSource(course, widget.target.episode);
    if (source == null || source.isEmpty) {
      return;
    }
    final String key = '${course.id}|$source';
    if (_fetchKey == key &&
        _fetchedCover != null &&
        isDisplayableCover(_fetchedCover!) &&
        !_fetchedCover!.startsWith('http')) {
      return;
    }
    _fetchKey = key;
    try {
      final String cookie =
          ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader;
      final String? cover = await BilibiliImportService.withCookie(cookie)
          .resolveCoverImage(source);
      if (!mounted || cover == null || cover.isEmpty) {
        return;
      }
      if (!isDisplayableCover(cover)) {
        return;
      }
      setState(() => _fetchedCover = cover);
      try {
        await ref.read(libraryCatalogProvider.notifier).updateCourseCover(
              courseId: course.id,
              coverImage: cover,
            );
      } catch (_) {}
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final String path = (_fetchedCover != null &&
            isDisplayableCover(_fetchedCover!))
        ? _fetchedCover!
        : _catalogCover;
    return LibraryCoursePoster(
      title: widget.target.course.title,
      path: path,
      borderRadius: widget.borderRadius,
    );
  }
}

bool _isBilibiliCourse(LibraryCourseData course) {
  return course.category == 'bilibili' ||
      course.sourceLabel.toLowerCase().contains('bilibili') ||
      course.id.startsWith('bilibili-');
}

String? _bilibiliSource(
  LibraryCourseData course,
  LibraryEpisodeItem episode,
) {
  String? pick(String? raw) {
    final String value = (raw ?? '').trim();
    if (value.isEmpty) {
      return null;
    }
    final RegExpMatch? bv = RegExp(
      r'(BV[0-9A-Za-z]+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (bv != null) {
      return bv.group(1);
    }
    if (BilibiliImport.isWatchPageUrl(value) ||
        BilibiliImport.looksLikeBilibiliInput(value) ||
        value.contains('bilibili.com') ||
        value.contains('b23.tv')) {
      return value;
    }
    return null;
  }

  for (final String? candidate in <String?>[
    episode.sourceUrl,
    episode.videoAsset,
    course.description,
    episode.id,
    course.id,
  ]) {
    final String? hit = pick(candidate);
    if (hit != null) {
      return hit;
    }
  }

  // Any sibling episode may still carry a watch URL / BV.
  for (final LibraryEpisodeItem other in course.episodes) {
    final String? hit = pick(other.sourceUrl) ?? pick(other.videoAsset);
    if (hit != null) {
      return hit;
    }
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
  return null;
}
