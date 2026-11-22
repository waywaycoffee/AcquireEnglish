import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../constants/endpoints.dart';

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
  if (source.startsWith('assets/')) {
    return true;
  }
  return File(source).existsSync();
}

Future<String> loadPlayerTextSource(String source) async {
  final String trimmed = source.trim();
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

bool _isLocalFilePath(String source) {
  if (source.isEmpty) {
    return false;
  }
  return File(source).existsSync();
}
