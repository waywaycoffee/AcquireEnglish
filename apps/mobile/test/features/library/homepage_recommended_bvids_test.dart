import 'package:common_learn_english/features/library/domain/homepage_recommended_bvids.dart';
import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

AcquireDailyFeedItemDto _feed(String bvid) => AcquireDailyFeedItemDto(
      id: 'bili-$bvid',
      title: bvid,
      bvid: bvid,
      watchUrl: 'https://www.bilibili.com/video/$bvid',
    );

void main() {
  test('builds uppercase homepage bvid set from daily feed', () {
    final Set<String> set = homepageRecommendedBvidsFromFeed(<AcquireDailyFeedItemDto>[
      _feed('bv1xx411c7m7'),
      _feed('BV1YY411c7M8'),
      _feed(''),
    ]);
    expect(set, <String>{'BV1XX411C7M7', 'BV1YY411C7M8'});
  });

  test('english-browse feed drops homepage duplicates', () {
    final Set<String> home = homepageRecommendedBvidsFromFeed(<AcquireDailyFeedItemDto>[
      _feed('BV1AA411c7aa'),
    ]);
    final List<AcquireDailyFeedItemDto> filtered =
        excludeHomepageRecommendedFeedItems(
      <AcquireDailyFeedItemDto>[
        _feed('BV1AA411c7aa'),
        _feed('BV1BB411c7bb'),
      ],
      home,
    );
    expect(filtered.map((AcquireDailyFeedItemDto e) => e.bvid).toList(),
        <String>['BV1BB411c7bb']);
  });

  test('recommended creator sample videos drop homepage duplicates', () {
    final Set<String> home = <String>{'BV1HOME00001'};
    final List<RecommendedBilibiliCreatorDto> filtered =
        excludeHomepageRecommendedCreatorVideos(
      <RecommendedBilibiliCreatorDto>[
        const RecommendedBilibiliCreatorDto(
          id: 'a',
          creatorId: '1',
          displayName: 'Keep',
          videos: <RecommendedBilibiliVideoDto>[
            RecommendedBilibiliVideoDto(
              bvid: 'BV1HOME00001',
              title: 'home',
              watchUrl: 'https://www.bilibili.com/video/BV1HOME00001',
            ),
            RecommendedBilibiliVideoDto(
              bvid: 'BV1OTHER0002',
              title: 'other',
              watchUrl: 'https://www.bilibili.com/video/BV1OTHER0002',
            ),
          ],
        ),
        const RecommendedBilibiliCreatorDto(
          id: 'b',
          creatorId: '2',
          displayName: 'Drop empty',
          videos: <RecommendedBilibiliVideoDto>[
            RecommendedBilibiliVideoDto(
              bvid: 'BV1HOME00001',
              title: 'home only',
              watchUrl: 'https://www.bilibili.com/video/BV1HOME00001',
            ),
          ],
        ),
      ],
      home,
    );
    expect(filtered, hasLength(1));
    expect(filtered.single.displayName, 'Keep');
    expect(
      filtered.single.videos.map((RecommendedBilibiliVideoDto v) => v.bvid),
      <String>['BV1OTHER0002'],
    );
  });
}
