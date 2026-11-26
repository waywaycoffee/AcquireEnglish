import '../../sync/data/acquire_api_client.dart';

/// Normalize B站 BV ids for cross-surface dedupe (home vs video library).
String normalizeRecommendedBvid(String? raw) =>
    (raw ?? '').trim().toUpperCase();

/// BVids already offered on the homepage「推荐视频」rail.
Set<String> homepageRecommendedBvidsFromFeed(
  Iterable<AcquireDailyFeedItemDto> feed,
) {
  final Set<String> out = <String>{};
  for (final AcquireDailyFeedItemDto item in feed) {
    final String bvid = normalizeRecommendedBvid(item.bvid);
    if (bvid.isNotEmpty) {
      out.add(bvid);
    }
  }
  return out;
}

bool isHomepageRecommendedBvid(String? bvid, Set<String> homepageBvids) {
  if (homepageBvids.isEmpty) {
    return false;
  }
  final String key = normalizeRecommendedBvid(bvid);
  return key.isNotEmpty && homepageBvids.contains(key);
}

List<AcquireDailyFeedItemDto> excludeHomepageRecommendedFeedItems(
  Iterable<AcquireDailyFeedItemDto> items,
  Set<String> homepageBvids,
) {
  if (homepageBvids.isEmpty) {
    return List<AcquireDailyFeedItemDto>.unmodifiable(items);
  }
  return items
      .where(
        (AcquireDailyFeedItemDto item) =>
            !isHomepageRecommendedBvid(item.bvid, homepageBvids),
      )
      .toList(growable: false);
}

List<RecommendedBilibiliCreatorDto> excludeHomepageRecommendedCreatorVideos(
  Iterable<RecommendedBilibiliCreatorDto> creators,
  Set<String> homepageBvids,
) {
  if (homepageBvids.isEmpty) {
    return List<RecommendedBilibiliCreatorDto>.unmodifiable(creators);
  }
  final List<RecommendedBilibiliCreatorDto> out =
      <RecommendedBilibiliCreatorDto>[];
  for (final RecommendedBilibiliCreatorDto creator in creators) {
    final List<RecommendedBilibiliVideoDto> videos = creator.videos
        .where(
          (RecommendedBilibiliVideoDto video) =>
              !isHomepageRecommendedBvid(video.bvid, homepageBvids),
        )
        .toList(growable: false);
    if (videos.isEmpty) {
      continue;
    }
    if (videos.length == creator.videos.length) {
      out.add(creator);
      continue;
    }
    out.add(
      RecommendedBilibiliCreatorDto(
        id: creator.id,
        creatorId: creator.creatorId,
        displayName: creator.displayName,
        source: creator.source,
        avatarUrl: creator.avatarUrl,
        profileUrl: creator.profileUrl,
        blurb: creator.blurb,
        videos: videos,
      ),
    );
  }
  return out;
}
