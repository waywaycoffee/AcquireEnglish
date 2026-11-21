import 'dart:convert';
import 'dart:typed_data';

import 'package:common_learn_english/features/words/data/lilinji_catalog.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._handlers);

  final List<ResponseBody Function(RequestOptions)> _handlers;
  int calls = 0;
  final List<String> urls = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    urls.add(options.uri.toString());
    final ResponseBody Function(RequestOptions) handler =
        _handlers[calls.clamp(0, _handlers.length - 1)];
    calls += 1;
    return handler(options);
  }
}

void main() {
  test('listPath parses GitHub contents payload', () async {
    final Dio dio = Dio();
    dio.httpClientAdapter = _ScriptedAdapter(<ResponseBody Function(RequestOptions)>[
      (_) => ResponseBody.fromString(
        jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'name': 'folder',
            'path': '2.中考/folder',
            'type': 'dir',
          },
          <String, Object?>{
            'name': '词表.xlsx',
            'path': '2.中考/词表.xlsx',
            'type': 'file',
            'size': 12,
            'download_url':
                'https://raw.githubusercontent.com/lilinji/English/main/2.中考/词表.xlsx',
          },
          <String, Object?>{
            'name': 'readme.md',
            'path': '2.中考/readme.md',
            'type': 'file',
            'size': 3,
            'download_url':
                'https://raw.githubusercontent.com/lilinji/English/main/2.中考/readme.md',
          },
        ]),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      ),
    ]);

    final LilinjiCatalogClient client = LilinjiCatalogClient(dio: dio);
    final List<LilinjiCatalogEntry> entries = await client.listPath('2.中考');
    expect(entries.length, 2);
    expect(entries.first.kind, LilinjiEntryKind.folder);
    expect(entries.last.kind, LilinjiEntryKind.book);
    expect(entries.last.displayTitle, '词表');
  });

  test('downloadBook parses text vocab and skips disclaimer text', () async {
    final Dio dio = Dio();
    dio.httpClientAdapter = _ScriptedAdapter(<ResponseBody Function(RequestOptions)>[
      (_) => ResponseBody.fromBytes(
        utf8.encode('word\tgloss\napple\t苹果\nbook\t书\n'),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/octet-stream'],
        },
      ),
    ]);

    final LilinjiCatalogClient client = LilinjiCatalogClient(dio: dio);
    final result = await client.downloadBook(
      entry: const LilinjiCatalogEntry(
        name: 'demo.txt',
        path: '2.中考/demo.txt',
        kind: LilinjiEntryKind.book,
        downloadUrl:
            'https://raw.githubusercontent.com/lilinji/English/main/2.中考/demo.txt',
      ),
      examTag: 'ZK',
    );
    expect(result.words.length, 2);
    expect(result.book.disclaimer, isEmpty);
    expect(result.book.examTag, 'ZK');
    expect(result.book.title, 'demo');
  });
}
