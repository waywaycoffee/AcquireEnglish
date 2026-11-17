import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../library/data/course_pack_mapper.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../data/acquire_api_client.dart';
import '../data/personal_import_sync.dart';
import 'daily_feed_provider.dart';

/// [ref] may be a [Ref] or [WidgetRef] (both expose `.read`).
Future<void> syncCloudCatalogAndFeed(dynamic ref) async {
  try {
    final AcquireApiClient api =
        ref.read(acquireApiClientProvider) as AcquireApiClient;
    final List<AcquireCourseDto> courses = await api.courses();
    // Never merge unplayable placeholder packs (cdn.example.com demo catalog).
    final List<LibraryCourseData> mapped = courses
        .where((AcquireCourseDto c) => !isPlaceholderCloudCourse(c))
        // Personal link-* assets are restored separately (video re-download +
        // DB softsubs). Merging raw watch URLs as playable files is wrong.
        .where((AcquireCourseDto c) => !c.id.startsWith('link-'))
        .map(mapAcquireCourseToLibrary)
        .toList(growable: false);
    await (ref.read(libraryCatalogProvider.notifier) as LibraryCatalogNotifier)
        .mergeCloudCourses(mapped);
  } catch (_) {}
  try {
    // Cross-device / re-login: B站原链接重下视频，字幕从个人资产库拉取。
    await restorePersonalImportAssets(ref);
  } catch (_) {}
  try {
    await (ref.read(learningPreferencesProvider.notifier)
            as dynamic)
        .pullRemote();
  } catch (_) {}
  try {
    await (ref.read(dailyFeedProvider.notifier) as dynamic).refresh();
  } catch (_) {}
}

/// Cold start + every login (token change) → restore personal video/subtitle assets.
final FutureProvider<void> cloudCatalogSyncProvider =
    FutureProvider<void>((Ref ref) async {
      // Rebuild when the user signs in / switches account on a new device.
      final String token = ref.watch(
        authSessionProvider.select((AuthSessionState s) => s.accessToken),
      );
      if (token.isEmpty) {
        return;
      }
      await syncCloudCatalogAndFeed(ref);
    });
