import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/data/acquire_api_client.dart';

/// Shared daily YouTube education shelf keyed by CEFR level.
final youtubeBrowseDailyProvider =
    FutureProvider.family<List<AcquireDailyFeedItemDto>, String>((
  Ref ref,
  String level,
) async {
  ref.keepAlive();
  final String safe =
      level.trim().isEmpty ? 'A2' : level.trim().toUpperCase();
  return ref.read(acquireApiClientProvider).youtubeBrowseFeed(level: safe);
});
