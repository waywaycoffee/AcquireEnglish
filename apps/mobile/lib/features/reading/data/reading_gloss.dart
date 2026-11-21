import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../words/data/offline_word_dictionary.dart';

/// Words at or below this SUBTLEX-style frequency rank stay unglossed.
const int kReadingHardWordRankThreshold = 3000;

const String kEnglishFreqTop3000Asset =
    'assets/dictionary/english_freq_top3000.txt';

final FutureProvider<ReadingFrequencyLexicon> readingFrequencyLexiconProvider =
    FutureProvider<ReadingFrequencyLexicon>((Ref ref) async {
      return ReadingFrequencyLexicon.load();
    });

/// Offline top-N frequency set (Hermit Dave FrequencyWords, top 3000).
class ReadingFrequencyLexicon {
  ReadingFrequencyLexicon(this._top);

  final Set<String> _top;

  static Future<ReadingFrequencyLexicon> load() async {
    try {
      final String raw = await rootBundle.loadString(kEnglishFreqTop3000Asset);
      final Set<String> top = <String>{
        for (final String line in raw.split('\n'))
          if (line.trim().isNotEmpty) line.trim().toLowerCase(),
      };
      return ReadingFrequencyLexicon(top);
    } catch (_) {
      return ReadingFrequencyLexicon(const <String>{});
    }
  }

  bool isCommon(String word) {
    final String key = word.trim().toLowerCase().replaceAll('’', "'");
    if (key.isEmpty) return true;
    return _top.contains(key);
  }

  /// True when the word should get an inline Chinese gloss.
  bool isHard(String word) => !isCommon(word);
}

/// First short Chinese sense suitable for ruby-style inline gloss.
String shortReadingGloss(String rawTranslation) {
  String text = rawTranslation.trim();
  if (text.isEmpty) return '';
  text = text.replaceAll(r'\n', '\n');
  text = text.split('\n').first.trim();
  // Drop leading POS tags: "n. ", "vt. ", "a. ", "prep. "
  text = text.replaceFirst(RegExp(r'^[a-z]+\.\s*', caseSensitive: false), '');
  text = text.replaceFirst(RegExp(r'^\[.*?\]\s*'), '');
  // Keep first sense / synonym only.
  text = text.split(RegExp(r'[,，;；/、]')).first.trim();
  if (text.length > 10) {
    text = '${text.substring(0, 10)}…';
  }
  return text;
}

Future<Map<String, String>> buildHardWordGlosses({
  required Iterable<String> words,
  required ReadingFrequencyLexicon lexicon,
  required OfflineWordDictionary dictionary,
}) async {
  final Map<String, String> out = <String, String>{};
  final Set<String> seen = <String>{};
  for (final String raw in words) {
    final String word = raw.trim().toLowerCase().replaceAll('’', "'");
    if (word.length < 2 || !seen.add(word)) continue;
    if (!lexicon.isHard(word)) continue;
    final OfflineWordDefinition? def = await dictionary.lookup(word);
    final String gloss = shortReadingGloss(def?.translation ?? '');
    if (gloss.isEmpty) continue;
    out[word] = gloss;
  }
  return out;
}

Set<String> extractReadingWords(String text) {
  final Set<String> out = <String>{};
  for (final RegExpMatch m in RegExp(
    r"[A-Za-z]+(?:['’-][A-Za-z]+)*",
  ).allMatches(text)) {
    final String w = m.group(0)!.toLowerCase().replaceAll('’', "'");
    if (w.length >= 2) out.add(w);
  }
  return out;
}
