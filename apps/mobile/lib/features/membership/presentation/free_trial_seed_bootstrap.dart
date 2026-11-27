import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../exam/presentation/exam_pack_provider.dart';
import '../../import_course/data/bilibili_course_builder.dart';
import '../../import_course/data/bilibili_import_service.dart';
import '../../import_course/data/bilibili_open_or_import.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../reading/presentation/reading_cold_start.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../sync/data/acquire_api_client.dart';
import '../domain/free_trial_seeds.dart';

const String _kBootstrapDoneKey = 'free_trial_seed_bootstrap_v1';

/// Prefetch free-trial video seeds + exam packs. Reading shelf only gets
/// 绿野仙踪 via [readingColdStartProvider] — starter/course-seed demos stay off.
final freeTrialSeedBootstrapProvider = FutureProvider<void>((Ref ref) async {
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
    unawaited(
      _downloadVideoSeeds(ref, seeds['video'] ?? const <FreeTrialSeedItem>[]),
    );
  }
});

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
