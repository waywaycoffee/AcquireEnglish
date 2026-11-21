import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/domain/word_lookup_entry.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../domain/scene_word_label.dart';

final Provider<SceneWordRecognizer> sceneWordRecognizerProvider =
    Provider<SceneWordRecognizer>((Ref ref) {
      return SceneWordRecognizer(
        lookup: ref.read(wordLookupServiceProvider),
      );
    });

/// On-device image labeling + OCR, enriched with IPA/Chinese for coach chips.
class SceneWordRecognizer {
  SceneWordRecognizer({
    required WordLookupService lookup,
    OfflineWordDictionary? offline,
  }) : _lookup = lookup,
       _offline = offline ?? OfflineWordDictionary();

  final WordLookupService _lookup;
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
      options: ImageLabelerOptions(confidenceThreshold: 0.45),
    );
    final TextRecognizer ocr = TextRecognizer(
      script: TextRecognitionScript.latin,
    );
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
          );
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

  Future<SceneWordLabel> _enrich({
    required String word,
    required double confidence,
    required int index,
    required LearningSettingsState settings,
  }) async {
    String phonetic = '';
    String chinese = _commonZh[word] ?? '';
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
    // Spread chips so they don't fully overlap.
    final double ax = 0.28 + (index % 3) * 0.22;
    final double ay = 0.32 + (index ~/ 3) * 0.22;
    return SceneWordLabel(
      word: word,
      phonetic: phonetic.isEmpty
          ? ''
          : (phonetic.startsWith('/') ? phonetic : '/$phonetic/'),
      chinese: chinese,
      confidence: confidence,
      anchorX: ax.clamp(0.12, 0.88),
      anchorY: ay.clamp(0.18, 0.78),
    );
  }

  String _normalizeWord(String raw) {
    final String text = raw.trim().toLowerCase().replaceAll('’', "'");
    if (!_wordRe.hasMatch(text)) return '';
    // Drop overly generic ML labels.
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
    };
    if (skip.contains(text)) return '';
    if (text.contains(' ')) {
      // Prefer single-token concrete nouns for the wordbook.
      final List<String> parts = text
          .split(RegExp(r'\s+'))
          .where((String p) => _wordRe.hasMatch(p) && p.length >= 3)
          .toList(growable: false);
      if (parts.isEmpty) return '';
      return parts.last;
    }
    return text;
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
    return 'The learner is showing a live real-world scene that likely includes: $nouns. '
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
