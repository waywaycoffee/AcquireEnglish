import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../constants/endpoints.dart';
import '../../exam/presentation/exam_pack_provider.dart';
import '../../import_course/data/bilibili_course_builder.dart';
import '../../import_course/data/bilibili_import_service.dart';
import '../../import_course/data/bilibili_open_or_import.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../reading/domain/reading_doc.dart';
import '../../reading/presentation/reading_cold_start.dart';
import '../../reading/presentation/reading_library_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../domain/free_trial_seeds.dart';

const String _kBootstrapDoneKey = 'free_trial_seed_bootstrap_v1';

/// Auto-download default free-trial seeds into local cache on app start.
///
/// Media stays on ECS / remote APIs — never bundled under `apps/mobile/assets`.
final freeTrialSeedBootstrapProvider = FutureProvider<void>((Ref ref) async {
  // Reading starters (+ Oz) first — text corpus into reading library.
  await ref.watch(readingColdStartProvider.future);
  if (!ref.mounted) return;

  Map<String, List<FreeTrialSeedItem>> seeds = kDefaultFreeTrialSeeds;
  try {
    final Map<String, dynamic> remote =
        await ref.read(acquireApiClientProvider).commerceFreeTrialSeeds();
    seeds = parseFreeTrialSeedsPayload(remote);
  } catch (_) {
    // Bundled defaults are enough offline.
  }

  await _ensureCourseSeedDocs(ref, seeds['course'] ?? const <FreeTrialSeedItem>[]);
  if (!ref.mounted) return;

  // Exam pack JSON (text) into provider / client cache — audio stays on ECS.
  try {
    await ref.read(acquireApiClientProvider).examPack('cet4');
  } catch (_) {
    try {
      await ref.read(examPackProvider.future);
    } catch (_) {}
  }

  final bool alreadyDone = Hive.isBoxOpen('prefs') &&
      (Hive.box<String>('prefs').get(_kBootstrapDoneKey) == '1');
  if (!alreadyDone) {
    await _downloadVideoSeeds(ref, seeds['video'] ?? const <FreeTrialSeedItem>[]);
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(_kBootstrapDoneKey, '1');
    }
  } else {
    // Still ensure missing seed episodes get another download attempt.
    unawaited(
      _downloadVideoSeeds(ref, seeds['video'] ?? const <FreeTrialSeedItem>[]),
    );
  }
});

Future<void> _ensureCourseSeedDocs(
  Ref ref,
  List<FreeTrialSeedItem> courseSeeds,
) async {
  for (int i = 0; i < 40 && !ref.read(readingLibraryProvider).ready; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!ref.mounted) return;
  }
  if (!ref.mounted || !ref.read(readingLibraryProvider).ready) return;

  final String base =
      ref.read(learningSettingsProvider).resolvedCloudApiBaseUrl;
  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  try {
    Map<String, ReadingDoc> starters = <String, ReadingDoc>{};
    for (final ReadingDoc doc in ref.read(readingLibraryProvider).userDocs) {
      if (doc.id.startsWith('starter-')) {
        starters[doc.id] = doc;
      }
    }
    if (starters.isEmpty) {
      try {
        final response = await dio.get<dynamic>(
          Uri.parse(Endpoints.normalizeBaseUrl(base))
              .resolve('api/reading/starter')
              .toString(),
        );
        final docs = (response.data['documents'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (Map<dynamic, dynamic> d) =>
                  ReadingDoc.fromJson(Map<String, dynamic>.from(d)),
            );
        for (final ReadingDoc doc in docs) {
          starters[doc.id] = doc;
        }
      } catch (_) {}
    }

    final notifier = ref.read(readingLibraryProvider.notifier);
    for (final FreeTrialSeedItem seed in courseSeeds) {
      if (!ref.mounted) return;
      if (ref.read(readingLibraryProvider).docById(seed.id) != null) continue;
      final ReadingDoc? src = starters[seed.sourceStarterId];
      if (src == null || src.plainText.trim().isEmpty) continue;
      final ReadingDoc demo = ReadingDoc(
        id: seed.id,
        title: seed.title,
        plainText: src.plainText,
        level: src.level,
        sourceType: ReadingSourceType.catalog,
        sourceLabel: '免费体验 · 默认课程',
        courseTitle: 'Acquire English 免费体验课',
        segments: src.segments,
      );
      await notifier.addDoc(demo, checkQuota: false);
    }
  } finally {
    dio.close();
  }
}

Future<void> _downloadVideoSeeds(
  Ref ref,
  List<FreeTrialSeedItem> videoSeeds,
) async {
  if (videoSeeds.isEmpty) return;
  final String cookie =
      ref.read(learningSettingsProvider).resolvedBilibiliCookieHeader;
  final BilibiliImportService service =
      BilibiliImportService.withCookie(cookie);
  final catalog = ref.read(libraryCatalogProvider.notifier);

  for (final FreeTrialSeedItem seed in videoSeeds) {
    if (!ref.mounted) return;
    if (seed.kind != 'bilibili' || seed.watchUrl.isEmpty) continue;
    final hit = findLibraryEpisodeForBilibiliInput(
      ref.read(libraryCatalogProvider),
      seed.watchUrl,
    );
    if (hit != null) {
      final String? path = hit.episode.videoAsset;
      if (path != null &&
          path.isNotEmpty &&
          !path.startsWith('http') &&
          hit.episode.videoMissing != true) {
        continue;
      }
    }
    try {
      final meta = await service.fetchAndDownloadLocal(
        seed.watchUrl,
        onProgress: (_, __) {},
      );
      if (meta.localVideoPath == null || meta.localVideoPath!.isEmpty) {
        continue;
      }
      final LibraryCourseData course =
          buildLibraryCourseFromBilibiliImport(meta);
      await catalog.importCourse(course);
    } catch (_) {
      // Cookie / CDN failures: leave seed listed via recommended UI;
      // document ECS shared-subtitle + re-try on next launch.
    }
  }
}
