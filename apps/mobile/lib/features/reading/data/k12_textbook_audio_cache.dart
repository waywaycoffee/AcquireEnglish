import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../import_course/data/netdisk_local_download.dart';
import '../../sync/data/acquire_api_client.dart';

/// Download textbook lesson MP3 to phone Documents cache (per book/seq).
Future<Directory> k12TextbookAudioDirectory() async {
  final Directory docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}/k12_textbook_audio');
}

bool _isEcsMediaUrl(String url) {
  final String value = url.toLowerCase();
  return value.contains('/media/reading/k12/') ||
      value.contains('/media/reading/textbooks/');
}

Future<File> ensureK12TextbookAudioCached({
  required AcquireApiClient client,
  required String bookId,
  required int seq,
  String? fallbackAudioUrl,
}) async {
  final String id = bookId.trim();
  if (id.isEmpty || seq < 1) {
    throw StateError('无效的教材音频缓存键');
  }
  final Directory root = await k12TextbookAudioDirectory();
  final Directory bookDir = Directory('${root.path}/$id');
  await bookDir.create(recursive: true);
  final File dest = File('${bookDir.path}/$seq.mp3');
  if (dest.existsSync() && dest.lengthSync() > 1024) {
    return dest;
  }

  String url = (fallbackAudioUrl ?? '').trim();
  Map<String, String> headers = <String, String>{};

  if (!_isEcsMediaUrl(url)) {
    final Map<String, dynamic>? resolved =
        await client.getReadingTextbookAudio(id, seq);
    if (resolved != null) {
      final String resolvedUrl = '${resolved['url'] ?? ''}'.trim();
      if (resolvedUrl.isNotEmpty) {
        url = resolvedUrl;
      }
      final Object? rawHeaders = resolved['headers'];
      if (rawHeaders is Map) {
        headers = <String, String>{
          for (final MapEntry<dynamic, dynamic> entry in rawHeaders.entries)
            if ('${entry.key}'.trim().isNotEmpty && entry.value != null)
              '${entry.key}': '${entry.value}',
        };
      }
    }
    if (headers.isEmpty) {
      headers = Map<String, String>.from(kNetdiskStreamHeaders);
    }
  }

  if (url.isEmpty) {
    throw StateError('教材音频地址为空');
  }

  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 3),
      responseType: ResponseType.bytes,
      followRedirects: true,
      validateStatus: (int? code) => code != null && code >= 200 && code < 400,
    ),
  );
  final Response<List<int>> response = await dio.get<List<int>>(
    url,
    options: Options(headers: headers.isEmpty ? null : headers),
  );
  final List<int> bytes = response.data ?? <int>[];
  if (bytes.length < 1024) {
    throw StateError('教材音频下载过短');
  }
  final File part = File('${dest.path}.part');
  await part.writeAsBytes(bytes, flush: true);
  if (dest.existsSync()) {
    await dest.delete();
  }
  await part.rename(dest.path);
  return dest;
}
