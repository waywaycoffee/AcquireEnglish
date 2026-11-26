import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/reading_doc.dart';
import '../domain/reading_title_zh.dart';

/// How long a successful auto scan suppresses the next reading-page scan.
const Duration kNetdiskShelfAutoSyncGap = Duration(minutes: 10);

/// One EPUB discovered on the user's own Baidu drive.
class NetdiskEpubRef {
  const NetdiskEpubRef({
    required this.path,
    required this.title,
    this.variant = '未标注版本',
  });

  factory NetdiskEpubRef.fromJson(Map<String, dynamic> json) => NetdiskEpubRef(
    path: '${json['path'] ?? ''}'.trim(),
    title: '${json['title'] ?? ''}'.trim(),
    variant: '${json['variant'] ?? '未标注版本'}'.trim(),
  );

  final String path;
  final String title;
  final String variant;

  String get displayVariant =>
      variant.trim().isEmpty ? '未标注版本' : variant.trim();

  String get displayTitle {
    final String named = title.trim();
    if (named.isNotEmpty) return named;
    final String file = path.split('/').last;
    return _epubStem(file);
  }
}

class NetdiskImportProgress {
  const NetdiskImportProgress({
    required this.index,
    required this.total,
    required this.title,
  });

  final int index;
  final int total;
  final String title;
}

class NetdiskImportOutcome {
  const NetdiskImportOutcome({
    required this.imported,
    required this.skipped,
    required this.failed,
    required this.hitQuota,
    this.errors = const <String>[],
  });

  final int imported;
  final int skipped;
  final int failed;
  final bool hitQuota;
  final List<String> errors;

  static const NetdiskImportOutcome empty = NetdiskImportOutcome(
    imported: 0,
    skipped: 0,
    failed: 0,
    hitQuota: false,
  );
}

/// Remembered Baidu folders and the last sync the reading page should show.
class ReadingNetdiskShelfConfig {
  const ReadingNetdiskShelfConfig({
    this.autoImport = true,
    this.folders = const <String>[],
    this.lastSummary = '',
    this.lastRunAt,
    this.lastFailed = false,
  });

  factory ReadingNetdiskShelfConfig.fromJson(Map<String, dynamic> json) {
    final List<String> folders = <String>[];
    final Object? raw = json['folders'];
    if (raw is List) {
      for (final Object? item in raw) {
        final String path = normalizeNetdiskFolder('$item');
        if (path.isEmpty || folders.contains(path)) continue;
        folders.add(path);
      }
    }
    return ReadingNetdiskShelfConfig(
      autoImport: json['autoImport'] as bool? ?? true,
      folders: List<String>.unmodifiable(folders),
      lastSummary: '${json['lastSummary'] ?? ''}'.trim(),
      lastRunAt: DateTime.tryParse('${json['lastRunAt'] ?? ''}'),
      lastFailed: json['lastFailed'] == true,
    );
  }

  final bool autoImport;
  final List<String> folders;
  final String lastSummary;
  final DateTime? lastRunAt;
  final bool lastFailed;

  bool isWatching(String path) {
    final String normalized = normalizeNetdiskFolder(path);
    return folders.any((String folder) => folder == normalized);
  }

  ReadingNetdiskShelfConfig copyWith({
    bool? autoImport,
    List<String>? folders,
    String? lastSummary,
    DateTime? lastRunAt,
    bool? lastFailed,
  }) => ReadingNetdiskShelfConfig(
    autoImport: autoImport ?? this.autoImport,
    folders: folders ?? this.folders,
    lastSummary: lastSummary ?? this.lastSummary,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    lastFailed: lastFailed ?? this.lastFailed,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'autoImport': autoImport,
    'folders': folders,
    if (lastSummary.isNotEmpty) 'lastSummary': lastSummary,
    if (lastRunAt != null) 'lastRunAt': lastRunAt!.toIso8601String(),
    if (lastFailed) 'lastFailed': true,
  };
}

String _epubStem(String name) {
  String base = name.trim().replaceAll(r'\', '/');
  final int slash = base.lastIndexOf('/');
  if (slash >= 0) base = base.substring(slash + 1);
  base = base.replaceAll(RegExp(r'\.epub$', caseSensitive: false), '');
  return base.isEmpty ? '导入读物' : base;
}

String normalizeNetdiskFolder(String path) {
  String value = path.trim().replaceAll(r'\', '/');
  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/// Stable across devices so a re-scan does not duplicate the same file.
String netdiskReadingDocId(String path) {
  final String normalized = normalizeNetdiskFolder(path);
  final String digest = sha256.convert(utf8.encode(normalized)).toString();
  return 'netdisk_$digest';
}

bool isNetdiskBookImported(NetdiskEpubRef book, Iterable<ReadingDoc> docs) {
  final String path = normalizeNetdiskFolder(book.path);
  if (path.isEmpty) return false;
  final String id = netdiskReadingDocId(path);
  for (final ReadingDoc doc in docs) {
    if (doc.id == id) return true;
    if (normalizeNetdiskFolder(doc.netdiskPath) == path) return true;
    if (_legacyNetdiskDocMatches(doc, book)) return true;
  }
  return false;
}

bool _legacyNetdiskDocMatches(ReadingDoc doc, NetdiskEpubRef book) {
  if (!doc.sourceLabel.startsWith('百度网盘')) return false;
  if (!doc.sourceLabel.contains(book.displayVariant)) return false;
  return normalizeReadingTitleKey(doc.title) ==
      normalizeReadingTitleKey(book.displayTitle);
}

ReadingDoc readingDocFromNetdiskEpub({
  required NetdiskEpubRef book,
  required String plainText,
  DateTime? createdAt,
}) {
  final String path = normalizeNetdiskFolder(book.path);
  return ReadingDoc(
    id: netdiskReadingDocId(path),
    title: book.displayTitle,
    sourceType: ReadingSourceType.import,
    plainText: plainText,
    sourceLabel: '百度网盘 · ${book.displayVariant}',
    netdiskPath: path,
    createdAt: createdAt ?? DateTime.now(),
  );
}

/// Download and parse only books that are not already on the shelf.
Future<NetdiskImportOutcome> importPendingNetdiskEpubs({
  required List<NetdiskEpubRef> books,
  required List<ReadingDoc> existing,
  required int importCount,
  required int maxImportDocs,
  required Future<Uint8List> Function(String path) download,
  required Future<String> Function(Uint8List bytes, String path) parse,
  required Future<ReadingDoc?> Function(ReadingDoc doc) save,
  void Function(NetdiskImportProgress progress)? onProgress,
}) async {
  final Map<String, NetdiskEpubRef> unique = <String, NetdiskEpubRef>{};
  for (final NetdiskEpubRef book in books) {
    final String path = normalizeNetdiskFolder(book.path);
    if (path.isEmpty) continue;
    unique.putIfAbsent(path, () => book);
  }
  final List<ReadingDoc> shelf = List<ReadingDoc>.from(existing);
  final List<NetdiskEpubRef> pending = <NetdiskEpubRef>[];
  int skipped = 0;
  for (final NetdiskEpubRef book in unique.values) {
    if (isNetdiskBookImported(book, shelf)) {
      skipped += 1;
    } else {
      pending.add(book);
    }
  }

  int imported = 0;
  int failed = 0;
  bool hitQuota = false;
  int used = importCount;
  final List<String> errors = <String>[];

  for (int i = 0; i < pending.length; i++) {
    final NetdiskEpubRef book = pending[i];
    if (used >= maxImportDocs) {
      hitQuota = true;
      break;
    }
    onProgress?.call(
      NetdiskImportProgress(
        index: i + 1,
        total: pending.length,
        title: book.displayTitle,
      ),
    );
    try {
      final Uint8List bytes = await download(book.path);
      final String text = (await parse(bytes, book.path)).trim();
      if (text.isEmpty) {
        throw StateError('未能从文件中提取正文');
      }
      final ReadingDoc doc = readingDocFromNetdiskEpub(
        book: book,
        plainText: text,
      );
      final ReadingDoc? saved = await save(doc);
      if (saved == null) {
        throw StateError('未能写入书架');
      }
      shelf.add(saved);
      imported += 1;
      used += 1;
    } catch (error) {
      if (error is StateError && '$error'.contains('上限')) {
        hitQuota = true;
        break;
      }
      failed += 1;
      if (errors.length < 3) {
        errors.add('${book.displayTitle}：${netdiskErrorText(error)}');
      }
    }
  }

  return NetdiskImportOutcome(
    imported: imported,
    skipped: skipped,
    failed: failed,
    hitQuota: hitQuota,
    errors: List<String>.unmodifiable(errors),
  );
}

String summarizeNetdiskImport(
  NetdiskImportOutcome outcome, {
  List<String> scanErrors = const <String>[],
}) {
  final List<String> parts = <String>[
    if (outcome.imported > 0) '新导入 ${outcome.imported} 本',
    if (outcome.skipped > 0) '已在书架 ${outcome.skipped} 本',
    if (outcome.failed > 0) '失败 ${outcome.failed} 本',
    if (outcome.hitQuota) '已达导入上限',
  ];
  if (parts.isEmpty && scanErrors.isEmpty) return '百度网盘书架已是最新';
  final StringBuffer buffer = StringBuffer('百度网盘');
  if (parts.isNotEmpty) buffer.write('：${parts.join('，')}');
  if (scanErrors.isNotEmpty) {
    buffer.write('；${scanErrors.length} 个目录扫描失败');
  }
  if (outcome.imported == 0 && outcome.errors.isNotEmpty) {
    buffer.write('（${outcome.errors.first}）');
  }
  return buffer.toString();
}

String netdiskErrorText(Object error) {
  final String raw = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (raw.length <= 160) return raw;
  return '${raw.substring(0, 160)}…';
}
