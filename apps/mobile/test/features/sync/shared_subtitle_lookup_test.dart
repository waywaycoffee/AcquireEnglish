import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shared lookup retries legacy case on the same page without enqueueing',
    () async {
      final Dio dio = Dio();
      addTearDown(dio.close);
      final List<RequestOptions> requests = [];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request);
            final bool hit = request.queryParameters['bvid'] == 'BV1CS4Y1V7SQ';
            handler.resolve(
              Response<dynamic>(
                requestOptions: request,
                statusCode: hit ? 200 : 404,
                data: hit
                    ? <String, dynamic>{
                        'bvid': 'BV1CS4Y1V7SQ',
                        'page': 14,
                        'subtitle_en_srt': 'English',
                        'subtitle_zh_srt': '中文字幕',
                      }
                    : null,
              ),
            );
          },
        ),
      );

      final pack = await AcquireApiClient(
        dio,
      ).getSharedBilibiliSubtitle(bvid: 'BV1CS4y1v7sQ', page: 14);

      expect(pack?.page, 14);
      expect(pack?.subtitleZhSrt, '中文字幕');
      expect(requests.map((r) => r.queryParameters['bvid']), [
        'BV1CS4y1v7sQ',
        'BV1CS4Y1V7SQ',
      ]);
      expect(
        requests.every(
          (r) => r.method == 'GET' && r.queryParameters['page'] == 14,
        ),
        isTrue,
      );
    },
  );
}
