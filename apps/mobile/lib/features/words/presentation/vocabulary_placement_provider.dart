import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../settings/presentation/settings_provider.dart';

typedef PlacementRow = Map<String, dynamic>;

final vocabularyPlacementProvider =
    NotifierProvider<VocabularyPlacement, PlacementRow>(
      VocabularyPlacement.new,
    );

final recommendedWordsProvider = Provider<Set<String>>((Ref ref) {
  final PlacementRow profile = ref.watch(vocabularyPlacementProvider);
  return (profile['words'] as List<dynamic>? ?? const <dynamic>[])
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
    final int start = (estimate * 0.8).round().clamp(1, 20000);
    final List<PlacementRow> words = await _fetch(
      'recommendations',
      parameters: <String, dynamic>{'start': start},
    );
    if (words.isEmpty) throw StateError('推荐词库为空');
    final PlacementRow result = <String, dynamic>{
      'estimate': estimate,
      'start': start,
      'words': words,
    };
    if (_key != key) throw StateError('账号已切换');
    if (Hive.isBoxOpen('prefs')) {
      await Hive.box<String>('prefs').put(key, jsonEncode(result));
    }
    if (_key == key) state = result;
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
