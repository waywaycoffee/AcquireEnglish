import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/bilibili_import.dart';

class BilibiliImportResult {
  const BilibiliImportResult({
    required this.idKey,
    required this.title,
    required this.watchUrl,
    required this.durationMinutes,
    this.enSubtitlePath,
    this.cnSubtitlePath,
    this.author,
  });

  final String idKey;
  final String title;
  final String watchUrl;
  final int durationMinutes;
  final String? enSubtitlePath;
  final String? cnSubtitlePath;
  final String? author;
}

class BilibiliImportService {
  BilibiliImportService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              headers: <String, dynamic>{
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Referer': 'https://www.bilibili.com',
                'Accept': 'application/json, text/plain, */*',
              },
            ),
          );

  final Dio _dio;

  Future<BilibiliImportResult> fetch(String rawInput) async {
    final Map<String, String>? ids = BilibiliImport.extractIds(rawInput);
    if (ids == null) {
      throw ArgumentError('无效的 Bilibili 链接');
    }

    final Response<dynamic> viewRes = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/web-interface/view',
      queryParameters: ids,
    );
    final Map<String, dynamic> viewRoot =
        viewRes.data as Map<String, dynamic>? ?? <String, dynamic>{};
    if ((viewRoot['code'] as int? ?? -1) != 0) {
      throw StateError(
        (viewRoot['message'] as String?) ?? '无法获取 Bilibili 视频信息',
      );
    }
    final Map<String, dynamic> data =
        viewRoot['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final String bvid = (data['bvid'] as String?) ?? ids['bvid'] ?? '';
    final int? aid = (data['aid'] as num?)?.toInt() ?? int.tryParse(ids['aid'] ?? '');
    final String rawTitle = (data['title'] as String?)?.trim() ?? '';
    final String title = rawTitle.isNotEmpty
        ? rawTitle
        : (bvid.isNotEmpty ? bvid : 'av$aid');
    final String? author =
        (data['owner'] as Map<String, dynamic>?)?['name'] as String?;
    final int durationSec = (data['duration'] as num?)?.toInt() ?? 60;
    final List<dynamic> pages =
        data['pages'] as List<dynamic>? ?? const <dynamic>[];
    final int? pageCid = pages.isEmpty
        ? null
        : (pages.first as Map<String, dynamic>?)?['cid'] as int?;
    final int cid = (data['cid'] as num?)?.toInt() ?? pageCid ?? 0;

    final String watch = BilibiliImport.watchUrl(
      bvid: bvid.isEmpty ? null : bvid,
      aid: aid?.toString(),
    );
    final String idKey = bvid.isNotEmpty ? bvid : 'av$aid';

    String? enPath;
    String? cnPath;
    if (cid > 0 && bvid.isNotEmpty) {
      try {
        final Map<String, String?> tracks = await _fetchSubtitles(
          bvid: bvid,
          cid: cid,
          idKey: idKey,
        );
        enPath = tracks['en'];
        cnPath = tracks['zh'];
      } catch (_) {}
    }

    return BilibiliImportResult(
      idKey: idKey,
      title: title,
      watchUrl: watch,
      durationMinutes: (durationSec / 60).ceil().clamp(1, 24 * 60),
      enSubtitlePath: enPath,
      cnSubtitlePath: cnPath,
      author: author,
    );
  }

  Future<Map<String, String?>> _fetchSubtitles({
    required String bvid,
    required int cid,
    required String idKey,
  }) async {
    final Response<dynamic> playerRes = await _dio.get<dynamic>(
      'https://api.bilibili.com/x/player/v2',
      queryParameters: <String, dynamic>{'bvid': bvid, 'cid': cid},
    );
    final Map<String, dynamic> root =
        playerRes.data as Map<String, dynamic>? ?? <String, dynamic>{};
    if ((root['code'] as int? ?? -1) != 0) {
      return const <String, String?>{};
    }
    final Map<String, dynamic>? subtitleRoot =
        (root['data'] as Map<String, dynamic>?)?['subtitle']
            as Map<String, dynamic>?;
    final List<dynamic> list =
        subtitleRoot?['subtitles'] as List<dynamic>? ?? const <dynamic>[];
    if (list.isEmpty) {
      return const <String, String?>{};
    }

    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/bilibili/$idKey');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    String? enPath;
    String? zhPath;
    for (final dynamic raw in list) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final String lan = (raw['lan'] as String? ?? '').toLowerCase();
      final String? url = raw['subtitle_url'] as String?;
      if (url == null || url.isEmpty) {
        continue;
      }
      final String absolute = url.startsWith('//')
          ? 'https:$url'
          : url.startsWith('http')
          ? url
          : 'https:$url';
      final bool isZh =
          lan.contains('zh') || lan.contains('中') || lan == 'ai-zh';
      final bool isEn = lan.startsWith('en') || lan.contains('英');
      if (!isZh && !isEn) {
        continue;
      }
      final String? path = await _downloadJsonSubtitleToSrt(
        absolute,
        File('${dir.path}/${isEn ? 'en' : 'zh'}.srt'),
      );
      if (isEn) {
        enPath ??= path;
      } else {
        zhPath ??= path;
      }
    }
    return <String, String?>{'en': enPath, 'zh': zhPath};
  }

  Future<String?> _downloadJsonSubtitleToSrt(String url, File outFile) async {
    final Response<dynamic> res = await _dio.get<dynamic>(url);
    final dynamic body = res.data;
    final Map<String, dynamic> json = body is String
        ? jsonDecode(body) as Map<String, dynamic>
        : body as Map<String, dynamic>;
    final List<dynamic> cues =
        json['body'] as List<dynamic>? ?? const <dynamic>[];
    if (cues.isEmpty) {
      return null;
    }
    final StringBuffer srt = StringBuffer();
    int index = 1;
    for (final dynamic cue in cues) {
      if (cue is! Map<String, dynamic>) {
        continue;
      }
      final double from = (cue['from'] as num?)?.toDouble() ?? 0;
      final double to = (cue['to'] as num?)?.toDouble() ?? from + 1;
      final String content = (cue['content'] as String? ?? '').trim();
      if (content.isEmpty) {
        continue;
      }
      srt
        ..writeln(index)
        ..writeln('${_fmt(from)} --> ${_fmt(to)}')
        ..writeln(content)
        ..writeln();
      index += 1;
    }
    if (index == 1) {
      return null;
    }
    await outFile.writeAsString(srt.toString(), flush: true);
    return outFile.path;
  }

  String _fmt(double seconds) {
    final Duration d = Duration(milliseconds: (seconds * 1000).round());
    final int hours = d.inHours;
    final int minutes = d.inMinutes.remainder(60);
    final int secs = d.inSeconds.remainder(60);
    final int millis = d.inMilliseconds.remainder(1000);
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(hours)}:${two(minutes)}:${two(secs)},${three(millis)}';
  }
}
