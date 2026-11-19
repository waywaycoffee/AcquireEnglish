import 'dart:convert';
import 'dart:io';

import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:common_learn_english/features/sync/presentation/daily_feed_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  test('daily feed excludes unverified cached and refreshed videos', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'daily-feed-test-',
    );
    Hive.init(directory.path);
    final Box<String> box = await Hive.openBox<String>('prefs');
    addTearDown(() async {
      await box.close();
      await directory.delete(recursive: true);
    });

    final List<Map<String, dynamic>> candidates = <Map<String, dynamic>>[
      _candidate('verified', <String>['slow', '抽样英语原声']),
      _candidate('pending', <String>['slow', '原声待确认']),
      _candidate('legacy', <String>['slow']),
      _candidate('conflicting', <String>['抽样英语原声', '原声待确认']),
    ];
    await box.put('daily_feed_bili_v2:', jsonEncode(candidates));

    final Dio dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions request, RequestInterceptorHandler handler) {
          handler.resolve(
            Response<Object>(
              requestOptions: request,
              data: <Map<String, dynamic>>[
                _candidate('fresh', <String>['抽样英语原声']),
                ...candidates.skip(1),
              ],
            ),
          );
        },
      ),
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        acquireApiClientProvider.overrideWithValue(AcquireApiClient(dio)),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(dailyFeedProvider).map((item) => item.id), <String>[
      'verified',
    ]);
    await container.read(dailyFeedProvider.notifier).refresh(force: true);
    expect(container.read(dailyFeedProvider).map((item) => item.id), <String>[
      'fresh',
    ]);
    expect(box.get('daily_feed_synced_at_v2:'), isNull);
  });
}

Map<String, dynamic> _candidate(String id, List<String> tags) =>
    <String, dynamic>{
      'id': id,
      'bvid': id,
      'watchUrl': 'https://www.bilibili.com/video/$id',
      'tags': tags,
    };
