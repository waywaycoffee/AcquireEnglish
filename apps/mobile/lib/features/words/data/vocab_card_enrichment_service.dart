import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/data/api_usage_ledger.dart';
import '../../settings/presentation/settings_provider.dart';
import '../presentation/word_book_provider.dart';
import 'offline_word_dictionary.dart';

final Provider<VocabCardEnrichmentService> vocabCardEnrichmentServiceProvider =
    Provider<VocabCardEnrichmentService>(
      (Ref ref) => VocabCardEnrichmentService(ref),
    );

class VocabCardEnrichmentResult {
  const VocabCardEnrichmentResult({
    this.phonetic = '',
    this.partOfSpeech = '',
    this.definitionCn = '',
    this.definitionEn = '',
    this.analysisCn = '',
    this.mnemonicCn = '',
    this.rootsAffixesCn = '',
    this.etymologyCn = '',
    this.aiExampleEn = '',
    this.aiExampleCn = '',
  });

  final String phonetic;
  final String partOfSpeech;
  final String definitionCn;
  final String definitionEn;
  final String analysisCn;
  final String mnemonicCn;
  final String rootsAffixesCn;
  final String etymologyCn;
  final String aiExampleEn;
  final String aiExampleCn;
}

/// AI enrichment for collected vocabulary cards (解析 / 助记 / 例句).
class VocabCardEnrichmentService {
  VocabCardEnrichmentService(this._ref);

  final Ref _ref;

  Future<bool> enrichFavorite({
    required String rawWord,
    String? contextSentence,
    String? contextChinese,
    bool force = false,
  }) async {
    final WordBookNotifier book = _ref.read(wordBookProvider.notifier);
    final String word = normalizeLexeme(rawWord);
    if (word.isEmpty) {
      return false;
    }
    WordEntry? existing;
    for (final WordEntry entry in _ref.read(wordBookProvider)) {
      if (entry.word == word) {
        existing = entry;
        break;
      }
    }
    if (existing == null || !existing.favorite) {
      return false;
    }
    if (!force &&
        existing.enrichmentStatus == VocabEnrichmentStatus.ready &&
        (existing.mnemonicCn ?? '').trim().isNotEmpty &&
        (existing.aiExampleEn ?? '').trim().isNotEmpty) {
      return true;
    }

    if (!force && existing.kind == VocabCardKind.word) {
      OfflineWordDefinition? local;
      try {
        local = await _ref.read(offlineWordDictionaryProvider).lookup(word);
      } catch (_) {
        // A missing dictionary asset should not block online enrichment.
      }
      if (local != null && local.translation.trim().isNotEmpty) {
        book.applyEnrichment(
          rawWord: word,
          phonetic: local.phonetic,
          partOfSpeech: local.partOfSpeech,
          definitionCn: existing.definitionCn ?? local.translation,
          status: VocabEnrichmentStatus.ready,
        );
        return true;
      }
    }

    book.markEnrichmentPending(word);
    final LearningSettingsState settings = _ref.read(learningSettingsProvider);
    try {
      final VocabCardEnrichmentResult result = await _requestEnrichment(
        word: word,
        kind: existing.kind,
        contextSentence: contextSentence ?? existing.sourceSentence,
        contextChinese: contextChinese ?? existing.sourceSentenceCn,
        settings: settings,
      );
      book.applyEnrichment(
        rawWord: word,
        phonetic: result.phonetic,
        partOfSpeech: result.partOfSpeech,
        definitionCn: result.definitionCn,
        definitionEn: result.definitionEn,
        analysisCn: result.analysisCn,
        mnemonicCn: result.mnemonicCn,
        rootsAffixesCn: result.rootsAffixesCn,
        etymologyCn: result.etymologyCn,
        aiExampleEn: result.aiExampleEn,
        aiExampleCn: result.aiExampleCn,
        status: VocabEnrichmentStatus.ready,
      );
      return true;
    } catch (_) {
      book.applyEnrichment(rawWord: word, status: VocabEnrichmentStatus.failed);
      return false;
    }
  }

  Future<VocabCardEnrichmentResult> _requestEnrichment({
    required String word,
    required VocabCardKind kind,
    required String contextSentence,
    required String contextChinese,
    required LearningSettingsState settings,
  }) async {
    if (!_canUseAi(settings)) {
      throw StateError('请先在设置中配置可用的 AI 翻译接口。');
    }
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: settings.translationBaseUrl,
        headers: <String, String>{
          'Authorization':
              'Bearer ${settings.translationApiKey.trim().isEmpty ? 'ollama' : settings.translationApiKey.trim()}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          ...acquireUsageHeaders(module: 'vocab_enrich'),
        },
        sendTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    final String kindLabel = kind.labelCn;
    final Response<dynamic> response = await dio.post<dynamic>(
      '/chat/completions',
      data: <String, dynamic>{
        'model': settings.translationModel,
        'temperature': 0.4,
        'response_format': const <String, String>{'type': 'json_object'},
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'system',
            'content':
                'You help Chinese learners build vocabulary cards. '
                'Return strict JSON with keys: phonetic, partOfSpeech, definitionCn, '
                'definitionEn, analysisCn, mnemonicCn, rootsAffixesCn, etymologyCn, '
                'aiExampleEn, aiExampleCn. '
                'analysisCn = brief Chinese explanation of meaning/usage in context. '
                'mnemonicCn = a vivid Chinese memory tip (谐音/联想均可，简洁有趣). '
                'rootsAffixesCn = Chinese note on useful prefixes/roots/suffixes and 1-2 related words. '
                'etymologyCn = short Chinese etymology / word-origin story (Latin/Greek/Old English if relevant). '
                'aiExampleEn = one new natural English example (not copying the source). '
                'aiExampleCn = Chinese translation of that example. '
                'Keep each field short (under 80 Chinese chars / 25 English words).',
          },
          <String, String>{
            'role': 'user',
            'content':
                'Card kind: $kindLabel\n'
                'Lexeme: "$word"\n'
                'Source sentence: "${contextSentence.trim()}"\n'
                'Source Chinese: "${contextChinese.trim()}"\n'
                'Fill the vocabulary card JSON including roots/affixes and etymology.',
          },
        ],
      },
    );
    final Map<String, dynamic> responseData =
        response.data as Map<String, dynamic>;
    final List<dynamic> choices = responseData['choices'] as List<dynamic>;
    final Map<String, dynamic> message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>;
    final String content = '${message['content'] ?? ''}';
    unawaited(
      ApiUsageLedger.instance.recordChatCompletionResponse(
        kind: ApiUsageKind.wordLookup,
        module: 'vocab_enrich',
        provider: settings.translationProvider,
        model: settings.translationModel,
        responseData: responseData,
        messages: <Map<String, String>>[
          <String, String>{'role': 'user', 'content': word},
        ],
        completionText: content,
      ),
    );
    final Map<String, dynamic> decoded =
        jsonDecode(_extractJsonObject(content)) as Map<String, dynamic>;
    return VocabCardEnrichmentResult(
      phonetic: '${decoded['phonetic'] ?? ''}'.trim(),
      partOfSpeech: '${decoded['partOfSpeech'] ?? ''}'.trim(),
      definitionCn: '${decoded['definitionCn'] ?? ''}'.trim(),
      definitionEn: '${decoded['definitionEn'] ?? ''}'.trim(),
      analysisCn: '${decoded['analysisCn'] ?? ''}'.trim(),
      mnemonicCn: '${decoded['mnemonicCn'] ?? ''}'.trim(),
      rootsAffixesCn: '${decoded['rootsAffixesCn'] ?? ''}'.trim(),
      etymologyCn: '${decoded['etymologyCn'] ?? ''}'.trim(),
      aiExampleEn: '${decoded['aiExampleEn'] ?? ''}'.trim(),
      aiExampleCn: '${decoded['aiExampleCn'] ?? ''}'.trim(),
    );
  }

  bool _canUseAi(LearningSettingsState settings) {
    if (settings.translationProvider == '本地 Ollama') {
      return settings.translationBaseUrl.trim().isNotEmpty;
    }
    if (settings.translationProvider == '百度翻译' ||
        settings.translationProvider == '阿里云翻译' ||
        settings.translationProvider == 'Google 翻译') {
      return false;
    }
    return settings.translationApiKey.trim().isNotEmpty &&
        settings.translationBaseUrl.trim().isNotEmpty;
  }

  String _extractJsonObject(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }
    final int start = trimmed.indexOf('{');
    final int end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return trimmed.substring(start, end + 1);
    }
    return trimmed;
  }
}
