import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/domain/homepage_recommended_bvids.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';

/// Shared daily 「全英可逛」 shelf keyed by CEFR level.
///
/// Server builds the list once per calendar day; this provider keeps it warm
/// across Library tab remounts so opening the shelf does not re-hit Bilibili.
/// Homepage「推荐视频」BVids are filtered out so the video tab does not repeat them.
final englishBrowseDailyProvider =
    FutureProvider.family<List<AcquireDailyFeedItemDto>, String>((
  Ref ref,
  String level,
) async {
  ref.keepAlive();
  final Set<String> homepageBvids = ref.watch(homepageRecommendedBvidsProvider);
  final String safe =
      level.trim().isEmpty ? 'A2' : level.trim().toUpperCase();
  final List<AcquireDailyFeedItemDto> items =
      await ref.read(acquireApiClientProvider).englishBrowseFeed(level: safe);
  return excludeHomepageRecommendedFeedItems(items, homepageBvids);
});
