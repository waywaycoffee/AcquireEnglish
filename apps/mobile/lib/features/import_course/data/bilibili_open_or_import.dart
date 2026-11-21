import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../membership/domain/free_trial_seeds.dart';
import '../../membership/domain/module_access.dart';
import '../../../router/app_router.dart';
import '../domain/bilibili_import.dart';
import '../presentation/bilibili_import_sheet.dart';

/// Match an already-imported library episode for a Bilibili watch URL / BV.
({LibraryCourseData course, LibraryEpisodeItem episode})?
findLibraryEpisodeForBilibiliInput(
  List<LibraryCourseData> courses,
  String rawInput,
) {
  final String cleaned = BilibiliImport.normalizeInput(rawInput);
  final Map<String, String>? ids = BilibiliImport.extractIds(cleaned);
  if (ids == null) {
    return null;
  }
  final String bvid = (ids['bvid'] ?? '').trim().toUpperCase();
  final String aid = (ids['aid'] ?? '').trim();
  final int? page = _pageFromInput(cleaned);

  for (final LibraryCourseData course in courses) {
    final bool isBili =
        course.category == 'bilibili' ||
        course.sourceLabel.toLowerCase().contains('bilibili') ||
        course.id.startsWith('bilibili-');
    if (!isBili) {
      continue;
    }
    for (final LibraryEpisodeItem episode in course.episodes) {
      if (_episodeMatches(
        episode: episode,
        course: course,
        bvid: bvid,
        aid: aid,
        page: page,
      )) {
        return (course: course, episode: episode);
      }
    }
  }
  return null;
}

bool _episodeMatches({
  required LibraryEpisodeItem episode,
  required LibraryCourseData course,
  required String bvid,
  required String aid,
  required int? page,
}) {
  final List<String> candidates = <String>[
    episode.sourceUrl ?? '',
    episode.videoAsset ?? '',
    course.description,
  ];
  for (final String raw in candidates) {
    final Map<String, String>? ids = BilibiliImport.extractIds(raw);
    if (ids == null) {
      continue;
    }
    final String candBv = (ids['bvid'] ?? '').trim().toUpperCase();
    final String candAid = (ids['aid'] ?? '').trim();
    final bool idHit =
        (bvid.isNotEmpty && candBv == bvid) ||
        (aid.isNotEmpty && candAid == aid);
    if (!idHit) {
      continue;
    }
    if (page == null) {
      return true;
    }
    final int? candPage = _pageFromInput(raw);
    // Season members are distinct BVs — page filter only for multi-P same BV.
    if (course.id.startsWith('bilibili-season-')) {
      return true;
    }
    if (candPage == null) {
      // Episode numberStr often equals multi-P index.
      final int? fromNumber = int.tryParse(episode.numberStr);
      return fromNumber == null || fromNumber == page;
    }
    return candPage == page;
  }
  return false;
}

int? _pageFromInput(String raw) {
  final RegExpMatch? match = RegExp(
    r'[?&#]p=(\d+)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1) ?? '');
}

/// Open an already-imported episode, or fall back to the import sheet.
///
/// Returns the episode id when learning was opened / imported successfully.
Future<String?> openBilibiliLearningOrImport(
  BuildContext context,
  WidgetRef ref, {
  required String watchUrl,
  bool startImportImmediately = false,
  bool pushPlayer = true,
}) async {
  final String url = watchUrl.trim();
  if (url.isEmpty) {
    return null;
  }
  final Map<String, String>? ids = BilibiliImport.extractIds(url);
  final String bvid = (ids?['bvid'] ?? '').trim();
  final bool seedFree =
      bvid.isNotEmpty && isFreeTrialBilibiliBvid(bvid);
  if (!seedFree) {
    final bool unlocked = await resolveModuleUnlocked(ref, 'video');
    if (!unlocked) {
      if (context.mounted) {
        await showModulePaywall(context, moduleCode: 'video');
      }
      return null;
    }
  }
  final hit = findLibraryEpisodeForBilibiliInput(
    ref.read(libraryCatalogProvider),
    url,
  );
  if (hit != null) {
    if (!context.mounted) {
      return hit.episode.id;
    }
    if (pushPlayer) {
      context.pushNamed(
        SGRoute.player.name,
        pathParameters: <String, String>{'episodeId': hit.episode.id},
      );
    }
    return hit.episode.id;
  }
  if (!context.mounted) {
    return null;
  }
  return showBilibiliImportSheet(
    context,
    ref,
    initialUrl: url,
    startImmediately: startImportImmediately,
  );
}
