import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';

/// One user take aligned to a subtitle window.
class DubTake {
  const DubTake({
    required this.episodeId,
    required this.lineId,
    required this.startMs,
    required this.endMs,
    required this.english,
    required this.userWavPath,
    required this.createdAt,
    this.scorePercent,
    this.professionalScore = false,
  });

  factory DubTake.fromJson(Map<String, dynamic> json) => DubTake(
    scorePercent: (json['scorePercent'] as num?)?.toInt(),
    professionalScore: json['professionalScore'] == true,
    episodeId: '${json['episodeId'] ?? ''}',
    lineId: '${json['lineId'] ?? ''}',
    startMs: (json['startMs'] as num?)?.toInt() ?? 0,
    endMs: (json['endMs'] as num?)?.toInt() ?? 0,
    english: '${json['english'] ?? ''}',
    userWavPath: '${json['userWavPath'] ?? ''}',
    createdAt:
        DateTime.tryParse('${json['createdAt'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final bool professionalScore;
  final int? scorePercent;
  final String episodeId;
  final String lineId;
  final int startMs;
  final int endMs;
  final String english;
  final String userWavPath;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'scorePercent': scorePercent,
    'professionalScore': professionalScore,
    'episodeId': episodeId,
    'lineId': lineId,
    'startMs': startMs,
    'endMs': endMs,
    'english': english,
    'userWavPath': userWavPath,
    'createdAt': createdAt.toIso8601String(),
  };

  bool get fileExists =>
      userWavPath.isNotEmpty && File(userWavPath).existsSync();
}

/// Persists per-episode dub takes under app documents.
class DubSessionStore {
  DubSessionStore._();

  DubSessionStore.forDirectory(Directory directory) : _directory = directory;
  Directory? _directory;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static final DubSessionStore instance = DubSessionStore._();

  Future<Directory> _episodeDir(String episodeId) async {
    final Directory root =
        _directory ?? await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${root.path}/dub_sessions/$episodeId');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _indexFile(String episodeId) async {
    final Directory dir = await _episodeDir(episodeId);
    return File('${dir.path}/takes.json');
  }

  Future<List<DubTake>> loadTakes(
    String episodeId, {
    bool history = false,
  }) async {
    final File file = await _indexFile(episodeId);
    if (!file.existsSync()) {
      return const <DubTake>[];
    }
    try {
      final Object? raw = jsonDecode(await file.readAsString());
      if (raw is! List<dynamic>) {
        return const <DubTake>[];
      }
      final List<DubTake> parsed = <DubTake>[];
      for (final Object? row in raw) {
        if (row is! Map) {
          continue;
        }
        final Map<String, dynamic> asMap = <String, dynamic>{
          for (final MapEntry<dynamic, dynamic> entry in row.entries)
            '${entry.key}': entry.value,
        };
        final DubTake take = DubTake.fromJson(asMap);
        if (take.fileExists) {
          parsed.add(take);
        }
      }
      if (history) return parsed;
      final Map<String, DubTake> selected = <String, DubTake>{};
      for (final DubTake take in parsed) {
        selected[take.lineId] = take;
      }
      return selected.values.toList()
        ..sort((DubTake a, DubTake b) => a.startMs.compareTo(b.startMs));
    } catch (_) {
      return const <DubTake>[];
    }
  }

  Future<void> saveTake(DubTake take) async {
    final Directory dir = await _episodeDir(take.episodeId);
    // Copy wav into durable session folder so temp cleanup won't delete it.
    final String durablePath =
        '${dir.path}/take-${take.lineId.replaceAll(RegExp('[^0-9A-Za-z_-]'), '_')}-${take.createdAt.microsecondsSinceEpoch}.wav';
    final File source = File(take.userWavPath);
    if (!source.existsSync()) {
      throw StateError('录音文件不存在，无法保存配音。');
    }
    if (source.path != durablePath) {
      await source.copy(durablePath);
    }
    final DubTake durable = DubTake(
      episodeId: take.episodeId,
      lineId: take.lineId,
      startMs: take.startMs,
      endMs: take.endMs,
      english: take.english,
      userWavPath: durablePath,
      createdAt: take.createdAt,
      scorePercent: take.scorePercent,
      professionalScore: take.professionalScore,
    );
    final List<DubTake> existing = await loadTakes(
      take.episodeId,
      history: true,
    );
    final List<DubTake> next = <DubTake>[
      for (final DubTake row in existing)
        if (row.userWavPath != durable.userWavPath) row,
      durable,
    ];
    final File index = await _indexFile(take.episodeId);
    final File pending = File('${index.path}.pending');
    await pending.writeAsString(
      jsonEncode(next.map((DubTake t) => t.toJson()).toList(growable: false)),
      flush: true,
    );
    await pending.rename(index.path);
    revision.value++;
  }

  Future<String?> accompanimentPath(String episodeId) async {
    final Directory dir = await _episodeDir(episodeId);
    final File file = File('${dir.path}/separated_background_v2.wav');
    return file.existsSync() ? file.path : null;
  }

  Future<void> saveAccompanimentPath({
    required String episodeId,
    required String sourcePath,
  }) async {
    final Directory dir = await _episodeDir(episodeId);
    final String dest = '${dir.path}/separated_background_v2.wav';
    final File source = File(sourcePath);
    if (!source.existsSync()) {
      throw StateError('伴奏轨不存在。');
    }
    if (source.path != dest) {
      await source.copy(dest);
    }
  }
}
