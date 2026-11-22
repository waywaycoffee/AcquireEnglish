import 'package:flutter/services.dart';

import '../../../constants/endpoints.dart';

String createPlayerMediaUri(String source) {
  if (source.startsWith('http://') || source.startsWith('https://')) {
    return source;
  }
  return 'asset:///$source';
}

bool playerMediaAvailable(String source) => source.isNotEmpty;

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
