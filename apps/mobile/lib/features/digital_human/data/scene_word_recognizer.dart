import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../../../constants/endpoints.dart';
import '../../../constants/env_config.dart';
import '../../reading/data/reading_gloss.dart';
import '../../reading/data/reading_vocab_lists.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/domain/word_lookup_entry.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../domain/scene_word_label.dart';

/// Default cloud vision model for scene photo refine (DashScope compatible-mode).
const String kSceneVlModel = 'qwen-vl-plus';
const String kDashscopeCompatibleBase =
    'https://dashscope.aliyuncs.com/compatible-mode/v1';

final Provider<SceneWordRecognizer> sceneWordRecognizerProvider =
    Provider<SceneWordRecognizer>((Ref ref) {
      return SceneWordRecognizer(
        lookup: ref.read(wordLookupServiceProvider),
        api: ref.read(acquireApiClientProvider),
      );
    });

/// On-device image labeling + OCR, optionally refined by cloud Qwen-VL.
class SceneWordRecognizer {
  SceneWordRecognizer({
    required WordLookupService lookup,
    required AcquireApiClient api,
    OfflineWordDictionary? offline,
  }) : _lookup = lookup,
       _api = api,
       _offline = offline ?? OfflineWordDictionary();

  final WordLookupService _lookup;
  final AcquireApiClient _api;
  final OfflineWordDictionary _offline;

  static const Map<String, String> _commonZh = <String, String>{
    'watermelon': '西瓜',
    'apple': '苹果',
    'banana': '香蕉',
    'orange': '橙子',
    'grape': '葡萄',
    'strawberry': '草莓',
    'tomato': '番茄',
    'carrot': '胡萝卜',
    'bread': '面包',
    'milk': '牛奶',
    'coffee': '咖啡',
    'tea': '茶',
    'water': '水',
    'cup': '杯子',
    'bottle': '瓶子',
    'bag': '袋子',
    'hand': '手',
    'person': '人',
    'sneaker': '运动鞋',
    'shoe': '鞋',
    'phone': '手机',
    'laptop': '笔记本电脑',
    'book': '书',
    'pen': '笔',
    'table': '桌子',
    'chair': '椅子',
    'dog': '狗',
    'cat': '猫',
    'car': '汽车',
    'bus': '公交车',
    'tree': '树',
    'flower': '花',
    'food': '食物',
    'fruit': '水果',
    'vegetable': '蔬菜',
  };

  static final RegExp _wordRe = RegExp(r"^[A-Za-z][A-Za-z'-]{1,24}$");

  /// Fast on-device pass (ML Kit labels + Latin OCR).
  Future<List<SceneWordLabel>> recognize(
    String imagePath, {
    required LearningSettingsState settings,
    int limit = 8,
  }) async {
    final File file = File(imagePath);
    if (!file.existsSync()) {
      return const <SceneWordLabel>[];
    }
    final InputImage input = InputImage.fromFilePath(imagePath);
    final ImageLabeler labeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.48),
    );
    final TextRecognizer ocr = TextRecognizer();
    try {
      final List<ImageLabel> rawLabels = await labeler.processImage(input);
      final RecognizedText text = await ocr.processImage(input);
      final List<_Candidate> candidates = <_Candidate>[];
      for (final ImageLabel item in rawLabels) {
        final String word = _normalizeWord(item.label);
        if (word.isEmpty) continue;
        candidates.add(
          _Candidate(word: word, confidence: item.confidence, fromOcr: false),
        );
      }
      for (final TextBlock block in text.blocks) {
        for (final String token in block.text.split(RegExp(r'[^A-Za-z]+'))) {
          final String word = _normalizeWord(token);
          if (word.isEmpty || word.length < 3) continue;
          candidates.add(
            _Candidate(word: word, confidence: 0.55, fromOcr: true),
          ); // OCR tokens get a mid prior until VL refine.
        }
      }
      candidates.sort(
        (_Candidate a, _Candidate b) => b.confidence.compareTo(a.confidence),
      );
      final Set<String> seen = <String>{};
      final List<SceneWordLabel> out = <SceneWordLabel>[];
      for (final _Candidate item in candidates) {
        if (!seen.add(item.word)) continue;
        final SceneWordLabel enriched = await _enrich(
          word: item.word,
          confidence: item.confidence,
          index: out.length,
          settings: settings,
          source: 'local',
        );
        out.add(enriched);
        if (out.length >= limit) break;
      }
      return out;
    } finally {
      await labeler.close();
      await ocr.close();
    }
  }

  /// Cloud VL refine: Acquire API → direct DashScope `qwen-vl-plus` → user vision.
  Future<List<SceneWordLabel>> refineWithCloud(
    String imagePath, {
    required LearningSettingsState settings,
    List<SceneWordLabel> seed = const <SceneWordLabel>[],
    int limit = 8,
  }) async {
    final ({String base64, String mime}) encoded =
        await _encodeImageForUpload(imagePath);
    List<SceneWordLabel> cloud = const <SceneWordLabel>[];
    try {
      cloud = await _api.recognizeSceneWords(
        imageBase64: encoded.base64,
        mime: encoded.mime,
        seedLabels: seed,
        limit: limit,
      );
    } catch (_) {
      cloud = await _refineWithDashscopeQwenVl(
        imageBase64: encoded.base64,
        mime: encoded.mime,
        settings: settings,
        seed: seed,
        limit: limit,
      );
      if (cloud.isEmpty) {
        cloud = await _refineWithUserVision(
          imageBase64: encoded.base64,
          mime: encoded.mime,
          settings: settings,
          seed: seed,
          limit: limit,
        );
      }
    }
    if (cloud.isEmpty) {
      return seed;
    }
    final List<SceneWordLabel> out = <SceneWordLabel>[];
    for (int i = 0; i < cloud.length; i++) {
      final SceneWordLabel item = cloud[i];
      out.add(
        await _enrich(
          word: item.word,
          confidence: item.confidence,
          index: i,
          settings: settings,
          source: 'cloud',
          chineseHint: item.chinese,
          anchorX: item.anchorX,
          anchorY: item.anchorY,
        ),
      );
    }
    return out;
  }

  String _dashscopeVlApiKey(LearningSettingsState settings) {
    final String asr = settings.resolvedAsrApiKey.trim();
    if (asr.isNotEmpty) return asr;
    if (EnvConfig.hasBailianAsrApiKey) return EnvConfig.bailianAsrApiKey;
    final String translation = settings.translationApiKey.trim();
    final String provider = settings.translationProvider.trim();
    if (translation.isNotEmpty &&
        (provider.contains('百炼') ||
            provider.toLowerCase().contains('dashscope') ||
            settings.translationBaseUrl.contains('dashscope'))) {
      return translation;
    }
    return '';
  }

  Future<List<SceneWordLabel>> _refineWithDashscopeQwenVl({
    required String imageBase64,
    required String mime,
    required LearningSettingsState settings,
    required List<SceneWordLabel> seed,
    required int limit,
  }) async {
    final String apiKey = _dashscopeVlApiKey(settings);
    if (apiKey.isEmpty) return const <SceneWordLabel>[];
    try {
      return await _postVisionChat(
        baseUrl: kDashscopeCompatibleBase,
        apiKey: apiKey,
        model: kSceneVlModel,
        imageBase64: imageBase64,
        mime: mime,
        seed: seed,
        limit: limit,
      );
    } catch (_) {
      return const <SceneWordLabel>[];
    }
  }

  Future<List<SceneWordLabel>> _refineWithUserVision({
    required String imageBase64,
    required String mime,
    required LearningSettingsState settings,
    required List<SceneWordLabel> seed,
    required int limit,
  }) async {
    if (!_canUseUserVision(settings)) {
      return const <SceneWordLabel>[];
    }
    final String model = settings.translationModel.trim();
    final String base = settings.translationBaseUrl.trim().replaceAll(
      RegExp(r'/+$'),
      '',
    );
    // Bailian users often set ASR base without compatible-mode; normalize.
    final String chatBase = base.contains('dashscope.aliyuncs.com') &&
            !base.contains('compatible-mode')
        ? kDashscopeCompatibleBase
        : base;
    try {
      return await _postVisionChat(
        baseUrl: chatBase,
        apiKey: settings.translationApiKey.trim().isEmpty
            ? 'ollama'
            : settings.translationApiKey.trim(),
        model: model.toLowerCase().contains('qwen-vl') ? model : kSceneVlModel,
        imageBase64: imageBase64,
        mime: mime,
        seed: seed,
        limit: limit,
      );
    } catch (_) {
      return const <SceneWordLabel>[];
    }
  }

  Future<List<SceneWordLabel>> _postVisionChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String imageBase64,
    required String mime,
    required List<SceneWordLabel> seed,
    required int limit,
  }) async {
    final String seedBrief = seed
        .take(8)
        .map((SceneWordLabel s) => '${s.word}:${s.chinese}')
        .join(', ');
    final Map<String, dynamic> body = <String, dynamic>{
      'model': model,
      'temperature': 0.1,
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'system',
          'content':
              'Label photo objects for English learners. Return ONLY a JSON array: '
              '[{"word":"apple","chinese":"苹果","confidence":0.9,"anchor_x":0.4,"anchor_y":0.5}]. '
              'Concrete nouns only; max $limit items.',
        },
        <String, dynamic>{
          'role': 'user',
          'content': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'image_url',
              'image_url': <String, String>{
                'url': 'data:$mime;base64,$imageBase64',
              },
            },
            <String, dynamic>{
              'type': 'text',
              'text':
                  'Refine seed labels and add clear missing objects. seed=[$seedBrief]',
            },
          ],
        },
      ],
    };
    final Response<dynamic> response = await Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: <String, String>{
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
      ),
    ).post<dynamic>('/chat/completions', data: body);
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    final List<dynamic> choices =
        (data['choices'] as List<dynamic>?) ?? const <dynamic>[];
    if (choices.isEmpty) return const <SceneWordLabel>[];
    final Map<String, dynamic> message =
        (choices.first as Map<String, dynamic>)['message']
            as Map<String, dynamic>;
    final Object? content = message['content'];
    final String text = content is String
        ? content
        : (content is List
            ? content
                .whereType<Map>()
                .map((Map row) => '${row['text'] ?? ''}')
                .join('\n')
            : '');
    return _parseCloudJson(text);
  }

  bool _canUseUserVision(LearningSettingsState settings) {
    final String provider = settings.translationProvider.trim();
    if (provider == 'Google 翻译' ||
        provider == '百度翻译' ||
        provider == '阿里云翻译') {
      return false;
    }
    final String model = settings.translationModel.trim().toLowerCase();
    if (model.isEmpty) return false;
    return model.contains('gpt-4o') ||
        model.contains('gpt-4.1') ||
        model.contains('gpt-5') ||
        model.contains('vision') ||
        model.contains('-vl') ||
        model.contains('qwen-vl') ||
        model.contains('qwen2.5-vl') ||
        model.contains('gemini') ||
        model.contains('claude-3') ||
        model.contains('claude-4');
  }

  List<SceneWordLabel> _parseCloudJson(String raw) {
    String text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    Object? parsed;
    try {
      parsed = jsonDecode(text);
    } catch (_) {
      final Match? match = RegExp(r'\[[\s\S]*\]').firstMatch(text);
      if (match == null) return const <SceneWordLabel>[];
      try {
        parsed = jsonDecode(match.group(0)!);
      } catch (_) {
        return const <SceneWordLabel>[];
      }
    }
    if (parsed is! List) return const <SceneWordLabel>[];
    final List<SceneWordLabel> out = <SceneWordLabel>[];
    final Set<String> seen = <String>{};
    for (final Object? row in parsed) {
      if (row is! Map) continue;
      final Map<String, dynamic> map = Map<String, dynamic>.from(row);
      final SceneWordLabel label = SceneWordLabel.fromJson(map).copyWith(
        source: 'cloud',
      );
      if (label.word.length < 2 || !seen.add(label.word)) continue;
      out.add(label);
      if (out.length >= 8) break;
    }
    return out;
  }

  Future<({String base64, String mime})> _encodeImageForUpload(
    String imagePath,
  ) async {
    final File file = File(imagePath);
    final Uint8List bytes = await file.readAsBytes();
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return (base64: base64Encode(bytes), mime: 'image/jpeg');
    }
    const int maxEdge = 1280;
    if (decoded.width > maxEdge || decoded.height > maxEdge) {
      final double scale = maxEdge /
          math.max(decoded.width, decoded.height).toDouble();
      decoded = img.copyResize(
        decoded,
        width: (decoded.width * scale).round().clamp(1, maxEdge),
        height: (decoded.height * scale).round().clamp(1, maxEdge),
      );
    }
    final Uint8List jpeg = Uint8List.fromList(
      img.encodeJpg(decoded, quality: 72),
    );
    return (base64: base64Encode(jpeg), mime: 'image/jpeg');
  }

  Future<SceneWordLabel> _enrich({
    required String word,
    required double confidence,
    required int index,
    required LearningSettingsState settings,
    required String source,
    String chineseHint = '',
    double? anchorX,
    double? anchorY,
  }) async {
    String phonetic = '';
    String chinese = chineseHint.trim().isNotEmpty
        ? chineseHint.trim()
        : (_commonZh[word] ?? '');
    try {
      final OfflineWordDefinition? offline = await _offline.lookup(word);
      if (offline != null) {
        if (phonetic.isEmpty) phonetic = offline.phonetic.trim();
        if (chinese.isEmpty) chinese = offline.translation.trim();
      }
    } catch (_) {}
    try {
      final WordLookupEntry entry = await _lookup.lookupWord(
        rawWord: word,
        settings: settings,
      );
      if (phonetic.isEmpty) phonetic = entry.phonetic.trim();
      if (chinese.isEmpty) {
        chinese = (entry.contextMeaningCn ?? entry.definitionCn).trim();
        if (chinese.contains('；')) {
          chinese = chinese.split('；').first.trim();
        }
        if (chinese.contains(';')) {
          chinese = chinese.split(';').first.trim();
        }
        if (chinese.length > 12) {
          chinese = chinese.substring(0, 12);
        }
      }
    } catch (_) {}
    final double ax = anchorX ?? (0.28 + (index % 3) * 0.22);
    final double ay = anchorY ?? (0.32 + (index ~/ 3) * 0.22);
    return SceneWordLabel(
      word: word,
      phonetic: phonetic.isEmpty
          ? ''
          : (phonetic.startsWith('/') ? phonetic : '/$phonetic/'),
      chinese: chinese,
      confidence: confidence,
      anchorX: ax.clamp(0.12, 0.88),
      anchorY: ay.clamp(0.18, 0.78),
      source: source,
    );
  }

  String _normalizeWord(String raw) {
    final String text = raw.trim().toLowerCase().replaceAll('’', "'");
    if (!_wordRe.hasMatch(text) && !text.contains(' ')) {
      return '';
    }
    const Set<String> skip = <String>{
      'dish',
      'cuisine',
      'ingredient',
      'produce',
      'plant',
      'organism',
      'natural foods',
      'local food',
      'finger food',
      'superfood',
      'product',
      'object',
      'thing',
      'food',
      'fruit',
      'vegetable',
    };
    if (skip.contains(text)) return '';
    if (text.contains(' ')) {
      final List<String> parts = text
          .split(RegExp(r'\s+'))
          .where((String p) => _wordRe.hasMatch(p) && p.length >= 3)
          .toList(growable: false);
      if (parts.isEmpty) return '';
      return parts.last;
    }
    if (!_wordRe.hasMatch(text)) return '';
    return text;
  }

  /// Drop words the learner already knows: high frequency (≤ threshold) or
  /// marked known / mastered. Focus-list words always keep.
  static List<SceneWordLabel> keepLearningTargets(
    List<SceneWordLabel> labels, {
    required ReadingFrequencyLexicon lexicon,
    required int freqThreshold,
    required Set<String> knownWords,
    Set<String> focusWords = const <String>{},
  }) {
    final List<SceneWordLabel> out = <SceneWordLabel>[];
    final Set<String> seen = <String>{};
    for (final SceneWordLabel label in labels) {
      final String word = label.word.trim().toLowerCase();
      if (word.length < 2 || !seen.add(word)) continue;
      if (!isReadingHardWord(
        word: word,
        lexicon: lexicon,
        threshold: freqThreshold,
        known: knownWords,
        focus: focusWords,
      )) {
        continue;
      }
      out.add(label);
    }
    return out;
  }

  String buildSceneDescription(List<SceneWordLabel> labels) {
    if (labels.isEmpty) {
      return 'The learner shared a real-world photo, but no clear objects were labeled.';
    }
    final String nouns = labels
        .take(6)
        .map((SceneWordLabel item) {
          if (item.chinese.isEmpty) return item.word;
          return '${item.word} (${item.chinese})';
        })
        .join(', ');
    final bool cloud = labels.any((SceneWordLabel l) => l.source == 'cloud');
    final String quality = cloud
        ? 'Cloud vision refined these nouns'
        : 'On-device labels suggest these nouns';
    return 'The learner is showing a live real-world scene. $quality: $nouns. '
        'Talk about what you see, teach useful words, and ask the learner to describe the scene in English.';
  }
}

class _Candidate {
  const _Candidate({
    required this.word,
    required this.confidence,
    required this.fromOcr,
  });

  final String word;
  final double confidence;
  final bool fromOcr;
}
