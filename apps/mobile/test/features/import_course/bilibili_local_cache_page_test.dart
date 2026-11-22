import 'dart:io';

import 'package:common_learn_english/features/import_course/data/bilibili_import_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each watch page selects only its own local video', () async {
    final Directory root = Directory.systemTemp.createTempSync('bili-page-');
    final PathProviderPlatform previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(root);
    try {
      final Directory cache = Directory('${root.path}/bilibili_media')
        ..createSync();
      final File first = File('${cache.path}/BV1CS4y1v7sQ-p01.mp4')
        ..writeAsBytesSync(List<int>.filled(65 * 1024, 1));
      final File second = File('${cache.path}/BV1CS4y1v7sQ-p02.mp4')
        ..writeAsBytesSync(List<int>.filled(65 * 1024, 2));
      final Dio dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (RequestOptions options, RequestInterceptorHandler handler) {
                handler.resolve(
                  Response<Map<String, Object>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, Object>{'code': -404, 'message': '啥都木有'},
                  ),
                );
              },
        ),
      );
      final BilibiliImportService service = BilibiliImportService(dio: dio);

      expect(
        await service.findExistingLocalCache(
          'https://www.bilibili.com/video/BV1CS4y1v7sQ?p=1',
        ),
        first.path,
      );
      expect(
        await service.findExistingLocalCache(
          'https://www.bilibili.com/video/BV1CS4y1v7sQ?p=2',
        ),
        second.path,
      );
      expect(
        await service.findExistingLocalCache(
          'https://www.bilibili.com/video/BV1CS4y1v7sQ?p=3',
        ),
        isNull,
      );
    } finally {
      PathProviderPlatform.instance = previous;
      root.deleteSync(recursive: true);
    }
  });
}
