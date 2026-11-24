import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../constants/endpoints.dart';
import '../domain/drama_catalog.dart';

/// Device-side poster cache for curated drama shelf.
///
/// Remote files live on ECS under `/media/misc/drama-covers/{id}.jpg`
/// (never shipped inside the APK). After the first download, posters open
/// from `Documents/drama_covers/` so the hub does not wait on the network.
final Map<String, String> _memoryLocalById = <String, String>{};
Future<void>? _prefetchJob;

Future<Directory> dramaCoverDirectory() async {
  final Directory docs = await getApplicationDocumentsDirectory();
  final Directory dir = Directory('${docs.path}/drama_covers');
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
  }
  return dir;
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
  for (final String ext in <String>['.jpg', '.jpeg', '.png', '.webp']) {
    final File file = File('${dir.path}/$entryId$ext');
    if (file.existsSync() && file.lengthSync() > 1024) {
      _memoryLocalById[entryId] = file.path;
      return file;
    }
  }
  return null;
}

/// Instant local path when already cached (sync, for first paint).
String? cachedDramaCoverPathSync(String entryId) {
  final String? remembered = _memoryLocalById[entryId];
  if (remembered == null) {
    return null;
  }
  try {
    final File file = File(remembered);
    if (file.existsSync() && file.lengthSync() > 1024) {
      return remembered;
    }
  } catch (_) {}
  _memoryLocalById.remove(entryId);
  return null;
}

/// Ensure one catalog poster exists under Documents/drama_covers.
Future<String?> ensureDramaCoverCached(DramaCatalogEntry entry) async {
  final Directory dir = await dramaCoverDirectory();
  final File? hit = _localHit(entry.id, dir);
  if (hit != null) {
    return hit.path;
  }
  final String remote = resolveDramaCoverRemoteUrl(
    entry.coverUrl ?? entry.id,
  );
  if (remote.isEmpty) {
    return null;
  }
  final File out = File('${dir.path}/${entry.id}.jpg');
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
    _memoryLocalById[entry.id] = out.path;
    return out.path;
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
      await Future.wait(
        kDramaCatalog.map(ensureDramaCoverCached),
      );
    } finally {
      _prefetchJob = null;
    }
  }();
}
