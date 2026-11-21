import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../domain/video_difficulty.dart';

const String kVideoDifficultyCachePrefsKey = 'video_difficulty_cache_v1';

class VideoDifficultyStore {
  const VideoDifficultyStore();

  Future<Map<String, VideoDifficultyEstimate>> load() async {
    if (!Hive.isBoxOpen('prefs')) {
      return const <String, VideoDifficultyEstimate>{};
    }
    final String? raw = Hive.box<String>('prefs').get(kVideoDifficultyCachePrefsKey);
    if (raw == null || raw.isEmpty) {
      return const <String, VideoDifficultyEstimate>{};
    }
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((String courseId, dynamic value) {
        return MapEntry<String, VideoDifficultyEstimate>(
          courseId,
          VideoDifficultyEstimate.fromJson(
            Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
          ),
        );
      });
    } catch (_) {
      return const <String, VideoDifficultyEstimate>{};
    }
  }

  Future<void> save(Map<String, VideoDifficultyEstimate> byCourseId) async {
    if (!Hive.isBoxOpen('prefs')) {
      return;
    }
    final Map<String, Object?> encoded = <String, Object?>{
      for (final MapEntry<String, VideoDifficultyEstimate> e
          in byCourseId.entries)
        e.key: e.value.toJson(),
    };
    await Hive.box<String>('prefs').put(
      kVideoDifficultyCachePrefsKey,
      jsonEncode(encoded),
    );
  }
}
