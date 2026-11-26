import 'package:flutter/services.dart';

import '../../../constants/endpoints.dart';

String createPlayerMediaUri(String source) {
  final String trimmed = source.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/media/')) {
    final String base = Endpoints.normalizeBaseUrl(Endpoints.baseUrl)
        .replaceAll(RegExp(r'/$'), '');
    return '$base$trimmed';
  }
  return 'asset:///$trimmed';
}

bool playerMediaAvailable(String source) => source.isNotEmpty;

Future<bool> playerRemoteMediaExists(
  String source, {
  Duration timeout = const Duration(milliseconds: 1200),
}) async {
  // Web stub: treat absolute /media URLs as available so callers can proceed.
  final String uri = createPlayerMediaUri(source);
  return uri.startsWith('http://') || uri.startsWith('https://');
}

Future<String> loadPlayerTextSource(String source) async {
  final String trimmed = source.trim();
  if (trimmed.startsWith('/media/')) {
    final String base = Endpoints.normalizeBaseUrl(Endpoints.baseUrl)
        .replaceAll(RegExp(r'/$'), '');
    // Web stub: assets only; relative media paths are not fetched here.
    return rootBundle.loadString('$base$trimmed');
  }
  return rootBundle.loadString(trimmed);
}
