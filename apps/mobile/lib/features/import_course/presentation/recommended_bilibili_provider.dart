import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/data/acquire_api_client.dart';

final FutureProvider<List<RecommendedBilibiliCreatorDto>>
    recommendedBilibiliCreatorsProvider =
    FutureProvider<List<RecommendedBilibiliCreatorDto>>((Ref ref) async {
  try {
    return await ref.read(acquireApiClientProvider).listRecommendedCreators();
  } catch (_) {
    return const <RecommendedBilibiliCreatorDto>[];
  }
});
