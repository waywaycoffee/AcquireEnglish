import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';

final FutureProvider<List<RecommendedBilibiliCreatorDto>>
    recommendedBilibiliCreatorsProvider =
    FutureProvider<List<RecommendedBilibiliCreatorDto>>((Ref ref) async {
  // Keep the rail warm across tab switches; invalidate only on pull-to-refresh.
  ref.keepAlive();
  try {
    return await ref.read(acquireApiClientProvider).listRecommendedCreators();
  } catch (_) {
    return const <RecommendedBilibiliCreatorDto>[];
  }
});

/// In-app followed creators (not Bilibili site follows). Used by the
/// recommended-UP cards so the 关注 / 已关注 button stays in sync.
final FutureProvider<List<FollowedCreatorDto>> followedCreatorsListProvider =
    FutureProvider<List<FollowedCreatorDto>>((Ref ref) async {
  final bool loggedIn = ref.watch(
    authSessionProvider.select((AuthSessionState auth) => auth.isLoggedIn),
  );
  if (!loggedIn) {
    return const <FollowedCreatorDto>[];
  }
  try {
    return await ref.read(acquireApiClientProvider).listFollowedCreators();
  } catch (_) {
    return ref.read(learningPreferencesProvider).followedCreators;
  }
});
