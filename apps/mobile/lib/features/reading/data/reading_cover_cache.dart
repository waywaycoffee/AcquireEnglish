import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../../constants/endpoints.dart';

/// Device-side jacket cache for reading shelf covers.
///
/// Remote files live on ECS under `/media/reading/covers/{key}.jpg`
/// (never shipped in the APK). After the first download, shelves paint from
/// `Documents/reading_covers/` so Huawei / flaky networks do not fall back
/// to the cloth hardcover.
const String _prefsCoversDirKey = 'reading_covers_dir_v1';

final Map<String, String> _memoryLocalByKey = <String, String>{};
String? _coversRoot;
final Map<String, Future<String?>> _inflight = <String, Future<String?>>{};

/// Known ECS cover keys for featured classics (from media/reading/covers/index.json).
const Map<String, String> kFeaturedReadingCoverKeys = <String, String>{
  'the wonderful wizard of oz': 'cdc9ad096923711e194f',
  'pride and prejudice': 'd3904b9776ead26b01c2',
  'frankenstein': 'c9fd3a9a67de456fb7ff',
  'dracula': '6497c62337f89a2b3a9c',
  "alice's adventures in wonderland": '6ee2f0077d8ac64b8620',
  'the adventures of sherlock holmes': '1c0a4de6819fe6d953bb',
  'a christmas carol': '0fb46357804fddadcae6',
  'treasure island': '940750d00df635ba7cfa',
  "gulliver's travels": '1303e9ddce713b826eb2',
  'adventures of huckleberry finn': '3ad1a3adb516fbf40a7c',
  'moby dick': '118362294f236540d583',
};

/// Stable relative cover path for Wizard of Oz (seeded on ECS).
const String kWizardOfOzCoverRelative =
    '/media/reading/covers/cdc9ad096923711e194f.jpg';

String? featuredReadingCoverRelativeForTitle(String title) {
  final String normalized = title
      .replaceAll(RegExp(r'[\(（][^\)）]*[\)）]'), '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) {
    return null;
  }
  for (final MapEntry<String, String> e in kFeaturedReadingCoverKeys.entries) {
    if (normalized == e.key ||
        normalized.contains(e.key) ||
        e.key.contains(normalized)) {
      return '/media/reading/covers/${e.value}.jpg';
    }
  }
  return null;
}

Future<Directory> readingCoverDirectory() async {
  if (_coversRoot != null && _coversRoot!.isNotEmpty) {
    final Directory cached = Directory(_coversRoot!);
    if (!cached.existsSync()) {
      await cached.create(recursive: true);
    }
    return cached;
  }
  final Directory docs = await getApplicationDocumentsDirectory();
  final Directory dir = Directory('${docs.path}/reading_covers');
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  _coversRoot = dir.path;
  _persistCoversRoot(dir.path);
  return dir;
}

void _persistCoversRoot(String path) {
  if (!Hive.isBoxOpen('prefs')) {
    return;
  }
  unawaited(Hive.box<String>('prefs').put(_prefsCoversDirKey, path));
}

String? _readPersistedCoversRoot() {
  if (_coversRoot != null && _coversRoot!.isNotEmpty) {
    return _coversRoot;
  }
  if (!Hive.isBoxOpen('prefs')) {
    return null;
  }
  final String? saved =
      Hive.box<String>('prefs').get(_prefsCoversDirKey)?.trim();
  if (saved == null || saved.isEmpty) {
    return null;
  }
  _coversRoot = saved;
  return saved;
}

String readingCoverCacheKey(String coverUrlOrDocId) {
  final String raw = coverUrlOrDocId.trim();
  if (raw.isEmpty) {
    return '';
  }
  final RegExpMatch? media = RegExp(
    r'/media/reading/covers/([a-f0-9]{8,40})\.(?:jpe?g|png|webp)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (media != null) {
    return media.group(1)!.toLowerCase();
  }
  // Doc id / arbitrary string → filesystem-safe key.
  final String cleaned = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_\-]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (cleaned.isEmpty) {
    return '';
  }
  return cleaned.length <= 64 ? cleaned : cleaned.substring(0, 64);
}

String resolveReadingCoverRemoteUrl(String? coverUrl) {
  final String value = (coverUrl ?? '').trim();
  if (value.isEmpty) {
    return '';
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  final String base = Endpoints.normalizeBaseUrl(Endpoints.baseUrl)
      .replaceAll(RegExp(r'/$'), '');
  if (value.startsWith('/')) {
    return '$base$value';
  }
  return '$base/media/reading/covers/$value.jpg';
}

File? _localHit(String key, Directory dir) {
  if (key.isEmpty) {
    return null;
  }
  final String? remembered = _memoryLocalByKey[key];
  if (remembered != null) {
    final File rememberedFile = File(remembered);
    if (rememberedFile.existsSync() && rememberedFile.lengthSync() > 1024) {
      return rememberedFile;
    }
    _memoryLocalByKey.remove(key);
  }
  for (final String name in <String>[
    '$key.jpg',
    '$key.jpeg',
    '$key.png',
    '$key.webp',
  ]) {
    final File file = File('${dir.path}/$name');
    if (file.existsSync() && file.lengthSync() > 1024) {
      _memoryLocalByKey[key] = file.path;
      return file;
    }
  }
  return null;
}

/// Instant local path when already cached (sync, for first paint).
String? cachedReadingCoverPathSync(String coverUrlOrDocId) {
  final String key = readingCoverCacheKey(coverUrlOrDocId);
  if (key.isEmpty) {
    return null;
  }
  final String? remembered = _memoryLocalByKey[key];
  if (remembered != null) {
    try {
      final File file = File(remembered);
      if (file.existsSync() && file.lengthSync() > 1024) {
        return remembered;
      }
    } catch (_) {}
    _memoryLocalByKey.remove(key);
  }
  final String? root = _readPersistedCoversRoot();
  if (root == null) {
    return null;
  }
  try {
    return _localHit(key, Directory(root))?.path;
  } catch (_) {
    return null;
  }
}

/// Download (or reuse) a jacket into Documents/reading_covers.
Future<String?> ensureReadingCoverCached(String coverUrl) async {
  final String remote = resolveReadingCoverRemoteUrl(coverUrl);
  if (remote.isEmpty) {
    return null;
  }
  final String key = readingCoverCacheKey(coverUrl);
  if (key.isEmpty) {
    return null;
  }
  final Future<String?>? existing = _inflight[key];
  if (existing != null) {
    return existing;
  }
  final Future<String?> job = () async {
    final Directory dir = await readingCoverDirectory();
    final File? hit = _localHit(key, dir);
    if (hit != null) {
      return hit.path;
    }
    final File out = File('${dir.path}/$key.jpg');
    final File part = File('${out.path}.part');
    try {
      final Dio dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
          followRedirects: true,
          maxRedirects: 5,
          responseType: ResponseType.bytes,
          headers: const <String, String>{
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            'Accept': 'image/jpeg,image/*,*/*',
          },
          validateStatus: (int? code) =>
              code != null && code >= 200 && code < 400,
        ),
      );
      final Response<List<int>> resp = await dio.get<List<int>>(remote);
      final List<int>? bytes = resp.data;
      if (bytes == null || bytes.length < 1024) {
        return null;
      }
      await part.writeAsBytes(bytes, flush: true);
      if (out.existsSync()) {
        await out.delete();
      }
      await part.rename(out.path);
      _memoryLocalByKey[key] = out.path;
      return out.path;
    } catch (_) {
      try {
        if (part.existsSync()) {
          await part.delete();
        }
      } catch (_) {}
      return null;
    } finally {
      _inflight.remove(key);
    }
  }();
  _inflight[key] = job;
  return job;
}

/// Warm local jackets for a list of ECS cover URLs (deduped).
Future<void> prefetchReadingCovers(Iterable<String> coverUrls) async {
  final List<String> urls = coverUrls
      .map((String u) => u.trim())
      .where((String u) => u.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (urls.isEmpty) {
    return;
  }
  await Future.wait(urls.map(ensureReadingCoverCached));
}
