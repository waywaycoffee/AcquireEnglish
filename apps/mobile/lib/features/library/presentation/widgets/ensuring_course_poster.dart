import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../import_course/data/bilibili_cover_refresh.dart';
import '../../../import_course/data/bilibili_import_service.dart';
import '../../../import_course/domain/bilibili_import.dart';
import '../../../settings/presentation/settings_provider.dart';
import '../library_catalog_provider.dart';
import '../library_mock_data.dart';
import 'library_course_poster.dart';

/// Course poster that backfills missing Bilibili covers (same path as 继续学习).
class EnsuringCoursePoster extends ConsumerStatefulWidget {
  const EnsuringCoursePoster({
    required this.course,
    required this.borderRadius,
    this.episode,
    this.fit = BoxFit.cover,
    super.key,
  });

  final LibraryCourseData course;
  final LibraryEpisodeItem? episode;
  final BorderRadius borderRadius;
  final BoxFit fit;

  @override
  ConsumerState<EnsuringCoursePoster> createState() =>
      _EnsuringCoursePosterState();
}

class _EnsuringCoursePosterState extends ConsumerState<EnsuringCoursePoster> {
  String? _fetchedCover;
  String? _fetchKey;

  LibraryEpisodeItem? get _episode {
    if (widget.episode != null) return widget.episode;
    for (final LibraryEpisodeItem ep in widget.course.episodes) {
      if (!ep.completed && ep.progressPercent > 0) return ep;
    }
    return widget.course.episodes.isEmpty ? null : widget.course.episodes.first;
  }

  String get _catalogCover => displayCoverForCourse(
        course: widget.course,
        episode: _episode,
      );

  @override
  void initState() {
    super.initState();
    unawaited(_ensureCover());
  }

  @override
  void didUpdateWidget(covariant EnsuringCoursePoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course.id != widget.course.id ||
        oldWidget.episode?.id != widget.episode?.id ||
        oldWidget.course.coverImage != widget.course.coverImage ||
        oldWidget.episode?.coverImage != widget.episode?.coverImage) {
      unawaited(_ensureCover());
    }
  }

  Future<void> _ensureCover() async {
    final String existing = _catalogCover;
    if (isDisplayableCover(existing)) {
      if (mounted) {
        setState(() => _fetchedCover = existing);
      }
      if (!existing.startsWith('http')) {
        return;
      }
    }

    final LibraryCourseData course = widget.course;
    if (!_isBilibiliCourse(course)) {
      return;
    }
    final LibraryEpisodeItem? episode = _episode;
    final String? source = _bilibiliSource(course, episode);
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
    // Prefer live catalog cover once backfill lands.
    final LibraryCourseData live = ref
            .watch(libraryCatalogProvider)
            .where((LibraryCourseData c) => c.id == widget.course.id)
            .firstOrNull ??
        widget.course;
    final String catalog = displayCoverForCourse(
      course: live,
      episode: _episode == null
          ? null
          : live.episodes
                .where((LibraryEpisodeItem e) => e.id == _episode!.id)
                .firstOrNull,
    );
    final String path = isDisplayableCover(catalog)
        ? catalog
        : (_fetchedCover != null && isDisplayableCover(_fetchedCover!)
            ? _fetchedCover!
            : catalog);
    return LibraryCoursePoster(
      title: live.title,
      path: path,
      borderRadius: widget.borderRadius,
      fit: widget.fit,
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
  LibraryEpisodeItem? episode,
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

  if (episode != null) {
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
  }

  for (final LibraryEpisodeItem other in course.episodes) {
    final String? hit = pick(other.sourceUrl) ?? pick(other.videoAsset);
    if (hit != null) {
      return hit;
    }
  }

  final String? fromDescription = pick(course.description);
  if (fromDescription != null) {
    return fromDescription;
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
