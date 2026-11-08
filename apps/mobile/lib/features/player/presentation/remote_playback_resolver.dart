import 'package:dio/dio.dart';
import 'package:media_kit/media_kit.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../import_course/domain/bilibili_import.dart';
import '../../import_course/domain/youtube_import.dart';
import 'player_media_source.dart';

/// Resolved remote playable URI + optional HTTP headers (Bilibili CDN needs Referer).
class ResolvedRemoteMedia {
  const ResolvedRemoteMedia({
    required this.uri,
    this.httpHeaders,
    this.audioOnly = false,
  });

  final String uri;
  final Map<String, String>? httpHeaders;
  final bool audioOnly;
}

/// Turn watch-page URLs (Bilibili / YouTube) into a Media media_kit can open.
/// Local files / direct CDN URLs pass through unchanged.
Future<Media> resolvePlayerMedia(String source) async {
  final String trimmed = source.trim();
  if (trimmed.isEmpty) {
    return Media(createPlayerMediaUri(trimmed));
  }
  if (BilibiliImport.isBilibiliUrl(trimmed)) {
    final ResolvedRemoteMedia remote = await resolveBilibiliPlayback(trimmed);
    return Media(remote.uri, httpHeaders: remote.httpHeaders);
  }
  if (YoutubeImport.isYoutubeUrl(trimmed)) {
    final ResolvedRemoteMedia remote = await resolveYoutubePlayback(trimmed);
    return Media(remote.uri, httpHeaders: remote.httpHeaders);
  }
  return Media(createPlayerMediaUri(trimmed));
}

Future<ResolvedRemoteMedia> resolveBilibiliPlayback(String raw) async {
  final Map<String, String>? ids = BilibiliImport.extractIds(raw);
  if (ids == null) {
    throw StateError('无效的 Bilibili 链接');
  }

  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: <String, dynamic>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Referer': 'https://www.bilibili.com',
        'Accept': 'application/json, text/plain, */*',
      },
    ),
  );

  final Response<dynamic> viewRes = await dio.get<dynamic>(
    'https://api.bilibili.com/x/web-interface/view',
    queryParameters: ids,
  );
  final Map<String, dynamic> viewRoot =
      viewRes.data as Map<String, dynamic>? ?? <String, dynamic>{};
  if ((viewRoot['code'] as int? ?? -1) != 0) {
    throw StateError((viewRoot['message'] as String?) ?? '无法获取 B 站视频信息');
  }
  final Map<String, dynamic> data =
      viewRoot['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  final String bvid = (data['bvid'] as String?) ?? ids['bvid'] ?? '';
  final List<dynamic> pages = data['pages'] as List<dynamic>? ?? const <dynamic>[];
  final int? pageCid = pages.isEmpty
      ? null
      : ((pages.first as Map<String, dynamic>?)?['cid'] as num?)?.toInt();
  final int cid = (data['cid'] as num?)?.toInt() ?? pageCid ?? 0;
  if (cid <= 0 || bvid.isEmpty) {
    throw StateError('缺少 bvid/cid，无法解析播放地址');
  }

  final Map<String, String> cdnHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Referer': 'https://www.bilibili.com',
    'Accept': '*/*',
  };

  // 1) Prefer legacy combined durl (A+V) — media_kit/mpv can play flv/mp4.
  try {
    final Response<dynamic> durlRes = await dio.get<dynamic>(
      'https://api.bilibili.com/x/player/playurl',
      queryParameters: <String, dynamic>{
        'bvid': bvid,
        'cid': cid,
        'qn': 64,
        'fnval': 0,
      },
    );
    final Map<String, dynamic> root =
        durlRes.data as Map<String, dynamic>? ?? <String, dynamic>{};
    if ((root['code'] as int? ?? -1) == 0) {
      final List<dynamic> durl =
          (root['data'] as Map<String, dynamic>?)?['durl'] as List<dynamic>? ??
              const <dynamic>[];
      if (durl.isNotEmpty) {
        final String? url =
            (durl.first as Map<String, dynamic>?)?['url'] as String?;
        if (url != null && url.isNotEmpty) {
          return ResolvedRemoteMedia(uri: url, httpHeaders: cdnHeaders);
        }
      }
    }
  } catch (_) {
    // Fall through to DASH.
  }

  // 2) DASH: prefer mid-quality video (picture); audio may be missing on some
  // devices — then fall back to audio-only so 精听/跟读 still get currentTime.
  final Response<dynamic> dashRes = await dio.get<dynamic>(
    'https://api.bilibili.com/x/player/playurl',
    queryParameters: <String, dynamic>{
      'bvid': bvid,
      'cid': cid,
      'fnval': 16,
      'fourk': 1,
    },
  );
  final Map<String, dynamic> dashRoot =
      dashRes.data as Map<String, dynamic>? ?? <String, dynamic>{};
  if ((dashRoot['code'] as int? ?? -1) != 0) {
    throw StateError((dashRoot['message'] as String?) ?? '无法获取 B 站播放地址');
  }
  final Map<String, dynamic> dash =
      (dashRoot['data'] as Map<String, dynamic>?)?['dash']
          as Map<String, dynamic>? ??
      <String, dynamic>{};

  final List<dynamic> videos = dash['video'] as List<dynamic>? ?? const <dynamic>[];
  if (videos.isNotEmpty) {
    final List<Map<String, dynamic>> sorted = videos
        .whereType<Map<String, dynamic>>()
        .toList()
      ..sort(
        (Map<String, dynamic> a, Map<String, dynamic> b) =>
            ((a['bandwidth'] as num?)?.toInt() ?? 0).compareTo(
              (b['bandwidth'] as num?)?.toInt() ?? 0,
            ),
      );
    final Map<String, dynamic> picked = sorted[sorted.length ~/ 2];
    final String? url =
        (picked['baseUrl'] as String?) ?? (picked['base_url'] as String?);
    if (url != null && url.isNotEmpty) {
      return ResolvedRemoteMedia(uri: url, httpHeaders: cdnHeaders);
    }
  }

  final List<dynamic> audios = dash['audio'] as List<dynamic>? ?? const <dynamic>[];
  if (audios.isNotEmpty) {
    final List<Map<String, dynamic>> sorted = audios
        .whereType<Map<String, dynamic>>()
        .toList()
      ..sort(
        (Map<String, dynamic> a, Map<String, dynamic> b) =>
            ((a['bandwidth'] as num?)?.toInt() ?? 0).compareTo(
              (b['bandwidth'] as num?)?.toInt() ?? 0,
            ),
      );
    final Map<String, dynamic> picked = sorted[sorted.length ~/ 2];
    final String? url =
        (picked['baseUrl'] as String?) ?? (picked['base_url'] as String?);
    if (url != null && url.isNotEmpty) {
      return ResolvedRemoteMedia(
        uri: url,
        httpHeaders: cdnHeaders,
        audioOnly: true,
      );
    }
  }

  throw StateError('该 B 站视频暂无可用直链，请改用本地下载后导入');
}

Future<ResolvedRemoteMedia> resolveYoutubePlayback(String raw) async {
  final String? id = YoutubeImport.extractVideoId(raw);
  if (id == null) {
    throw StateError('无效的 YouTube 链接');
  }
  final YoutubeExplode yt = YoutubeExplode();
  try {
    final StreamManifest manifest = await yt.videos.streamsClient.getManifest(
      id,
    );
    if (manifest.muxed.isNotEmpty) {
      final MuxedStreamInfo muxed = manifest.muxed.withHighestBitrate();
      return ResolvedRemoteMedia(uri: muxed.url.toString());
    }
    if (manifest.audioOnly.isNotEmpty) {
      final AudioOnlyStreamInfo audio = manifest.audioOnly.withHighestBitrate();
      return ResolvedRemoteMedia(uri: audio.url.toString(), audioOnly: true);
    }
    throw StateError('该 YouTube 视频暂无可用直链');
  } finally {
    yt.close();
  }
}

bool isRemoteWatchPage(String source) {
  final String s = source.trim();
  return BilibiliImport.isBilibiliUrl(s) || YoutubeImport.isYoutubeUrl(s);
}
