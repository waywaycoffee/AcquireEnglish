import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../constants/endpoints.dart';
import 'dub_session_store.dart';

/// Resolves an accompaniment (no-vocals) track for 趣配音-style mixing.
///
/// Quality path: POST audio to a stem-separation service (GPU box).
/// Returns null when genuine stem separation is unavailable.
class DubAccompanimentService {
  DubAccompanimentService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<String?> ensureAccompaniment({
    required String episodeId,
    required String videoSource,
    required String accessToken,
  }) async {
    final String? cached = await DubSessionStore.instance.accompanimentPath(
      episodeId,
    );
    if (cached != null) {
      return cached;
    }
    if (videoSource.isEmpty ||
        videoSource.startsWith('http://') ||
        videoSource.startsWith('https://')) {
      return null;
    }
    final File video = File(videoSource);
    if (!video.existsSync()) {
      return null;
    }

    if (accessToken.isEmpty) return null;
    return _fetchFromStemServer(
      episodeId: episodeId,
      videoPath: video.path,
      accessToken: accessToken,
    );
  }

  Future<String?> _fetchFromStemServer({
    required String episodeId,
    required String videoPath,
    required String accessToken,
  }) async {
    final FormData form = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(videoPath),
    });
    final Response<ResponseBody> response = await _dio.post<ResponseBody>(
      Uri.parse(
        Endpoints.normalizeBaseUrl(Endpoints.baseUrl),
      ).resolve('api/stem/separate').toString(),
      data: form,
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $accessToken'},
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(minutes: 10),
      ),
    );
    final ResponseBody? body = response.data;
    if (body == null) return null;
    final Directory temp = await getTemporaryDirectory();
    final Directory work = await temp.createTemp('acq-stem-');
    final File file = File('${work.path}/instrumental.wav');
    try {
      await body.stream.cast<List<int>>().pipe(file.openWrite());
      if (await file.length() < 44) return null;
      final RandomAccessFile input = await file.open();
      final List<int> header;
      try {
        header = await input.read(12);
      } finally {
        await input.close();
      }
      if (String.fromCharCodes(header.take(4)) != 'RIFF' ||
          String.fromCharCodes(header.skip(8)) != 'WAVE')
        return null;
      await DubSessionStore.instance.saveAccompanimentPath(
        episodeId: episodeId,
        sourcePath: file.path,
      );
      return DubSessionStore.instance.accompanimentPath(episodeId);
    } finally {
      await work.delete(recursive: true);
    }
  }
}
