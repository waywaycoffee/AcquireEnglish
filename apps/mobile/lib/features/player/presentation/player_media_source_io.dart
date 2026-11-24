import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../constants/endpoints.dart';
import '../data/softsub_paths.dart';

String createPlayerMediaUri(String source) {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return source;
  }
  if (_isLocalFilePath(source)) {
    return Uri.file(source).toString();
  }
  return 'asset:///$source';
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
      return cached.readAsString();
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
        throw StateError('字幕下载失败 HTTP ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
  if (trimmed.startsWith('/media/')) {
    final String base = Endpoints.normalizeBaseUrl(Endpoints.baseUrl)
        .replaceAll(RegExp(r'/$'), '');
    return loadPlayerTextSource('$base$trimmed');
  }
  if (_isLocalFilePath(trimmed)) {
    return File(trimmed).readAsString();
  }
  return rootBundle.loadString(trimmed);
}

int? _importIdFromPath(String path) {
  final Match? m = RegExp(r'/api/imports/(\d+)/srt/').firstMatch(path);
  return m == null ? null : int.tryParse(m.group(1)!);
}

bool _isLocalFilePath(String source) {
  if (source.isEmpty) {
    return false;
  }
  return File(source).existsSync();
}
