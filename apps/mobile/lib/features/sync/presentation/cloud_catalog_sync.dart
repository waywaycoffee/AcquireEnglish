import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/data/course_pack_mapper.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../data/acquire_api_client.dart';
import 'daily_feed_provider.dart';

Future<void> syncCloudCatalogAndFeed(WidgetRef ref) async {
  try {
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    final List<AcquireCourseDto> courses = await api.courses();
    final List<LibraryCourseData> mapped =
        courses.map(mapAcquireCourseToLibrary).toList(growable: false);
    await ref.read(libraryCatalogProvider.notifier).mergeCloudCourses(mapped);
  } catch (_) {}
  await ref.read(learningPreferencesProvider.notifier).pullRemote();
  await ref.read(dailyFeedProvider.notifier).refresh();
}
