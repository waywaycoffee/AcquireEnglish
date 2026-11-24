/// Path classification + auth bridge for softsubs (no player-loader imports).
library;

import 'dart:io';

import '../../sync/data/acquire_api_client.dart';

enum SoftsubPathKind {
  empty,
  localFile,
  importsApi,
  mediaRelative,
  httpUrl,
  assetOrOther,
}

typedef SoftsubImportSrtFetcher = Future<String?> Function({
  required int importId,
  required String lang,
});

/// Process-wide auth fetch for `/api/imports` (bound from [acquireApiClientProvider]).
class SoftsubAuthBridge {
  SoftsubAuthBridge._();
  static SoftsubImportSrtFetcher? fetchImportSrt;

  static void bindApiClient(AcquireApiClient api) {
    fetchImportSrt = ({required int importId, required String lang}) =>
        api.fetchPersonalImportSrt(importId: importId, lang: lang);
  }
}

SoftsubPathKind classifySoftsubPath(String? path) {
  final String value = (path ?? '').trim();
  if (value.isEmpty) {
    return SoftsubPathKind.empty;
  }
  final String lower = value.toLowerCase();
  if (lower.contains('/api/imports/') && lower.contains('/srt/')) {
    return SoftsubPathKind.importsApi;
  }
  if (value.startsWith('/media/')) {
    return SoftsubPathKind.mediaRelative;
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    if (lower.contains('/api/imports/') && lower.contains('/srt/')) {
      return SoftsubPathKind.importsApi;
    }
    return SoftsubPathKind.httpUrl;
  }
  if (value.startsWith('assets/')) {
    return SoftsubPathKind.assetOrOther;
  }
  if (File(value).existsSync()) {
    return SoftsubPathKind.localFile;
  }
  if (value.contains(Platform.pathSeparator) ||
      value.contains('/') ||
      value.contains('\\')) {
    return SoftsubPathKind.localFile;
  }
  return SoftsubPathKind.assetOrOther;
}

bool softsubPathLooksPresent(String? path) {
  final SoftsubPathKind kind = classifySoftsubPath(path);
  switch (kind) {
    case SoftsubPathKind.empty:
      return false;
    case SoftsubPathKind.importsApi:
    case SoftsubPathKind.mediaRelative:
    case SoftsubPathKind.httpUrl:
      return true;
    case SoftsubPathKind.localFile:
      final File file = File(path!.trim());
      return file.existsSync() && file.lengthSync() > 16;
    case SoftsubPathKind.assetOrOther:
      return path!.trim().isNotEmpty;
  }
}
