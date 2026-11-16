import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../presentation/desktop_ffmpeg.dart';
import 'dub_session_store.dart';

/// Resolves an accompaniment (no-vocals) track for 趣配音-style mixing.
///
/// Quality path: POST audio to a stem-separation service (GPU box).
/// Fallback: local ffmpeg center-channel attenuation, else null (UI ducks).
class DubAccompanimentService {
  DubAccompanimentService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Optional stem server, e.g. `http://192.168.1.8:8790`.
  static const String stemServerUrl = String.fromEnvironment(
    'STEM_SEPARATION_URL',
    defaultValue: '',
  );

  Future<String?> ensureAccompaniment({
    required String episodeId,
    required String videoSource,
    String? stemBaseUrl,
  }) async {
    final String? cached =
        await DubSessionStore.instance.accompanimentPath(episodeId);
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

    final String base = (stemBaseUrl ?? stemServerUrl).trim();
    if (base.isNotEmpty) {
      try {
        final String? remote = await _fetchFromStemServer(
          episodeId: episodeId,
          videoPath: video.path,
          baseUrl: base.replaceAll(RegExp(r'/+$'), ''),
        );
        if (remote != null) {
          return remote;
        }
      } catch (_) {}
    }

    try {
      final String? local = await _localCenterAttenuate(video.path);
      if (local != null) {
        await DubSessionStore.instance.saveAccompanimentPath(
          episodeId: episodeId,
          sourcePath: local,
        );
        return DubSessionStore.instance.accompanimentPath(episodeId);
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _fetchFromStemServer({
    required String episodeId,
    required String videoPath,
    required String baseUrl,
  }) async {
    final FormData form = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(videoPath),
      'episode_id': episodeId,
    });
    final Response<dynamic> response = await _dio.post<dynamic>(
      '$baseUrl/v1/separate',
      data: form,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(minutes: 10),
      ),
    );
    final List<int>? bytes = response.data is List<int>
        ? response.data as List<int>
        : null;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    final Directory temp = await getTemporaryDirectory();
    final String path =
        '${temp.path}/stem-no-vocals-${DateTime.now().microsecondsSinceEpoch}.wav';
    await File(path).writeAsBytes(bytes, flush: true);
    await DubSessionStore.instance.saveAccompanimentPath(
      episodeId: episodeId,
      sourcePath: path,
    );
    return DubSessionStore.instance.accompanimentPath(episodeId);
  }

  /// Weak local fallback: attenuate mid (approx vocals) with ffmpeg pan.
  Future<String?> _localCenterAttenuate(String videoPath) async {
    final String? ffmpeg = await findDesktopFfmpeg();
    if (ffmpeg == null) {
      return null;
    }
    final Directory temp = await getTemporaryDirectory();
    final String out =
        '${temp.path}/accomp-center-${DateTime.now().microsecondsSinceEpoch}.wav';
    final ProcessResult result = await Process.run(ffmpeg, <String>[
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-i',
      videoPath,
      '-vn',
      '-af',
      'pan=stereo|c0=0.5*c0+-0.5*c1|c1=-0.5*c0+0.5*c1,aformat=sample_fmts=s16:sample_rates=16000:channel_layouts=mono',
      '-ac',
      '1',
      '-ar',
      '16000',
      out,
    ]);
    if (result.exitCode != 0 || !File(out).existsSync()) {
      return null;
    }
    return out;
  }
}
