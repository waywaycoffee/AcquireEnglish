import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

const String dictationQueueStorageKey = 'dictation_queue_v1';

class DictationQueueItem {
  const DictationQueueItem({
    required this.id,
    required this.english,
    required this.chinese,
    required this.startMs,
    required this.endMs,
    required this.startTime,
    this.episodeId,
    this.courseTitle,
    this.episodeTitle,
    this.difficult = false,
    this.addedAtMs,
  });

  final String id;
  final String english;
  final String chinese;
  final int startMs;
  final int endMs;
  final String startTime;
  final String? episodeId;
  final String? courseTitle;
  final String? episodeTitle;
  final bool difficult;
  final int? addedAtMs;

  factory DictationQueueItem.fromJson(Map<String, dynamic> json) {
    return DictationQueueItem(
      id: json['id'] as String? ?? '',
      english: json['english'] as String? ?? '',
      chinese: json['chinese'] as String? ?? '',
      startMs: (json['startMs'] as num?)?.toInt() ?? 0,
      endMs: (json['endMs'] as num?)?.toInt() ?? 0,
      startTime: json['startTime'] as String? ?? '',
      episodeId: json['episodeId'] as String?,
      courseTitle: json['courseTitle'] as String?,
      episodeTitle: json['episodeTitle'] as String?,
      difficult: json['difficult'] as bool? ?? false,
      addedAtMs: (json['addedAtMs'] as num?)?.toInt(),
    );
  }

  DictationQueueItem copyWith({bool? difficult}) => DictationQueueItem(
    id: id,
    english: english,
    chinese: chinese,
    startMs: startMs,
    endMs: endMs,
    startTime: startTime,
    episodeId: episodeId,
    courseTitle: courseTitle,
    episodeTitle: episodeTitle,
    difficult: difficult ?? this.difficult,
    addedAtMs: addedAtMs,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'english': english,
    'chinese': chinese,
    'startMs': startMs,
    'endMs': endMs,
    'startTime': startTime,
    'episodeId': episodeId,
    'courseTitle': courseTitle,
    'episodeTitle': episodeTitle,
    'difficult': difficult,
    'addedAtMs': addedAtMs,
  };

  static String buildId({
    required String? episodeId,
    required int startMs,
    required int endMs,
    required String english,
  }) {
    final String ep = (episodeId ?? 'local').trim();
    final String text = english.trim().toLowerCase();
    return '$ep|$startMs|$endMs|$text';
  }
}

final NotifierProvider<DictationQueueNotifier, List<DictationQueueItem>>
dictationQueueProvider =
    NotifierProvider<DictationQueueNotifier, List<DictationQueueItem>>(
      DictationQueueNotifier.new,
    );

class DictationQueueNotifier extends Notifier<List<DictationQueueItem>> {
  @override
  List<DictationQueueItem> build() => _load();

  List<DictationQueueItem> _load() {
    if (!Hive.isBoxOpen('prefs')) {
      return const <DictationQueueItem>[];
    }
    final String? raw = Hive.box<String>('prefs').get(dictationQueueStorageKey);
    if (raw == null || raw.isEmpty) {
      return const <DictationQueueItem>[];
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> item) => DictationQueueItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((DictationQueueItem item) => item.english.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <DictationQueueItem>[];
    }
  }

  Future<void> _persist() async {
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    await Hive.box<String>('prefs').put(
      dictationQueueStorageKey,
      jsonEncode(state.map((DictationQueueItem e) => e.toJson()).toList()),
    );
  }

  Future<bool> addOrUpdate(DictationQueueItem item) async {
    final int existing = state.indexWhere(
      (DictationQueueItem e) => e.id == item.id,
    );
    if (existing >= 0) {
      final List<DictationQueueItem> next = List<DictationQueueItem>.from(state);
      final DictationQueueItem current = next[existing];
      next[existing] = current.copyWith(
        difficult: current.difficult || item.difficult,
      );
      state = List<DictationQueueItem>.unmodifiable(next);
      await _persist();
      return false;
    }
    state = List<DictationQueueItem>.unmodifiable(<DictationQueueItem>[
      item,
      ...state,
    ]);
    await _persist();
    return true;
  }

  Future<void> markDifficult(String id, {bool value = true}) async {
    state = List<DictationQueueItem>.unmodifiable(
      state
          .map(
            (DictationQueueItem item) =>
                item.id == id ? item.copyWith(difficult: value) : item,
          )
          .toList(),
    );
    await _persist();
  }

  Future<void> remove(String id) async {
    state = List<DictationQueueItem>.unmodifiable(
      state.where((DictationQueueItem item) => item.id != id).toList(),
    );
    await _persist();
  }

  Future<void> clear() async {
    state = const <DictationQueueItem>[];
    await _persist();
  }
}
