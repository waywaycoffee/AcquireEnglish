import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../constants/endpoints.dart';
import '../../library/presentation/library_mock_data.dart';
import '../domain/drama_catalog.dart';

/// Device-side poster cache for curated drama shelf.
///
/// Remote files live on ECS under `/media/misc/drama-covers/{id}.jpg`
/// (never shipped inside the APK). After the first download, posters open
/// from `Documents/drama_covers/` — preferably the small `.poster.jpg` thumb.
const String _prefsCoversDirKey = 'drama_covers_dir_v1';
const int _posterThumbWidth = 360;

final Map<String, String> _memoryLocalById = <String, String>{};
String? _coversRoot;
Future<void>? _prefetchJob;
Future<void>? _primeJob;

Future<Directory> dramaCoverDirectory() async {
  if (_coversRoot != null && _coversRoot!.isNotEmpty) {
    final Directory cached = Directory(_coversRoot!);
    if (!cached.existsSync()) {
      await cached.create(recursive: true);
    }
    return cached;
  }
  final Directory docs = await getApplicationDocumentsDirectory();
  final Directory dir = Directory('${docs.path}/drama_covers');
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

String resolveDramaCoverRemoteUrl(String? coverUrlOrSlug) {
  final String value = (coverUrlOrSlug ?? '').trim();
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
  return '$base/media/misc/drama-covers/$value.jpg';
}

File? _localHit(String entryId, Directory dir) {
  final String? remembered = _memoryLocalById[entryId];
  if (remembered != null) {
    final File rememberedFile = File(remembered);
    if (rememberedFile.existsSync() && rememberedFile.lengthSync() > 1024) {
      return rememberedFile;
    }
    _memoryLocalById.remove(entryId);
  }
  // Prefer tiny poster thumb for shelf paint; fall back to full JPEG.
  for (final String name in <String>[
    '$entryId.poster.jpg',
    '$entryId.jpg',
    '$entryId.jpeg',
    '$entryId.png',
    '$entryId.webp',
  ]) {
    final File file = File('${dir.path}/$name');
    if (file.existsSync() && file.lengthSync() > 1024) {
      _memoryLocalById[entryId] = file.path;
      return file;
    }
  }
  return null;
}

/// Best sync cover for a library course that matches the curated drama shelf.
///
/// Prefers a local `Documents/drama_covers` hit; otherwise the absolute ECS URL
/// so home「最近看过」can paint immediately even before download finishes.
String? dramaCoverForCourseSync(LibraryCourseData course) {
  final DramaCatalogEntry? entry = catalogEntryForCourse(course);
  if (entry == null) {
    return null;
  }
  final String? local = cachedDramaCoverPathSync(entry.id);
  if (local != null && local.trim().isNotEmpty) {
    return local;
  }
  final String remote = resolveDramaCoverRemoteUrl(entry.coverUrl ?? entry.id);
  return remote.isEmpty ? null : remote;
}

/// Instant local path when already cached (sync, for first paint).
///
/// Uses in-memory map, then a Hive-persisted covers directory so cold start
/// does not wait on `path_provider` before showing posters.
String? cachedDramaCoverPathSync(String entryId) {
  final String? remembered = _memoryLocalById[entryId];
  if (remembered != null) {
    try {
      final File file = File(remembered);
      if (file.existsSync() && file.lengthSync() > 1024) {
        return remembered;
      }
    } catch (_) {}
    _memoryLocalById.remove(entryId);
  }
  final String? root = _readPersistedCoversRoot();
  if (root == null) {
    return null;
  }
  try {
    return _localHit(entryId, Directory(root))?.path;
  } catch (_) {
    return null;
  }
}

/// Sync scan of known covers dir into memory (no await). Call from hub initState.
void primeDramaCoverCacheSyncFromPersisted() {
  final String? root = _readPersistedCoversRoot();
  if (root == null) {
    return;
  }
  final Directory dir = Directory(root);
  if (!dir.existsSync()) {
    return;
  }
  for (final DramaCatalogEntry entry in kDramaCatalog) {
    _localHit(entry.id, dir);
  }
}

/// Resolve docs path once and index every local poster into memory.
Future<void> primeDramaCoverCacheFromDisk() {
  return _primeJob ??= () async {
    try {
      final Directory dir = await dramaCoverDirectory();
      for (final DramaCatalogEntry entry in kDramaCatalog) {
        _localHit(entry.id, dir);
      }
    } finally {
      _primeJob = null;
    }
  }();
}

Future<void> _writePosterThumb({
  required List<int> bytes,
  required File thumbOut,
}) async {
  try {
    final img.Image? decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      return;
    }
    final img.Image sized = decoded.width <= _posterThumbWidth
        ? decoded
        : img.copyResize(
            decoded,
            width: _posterThumbWidth,
            interpolation: img.Interpolation.average,
          );
    final List<int> encoded = img.encodeJpg(sized, quality: 82);
    final File part = File('${thumbOut.path}.part');
    await part.writeAsBytes(encoded, flush: true);
    if (thumbOut.existsSync()) {
      await thumbOut.delete();
    }
    await part.rename(thumbOut.path);
  } catch (_) {
    // Full JPEG still usable if thumb encode fails.
  }
}

/// Ensure one catalog poster exists under Documents/drama_covers.
Future<String?> ensureDramaCoverCached(DramaCatalogEntry entry) async {
  final Directory dir = await dramaCoverDirectory();
  final File? hit = _localHit(entry.id, dir);
  if (hit != null) {
    // Backfill missing thumb from full JPEG for faster next open.
    final File thumb = File('${dir.path}/${entry.id}.poster.jpg');
    if (!thumb.existsSync() &&
        hit.path.endsWith('.jpg') &&
        !hit.path.endsWith('.poster.jpg')) {
      unawaited(() async {
        try {
          final List<int> bytes = await hit.readAsBytes();
          await _writePosterThumb(bytes: bytes, thumbOut: thumb);
          if (thumb.existsSync() && thumb.lengthSync() > 1024) {
            _memoryLocalById[entry.id] = thumb.path;
          }
        } catch (_) {}
      }());
    }
    return hit.path;
  }
  final String remote = resolveDramaCoverRemoteUrl(
    entry.coverUrl ?? entry.id,
  );
  if (remote.isEmpty) {
    return null;
  }
  final File out = File('${dir.path}/${entry.id}.jpg');
  final File thumb = File('${dir.path}/${entry.id}.poster.jpg');
  final File part = File('${out.path}.part');
  try {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        followRedirects: true,
        maxRedirects: 5,
        responseType: ResponseType.bytes,
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
    await _writePosterThumb(bytes: bytes, thumbOut: thumb);
    final String displayPath =
        thumb.existsSync() && thumb.lengthSync() > 1024 ? thumb.path : out.path;
    _memoryLocalById[entry.id] = displayPath;
    return displayPath;
  } catch (_) {
    try {
      if (part.existsSync()) {
        await part.delete();
      }
    } catch (_) {}
    return null;
  }
}

/// Warm every curated poster once (deduped). Safe to call from hub open.
Future<void> prefetchAllDramaCovers() {
  return _prefetchJob ??= () async {
    try {
      await primeDramaCoverCacheFromDisk();
      await Future.wait(
        kDramaCatalog.map(ensureDramaCoverCached),
      );
    } finally {
      _prefetchJob = null;
    }
  }();
}
