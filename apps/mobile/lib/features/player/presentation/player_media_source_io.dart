import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../constants/endpoints.dart';
import '../data/softsub_paths.dart';
import 'subtitle_text_decode.dart';

String createPlayerMediaUri(String source) {
  final String trimmed = source.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/media/')) {
    return _absoluteApiUrl(trimmed);
  }
  if (_isLocalFilePath(trimmed)) {
    return Uri.file(trimmed).toString();
  }
  return 'asset:///$trimmed';
}

bool playerMediaAvailable(String source) {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return true;
  }
  if (source.startsWith('/media/')) {
    return true;
  }
  if (source.contains('/api/imports/') && source.contains('/srt/')) {
    return true;
  }
  if (source.startsWith('assets/')) {
    return true;
  }
  return File(source).existsSync();
}

/// Fast existence probe for ECS `/media` (or absolute) streams.
///
/// Used so skill-module episodes can fall back to Bilibili stream without a
/// multi-second media_kit open failure when the ECS copy is not uploaded yet.
Future<bool> playerRemoteMediaExists(
  String source, {
  Duration timeout = const Duration(milliseconds: 1200),
}) async {
  final String uri = createPlayerMediaUri(source.trim());
  if (!(uri.startsWith('http://') || uri.startsWith('https://'))) {
    return _isLocalFilePath(source) && File(source).existsSync();
  }
  final HttpClient client = HttpClient();
  client.connectionTimeout = timeout;
  try {
    final HttpClientRequest request = await client
        .headUrl(Uri.parse(uri))
        .timeout(timeout);
    final HttpClientResponse response = await request.close().timeout(timeout);
    final int code = response.statusCode;
    // Drain lightly so the socket can close cleanly.
    await response.drain<void>().timeout(
      const Duration(milliseconds: 400),
      onTimeout: () {},
    );
    return code >= 200 && code < 300;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<String> loadPlayerTextSource(String source) async {
  final String trimmed = source.trim();
  // Auth-gated personal import softsubs — Dio via SoftsubAuthBridge, then local.
  if (classifySoftsubPath(trimmed) == SoftsubPathKind.importsApi) {
    final bool english = trimmed.toLowerCase().contains('/srt/en');
    final int? importId = _importIdFromPath(trimmed);
    if (importId == null) {
      throw StateError('无效的网盘字幕路径');
    }
    final Directory docs = await getApplicationDocumentsDirectory();
    final File cached = File(
      '${docs.path}/netdisk/$importId/${english ? 'en' : 'zh'}.srt',
    );
    if (cached.existsSync() && cached.lengthSync() > 16) {
      return decodeSubtitleBytes(await cached.readAsBytes());
    }
    final SoftsubImportSrtFetcher? fetcher = SoftsubAuthBridge.fetchImportSrt;
    if (fetcher == null) {
      throw StateError('网盘字幕未绑定登录客户端');
    }
    final String? body = await fetcher(
      importId: importId,
      lang: english ? 'en' : 'zh',
    );
    if (body == null || body.trim().isEmpty) {
      throw StateError('网盘字幕为空');
    }
    await cached.parent.create(recursive: true);
    // Persist as UTF-8 so later opens skip charset guessing.
    await cached.writeAsString(body, flush: true);
    return body;
  }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    final HttpClient client = HttpClient();
    try {
      final Uri uri = Uri.parse(trimmed);
      final HttpClientRequest request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 30));
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('字幕加载失败 HTTP ${response.statusCode}');
      }
      final List<int> bytes = await response.fold<List<int>>(
        <int>[],
        (List<int> prev, List<int> chunk) => prev..addAll(chunk),
      );
      return decodeSubtitleBytes(bytes);
    } finally {
      client.close(force: true);
    }
  }
  if (trimmed.startsWith('/media/')) {
    return loadPlayerTextSource(_absoluteApiUrl(trimmed));
  }
  if (_isLocalFilePath(trimmed)) {
    return decodeSubtitleBytes(await File(trimmed).readAsBytes());
  }
  return rootBundle.loadString(trimmed);
}

String _absoluteApiUrl(String path) {
  final String base = Endpoints.normalizeBaseUrl(Endpoints.baseUrl)
      .replaceAll(RegExp(r'/$'), '');
  if (path.startsWith('/')) {
    return '$base$path';
  }
  return '$base/$path';
}

int? _importIdFromPath(String path) {
  final Match? m = RegExp(r'/api/imports/(\d+)/srt/').firstMatch(path);
  return m == null ? null : int.tryParse(m.group(1)!);
}

bool _isLocalFilePath(String source) {
  if (source.isEmpty) {
    return false;
  }
  if (source.startsWith('/media/')) {
    return false;
  }
  return File(source).existsSync();
}
