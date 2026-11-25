import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../sync/data/acquire_api_client.dart';

const String _historyKey = 'english_browse_history_v1';
const String _studyKey = 'english_browse_study_v1';

class EnglishBrowseEntry {
  const EnglishBrowseEntry({
    required this.watchUrl,
    required this.title,
    required this.bvid,
    this.coverUrl = '',
    this.author = '',
    this.episodeId = '',
    this.courseId = '',
    this.playedAtMs = 0,
    this.liked = false,
    this.favorited = false,
    this.reserved = false,
  });

  final String watchUrl;
  final String title;
  final String bvid;
  final String coverUrl;
  final String author;
  final String episodeId;
  final String courseId;
  final int playedAtMs;
  final bool liked;
  final bool favorited;
  final bool reserved;

  bool get inStudyList => liked || favorited || reserved;

  EnglishBrowseEntry copyWith({
    String? watchUrl,
    String? title,
    String? bvid,
    String? coverUrl,
    String? author,
    String? episodeId,
    String? courseId,
    int? playedAtMs,
    bool? liked,
    bool? favorited,
    bool? reserved,
  }) {
    return EnglishBrowseEntry(
      watchUrl: watchUrl ?? this.watchUrl,
      title: title ?? this.title,
      bvid: bvid ?? this.bvid,
      coverUrl: coverUrl ?? this.coverUrl,
      author: author ?? this.author,
      episodeId: episodeId ?? this.episodeId,
      courseId: courseId ?? this.courseId,
      playedAtMs: playedAtMs ?? this.playedAtMs,
      liked: liked ?? this.liked,
      favorited: favorited ?? this.favorited,
      reserved: reserved ?? this.reserved,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'watchUrl': watchUrl,
        'title': title,
        'bvid': bvid,
        'coverUrl': coverUrl,
        'author': author,
        'episodeId': episodeId,
        'courseId': courseId,
        'playedAtMs': playedAtMs,
        'liked': liked,
        'favorited': favorited,
        'reserved': reserved,
      };

  factory EnglishBrowseEntry.fromJson(Map<String, dynamic> json) {
    return EnglishBrowseEntry(
      watchUrl: '${json['watchUrl'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      bvid: '${json['bvid'] ?? ''}'.trim(),
      coverUrl: '${json['coverUrl'] ?? ''}'.trim(),
      author: '${json['author'] ?? ''}'.trim(),
      episodeId: '${json['episodeId'] ?? ''}'.trim(),
      courseId: '${json['courseId'] ?? ''}'.trim(),
      playedAtMs: (json['playedAtMs'] as num?)?.toInt() ?? 0,
      liked: json['liked'] == true,
      favorited: json['favorited'] == true,
      reserved: json['reserved'] == true,
    );
  }

  factory EnglishBrowseEntry.fromFeed(
    AcquireDailyFeedItemDto item, {
    String episodeId = '',
    String courseId = '',
  }) {
    return EnglishBrowseEntry(
      watchUrl: item.watchUrl.trim(),
      title: item.title.trim(),
      bvid: item.bvid.trim(),
      coverUrl: (item.coverUrl ?? '').trim(),
      author: item.author.trim(),
      episodeId: episodeId,
      courseId: courseId,
      playedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

List<EnglishBrowseEntry> _readList(String key) {
  if (!Hive.isBoxOpen('prefs')) return const <EnglishBrowseEntry>[];
  final String raw = Hive.box<String>('prefs').get(key) ?? '';
  if (raw.trim().isEmpty) return const <EnglishBrowseEntry>[];
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) return const <EnglishBrowseEntry>[];
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (Map<dynamic, dynamic> row) => EnglishBrowseEntry.fromJson(
            row.map(
              (dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v),
            ),
          ),
        )
        .where((EnglishBrowseEntry e) => e.watchUrl.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const <EnglishBrowseEntry>[];
  }
}

Future<void> _writeList(String key, List<EnglishBrowseEntry> items) async {
  if (!Hive.isBoxOpen('prefs')) return;
  await Hive.box<String>('prefs').put(
    key,
    jsonEncode(items.map((EnglishBrowseEntry e) => e.toJson()).toList()),
  );
}

String _normUrl(String url) => url.trim().toLowerCase();

class EnglishBrowseStore extends Notifier<List<EnglishBrowseEntry>> {
  @override
  List<EnglishBrowseEntry> build() {
    final List<EnglishBrowseEntry> history = _readList(_historyKey);
    final List<EnglishBrowseEntry> study = _readList(_studyKey);
    final Map<String, EnglishBrowseEntry> merged = <String, EnglishBrowseEntry>{};
    for (final EnglishBrowseEntry e in history) {
      merged[_normUrl(e.watchUrl)] = e;
    }
    for (final EnglishBrowseEntry e in study) {
      final String key = _normUrl(e.watchUrl);
      final EnglishBrowseEntry? prev = merged[key];
      merged[key] = prev == null
          ? e
          : prev.copyWith(
              liked: prev.liked || e.liked,
              favorited: prev.favorited || e.favorited,
              reserved: prev.reserved || e.reserved,
              episodeId: e.episodeId.isNotEmpty ? e.episodeId : prev.episodeId,
              courseId: e.courseId.isNotEmpty ? e.courseId : prev.courseId,
              playedAtMs: e.playedAtMs > prev.playedAtMs
                  ? e.playedAtMs
                  : prev.playedAtMs,
            );
    }
    final List<EnglishBrowseEntry> all = merged.values.toList(growable: false)
      ..sort(
        (EnglishBrowseEntry a, EnglishBrowseEntry b) =>
            b.playedAtMs.compareTo(a.playedAtMs),
      );
    return all;
  }

  List<EnglishBrowseEntry> get history => state;

  List<EnglishBrowseEntry> get studyList => state
      .where((EnglishBrowseEntry e) => e.inStudyList)
      .toList(growable: false);

  Future<void> recordPlay(EnglishBrowseEntry entry) async {
    final String key = _normUrl(entry.watchUrl);
    if (key.isEmpty) return;
    final List<EnglishBrowseEntry> next = <EnglishBrowseEntry>[
      entry.copyWith(playedAtMs: DateTime.now().millisecondsSinceEpoch),
      ...state.where((EnglishBrowseEntry e) => _normUrl(e.watchUrl) != key),
    ];
    // Cap history length.
    final List<EnglishBrowseEntry> capped = next.take(80).toList(growable: false);
    state = capped;
    await _writeList(_historyKey, capped);
    await _writeList(_studyKey, capped.where((e) => e.inStudyList).toList());
  }

  Future<void> markStudy({
    required String watchUrl,
    bool? liked,
    bool? favorited,
    bool? reserved,
    String? episodeId,
    String? courseId,
    String? title,
    String? bvid,
    String? coverUrl,
    String? author,
  }) async {
    final String key = _normUrl(watchUrl);
    if (key.isEmpty) return;
    EnglishBrowseEntry? existing;
    for (final EnglishBrowseEntry e in state) {
      if (_normUrl(e.watchUrl) == key) {
        existing = e;
        break;
      }
    }
    final EnglishBrowseEntry updated = (existing ??
            EnglishBrowseEntry(
              watchUrl: watchUrl.trim(),
              title: (title ?? '').trim(),
              bvid: (bvid ?? '').trim(),
              coverUrl: (coverUrl ?? '').trim(),
              author: (author ?? '').trim(),
              playedAtMs: DateTime.now().millisecondsSinceEpoch,
            ))
        .copyWith(
          liked: liked,
          favorited: favorited,
          reserved: reserved,
          episodeId: episodeId,
          courseId: courseId,
          title: title,
          bvid: bvid,
          coverUrl: coverUrl,
          author: author,
          playedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
    final List<EnglishBrowseEntry> next = <EnglishBrowseEntry>[
      updated,
      ...state.where((EnglishBrowseEntry e) => _normUrl(e.watchUrl) != key),
    ];
    state = next;
    await _writeList(_historyKey, next);
    await _writeList(
      _studyKey,
      next.where((EnglishBrowseEntry e) => e.inStudyList).toList(),
    );
  }
}

final NotifierProvider<EnglishBrowseStore, List<EnglishBrowseEntry>>
    englishBrowseStoreProvider =
    NotifierProvider<EnglishBrowseStore, List<EnglishBrowseEntry>>(
  EnglishBrowseStore.new,
);
