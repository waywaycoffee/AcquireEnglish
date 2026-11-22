import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/vocabulary_placement_estimate.dart';

typedef PlacementRow = Map<String, dynamic>;

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

  Future<List<PlacementRow>> loadQuestions() => _fetch('placement');

  Future<void> saveEstimate(int estimate) async {
    final String key = _key;
    final int safeEstimate = estimate.clamp(
      kPlacementEstimateMin,
      kPlacementEstimateMax,
    );
    final int start = (safeEstimate * 0.8).round().clamp(
      1,
      kPlacementEstimateMax - 1000,
    );
    final List<PlacementRow> words = await _fetch(
      'recommendations',
      parameters: <String, dynamic>{'start': start},
    );
    if (words.isEmpty) throw StateError('推荐词库为空');
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
    final Dio client = Dio(
      BaseOptions(
        baseUrl: ref.read(learningSettingsProvider).resolvedCloudApiBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    try {
      final Response<List<dynamic>> response = await client.get<List<dynamic>>(
        'api/public-lexicon/$endpoint',
        queryParameters: parameters,
      );
      return (response.data ?? const <dynamic>[]).cast<PlacementRow>();
    } finally {
      client.close();
    }
  }
}
