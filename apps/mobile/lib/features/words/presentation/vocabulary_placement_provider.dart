import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../constants/endpoints.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/vocabulary_placement_estimate.dart';

typedef PlacementRow = Map<String, dynamic>;

const String _placementQuestionsCacheKey = 'vocabularyPlacementQuestions:v1';
const String _fallbackAssetPath =
    'assets/data/vocabulary_placement_fallback.json';

/// Soft gate: estimate + testedAt must both exist.
bool hasCompletedVocabularyPlacement(PlacementRow profile) =>
    profile['estimate'] is int &&
    (profile['testedAt'] as String? ?? '').trim().isNotEmpty;

/// Reminds once per app process while the user still has no estimate.
bool _placementReminderShownThisSession = false;

bool consumeVocabularyPlacementReminder({required bool hasPlacement}) {
  if (hasPlacement) return false;
  if (_placementReminderShownThisSession) return false;
  _placementReminderShownThisSession = true;
  return true;
}

@visibleForTesting
void resetVocabularyPlacementReminderForTest() {
  _placementReminderShownThisSession = false;
}

final vocabularyPlacementProvider =
    NotifierProvider<VocabularyPlacement, PlacementRow>(
      VocabularyPlacement.new,
    );

final predictedVocabularyProvider = Provider<int?>((Ref ref) {
  final PlacementRow profile = ref.watch(vocabularyPlacementProvider);
  final int? estimate = profile['estimate'] as int?;
  if (estimate == null) return null;
  final List<dynamic> learned =
      profile['learnedWords'] as List<dynamic>? ?? const <dynamic>[];
  return estimate + learned.length;
});

final recommendedWordsProvider = Provider<Set<String>>((Ref ref) {
  final Object? words = ref.watch(
    vocabularyPlacementProvider.select(
      (PlacementRow profile) => profile['words'],
    ),
  );
  return (words as List<dynamic>? ?? const <dynamic>[])
      .cast<PlacementRow>()
      .map((PlacementRow row) => row['word'] as String)
      .toSet();
});

class VocabularyPlacement extends Notifier<PlacementRow> {
  String get _key {
    final String email = ref
        .read(authSessionProvider)
        .email
        .trim()
        .toLowerCase();
    return 'vocabularyPlacement:v1:$email';
  }

  @override
  PlacementRow build() {
    ref.watch(
      authSessionProvider.select((AuthSessionState auth) => auth.email),
    );
    if (!Hive.isBoxOpen('prefs')) return <String, dynamic>{};
    final String? raw = Hive.box<String>('prefs').get(_key);
    if (raw == null) return <String, dynamic>{};
    try {
      return jsonDecode(raw) as PlacementRow;
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  Future<List<PlacementRow>> loadQuestions() async {
    Object? lastError;
    try {
      final List<PlacementRow> remote = await _fetch(
        'placement',
        parameters: const <String, dynamic>{'per_band': 18},
      );
      if (remote.isNotEmpty) {
        await _cacheQuestions(remote);
        return remote;
      }
    } catch (error) {
      lastError = error;
    }

    final List<PlacementRow> cached = _readCachedQuestions();
    if (cached.isNotEmpty) return cached;

    final List<PlacementRow> bundled = await _loadBundledQuestions();
    if (bundled.isNotEmpty) return bundled;

    throw StateError(
      lastError == null
          ? '词库未返回测试题'
          : '题目加载失败：${_shortError(lastError)}',
    );
  }

  Future<void> saveEstimate(int estimate, {bool requireRecommendations = true}) async {
    final String key = _key;
    final int safeEstimate = estimate.clamp(
      kPlacementEstimateMin,
      kPlacementEstimateMax,
    );
    final int start = (safeEstimate * 0.8).round().clamp(
      1,
      kPlacementEstimateMax - 1000,
    );
    List<PlacementRow> words = const <PlacementRow>[];
    if (requireRecommendations) {
      words = await _fetch(
        'recommendations',
        parameters: <String, dynamic>{'start': start},
      );
      if (words.isEmpty) throw StateError('推荐词库为空');
    } else {
      words = (state['words'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<PlacementRow>()
          .toList(growable: false);
    }
    final PlacementRow result = <String, dynamic>{
      'estimate': safeEstimate,
      'testedAt': DateTime.now().toUtc().toIso8601String(),
      'start': start,
      'words': words,
    };
    if (_key != key) throw StateError('账号已切换');
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(key, jsonEncode(result));
    }
    if (_key == key) state = result;
  }

  Future<void> recordLearnedWord(
    String rawWord, {
    DateTime? previouslyLearnedAt,
    String? accountAtReview,
  }) async {
    if (state['estimate'] == null) return;
    final String key = _key;
    if (accountAtReview != null && key != accountAtReview) return;
    final DateTime? testedAt = DateTime.tryParse(
      state['testedAt'] as String? ?? '',
    );
    if (previouslyLearnedAt != null &&
        (testedAt == null || previouslyLearnedAt.isBefore(testedAt))) {
      return;
    }
    final String word = rawWord.trim().toLowerCase().replaceAll('’', "'");
    if (!RegExp(r"^[a-z]+(?:[-'][a-z]+)*$").hasMatch(word)) return;
    final Set<String> learned = <String>{
      ...(state['learnedWords'] as List<dynamic>? ?? const <dynamic>[])
          .cast<String>(),
    };
    if (!learned.add(word)) return;
    final PlacementRow result = <String, dynamic>{
      ...state,
      'learnedWords': learned.toList(),
    };
    state = result;
    if (Hive.isBoxOpen('prefs')) {
      try {
        await Hive.box<String>('prefs').put(key, jsonEncode(result));
      } catch (_) {
        // Updating the estimate must not invalidate a completed review.
      }
    }
  }

  String get accountKey => _key;

  /// Offline demo recommendations (no network). Marked with `demo: true`.
  Future<void> seedDemoRecommendations() async {
    final String key = _key;
    final PlacementRow result = <String, dynamic>{
      'estimate': 3200,
      'testedAt': DateTime.now().toUtc().toIso8601String(),
      'start': 2500,
      'demo': true,
      'words': <PlacementRow>[
        <String, dynamic>{'word': 'serendipity', 'rank': 1},
        <String, dynamic>{'word': 'ephemeral', 'rank': 2},
        <String, dynamic>{'word': 'ubiquitous', 'rank': 3},
        <String, dynamic>{'word': 'pragmatic', 'rank': 4},
        <String, dynamic>{'word': 'resilient', 'rank': 5},
        <String, dynamic>{'word': 'nuance', 'rank': 6},
      ],
    };
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(key, jsonEncode(result));
    }
    if (_key == key) state = result;
  }

  Future<void> clearDemoRecommendations() async {
    if (state['demo'] != true) return;
    final String key = _key;
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').delete(key);
    }
    if (_key == key) state = <String, dynamic>{};
  }

  Future<List<PlacementRow>> _fetch(
    String endpoint, {
    Map<String, dynamic>? parameters,
  }) async {
    // Dedicated Dio: avoid MemCacheStore (placement is ORDER BY random())
    // and use the same generous timeouts as the rest of the app.
    final Dio client = Dio(
      BaseOptions(
        baseUrl: ref.read(learningSettingsProvider).resolvedCloudApiBaseUrl,
        connectTimeout: Duration(milliseconds: Endpoints.connectionTimeout),
        receiveTimeout: Duration(milliseconds: Endpoints.receiveTimeout),
        headers: const <String, dynamic>{'Accept': 'application/json'},
      ),
    );
    try {
      final Response<dynamic> response = await client.get<dynamic>(
        'api/public-lexicon/$endpoint',
        queryParameters: parameters,
      );
      return _parseListPayload(response.data);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _cacheQuestions(List<PlacementRow> rows) async {
    if (!Hive.isBoxOpen('prefs') || rows.isEmpty) return;
    try {
      await Hive.box<String>('prefs').put(
        _placementQuestionsCacheKey,
        jsonEncode(rows),
      );
    } catch (_) {}
  }

  List<PlacementRow> _readCachedQuestions() {
    if (!Hive.isBoxOpen('prefs')) return const <PlacementRow>[];
    final String? raw =
        Hive.box<String>('prefs').get(_placementQuestionsCacheKey);
    if (raw == null || raw.isEmpty) return const <PlacementRow>[];
    try {
      return _parseListPayload(jsonDecode(raw));
    } catch (_) {
      return const <PlacementRow>[];
    }
  }

  Future<List<PlacementRow>> _loadBundledQuestions() async {
    try {
      final String raw = await rootBundle.loadString(_fallbackAssetPath);
      return _parseListPayload(jsonDecode(raw));
    } catch (_) {
      return const <PlacementRow>[];
    }
  }

  List<PlacementRow> _parseListPayload(Object? data) {
    if (data is! List) return const <PlacementRow>[];
    return data
        .whereType<Map>()
        .map((Map row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _shortError(Object error) {
    if (error is DioException) {
      final int? code = error.response?.statusCode;
      if (code != null) return 'HTTP $code';
      return error.type.name;
    }
    final String text = error.toString();
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }
}
