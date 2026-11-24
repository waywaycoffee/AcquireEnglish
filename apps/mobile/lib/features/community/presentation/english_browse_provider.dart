import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/data/acquire_api_client.dart';

/// Shared daily 「全英可逛」 shelf keyed by CEFR level.
///
/// Server builds the list once per calendar day; this provider keeps it warm
/// across Library tab remounts so opening the shelf does not re-hit Bilibili.
final englishBrowseDailyProvider =
    FutureProvider.family<List<AcquireDailyFeedItemDto>, String>((
  Ref ref,
  String level,
) async {
  ref.keepAlive();
  final String safe =
      level.trim().isEmpty ? 'A2' : level.trim().toUpperCase();
  return ref.read(acquireApiClientProvider).englishBrowseFeed(level: safe);
});
