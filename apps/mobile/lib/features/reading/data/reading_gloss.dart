import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../words/data/offline_word_dictionary.dart';
import '../domain/reading_study_mode.dart';

const String kEnglishFreqTop20000Asset =
    'assets/dictionary/english_freq_top20000.txt';

/// Kept for backward compatibility with older call sites / docs.
const int kReadingHardWordRankThreshold = kReadingDefaultFreqThreshold;

final FutureProvider<ReadingFrequencyLexicon> readingFrequencyLexiconProvider =
    FutureProvider<ReadingFrequencyLexicon>((Ref ref) async {
      return ReadingFrequencyLexicon.load();
    });

/// Offline ranked frequency list (Hermit Dave FrequencyWords, top 20k).
/// Rank 1 = most common.
class ReadingFrequencyLexicon {
  ReadingFrequencyLexicon(this._rankByWord);

  final Map<String, int> _rankByWord;

  /// Lemmas at or under the classic top-3000 cutoff (CEFR / video coverage).
  Set<String> get topWords {
    return <String>{
      for (final MapEntry<String, int> e in _rankByWord.entries)
        if (e.value <= 3000) e.key,
    };
  }

  static Future<ReadingFrequencyLexicon> load() async {
    try {
      final String raw = await rootBundle.loadString(kEnglishFreqTop20000Asset);
      final Map<String, int> map = <String, int>{};
      int rank = 0;
      for (final String line in raw.split('\n')) {
        final String w = line.trim().toLowerCase();
        if (w.isEmpty) continue;
        rank += 1;
        map.putIfAbsent(w, () => rank);
      }
      return ReadingFrequencyLexicon(map);
    } catch (_) {
      return ReadingFrequencyLexicon(const <String, int>{});
    }
  }

  int get size => _rankByWord.length;

  /// 1-based rank, or null if outside the offline list.
  int? rankOf(String word) {
    final String key = word.trim().toLowerCase().replaceAll('’', "'");
    if (key.isEmpty) return null;
    return _rankByWord[key];
  }

  bool isCommon(String word, {required int threshold}) {
    final int? rank = rankOf(word);
    if (rank == null) return false;
    return rank <= threshold;
  }

  /// True when the word should get an inline Chinese gloss.
  bool isHard(String word, {required int threshold}) =>
      !isCommon(word, threshold: threshold);
}

/// First short Chinese sense suitable for ruby-style inline gloss.
String shortReadingGloss(String rawTranslation) {
  String text = rawTranslation.trim();
  if (text.isEmpty) return '';
  text = text.replaceAll(r'\n', '\n');
  text = text.split('\n').first.trim();
  text = text.replaceFirst(RegExp(r'^[a-z]+\.\s*', caseSensitive: false), '');
  text = text.replaceFirst(RegExp(r'^\[.*?\]\s*'), '');
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
  int threshold = kReadingDefaultFreqThreshold,
  Set<String> known = const <String>{},
  Set<String> focus = const <String>{},
}) async {
  await dictionary.ensureLoaded();
  final Map<String, String> out = <String, String>{};
  final Set<String> seen = <String>{};
  int yielded = 0;
  for (final String raw in words) {
    final String word = raw.trim().toLowerCase().replaceAll('’', "'");
    if (word.length < 2 || !seen.add(word)) continue;
    if (!_isHardWithLists(
      word: word,
      lexicon: lexicon,
      threshold: threshold,
      known: known,
      focus: focus,
    )) {
      continue;
    }
    final OfflineWordDefinition? def = dictionary.lookupSync(word);
    final String gloss = shortReadingGloss(def?.translation ?? '');
    if (gloss.isEmpty) continue;
    out[word] = gloss;
    // Keep the UI responsive while annotating a long page.
    yielded += 1;
    if (yielded % 40 == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return out;
}

bool _isHardWithLists({
  required String word,
  required ReadingFrequencyLexicon lexicon,
  required int threshold,
  required Set<String> known,
  required Set<String> focus,
}) {
  if (known.contains(word)) return false;
  if (focus.contains(word)) return true;
  return lexicon.isHard(word, threshold: threshold);
}

/// Share of tokens whose frequency rank is above [threshold] (or unknown).
/// Optional [known]/[focus] lists override frequency (whitelist / blacklist).
double unknownWordRate({
  required Iterable<String> words,
  required ReadingFrequencyLexicon lexicon,
  required int threshold,
  Set<String> known = const <String>{},
  Set<String> focus = const <String>{},
}) {
  int total = 0;
  int hard = 0;
  for (final String raw in words) {
    final String word = raw.trim().toLowerCase().replaceAll('’', "'");
    if (word.length < 2) continue;
    total += 1;
    if (_isHardWithLists(
      word: word,
      lexicon: lexicon,
      threshold: threshold,
      known: known,
      focus: focus,
    )) {
      hard += 1;
    }
  }
  if (total == 0) return 0;
  return hard / total;
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

List<String> extractReadingWordTokens(String text) {
  final List<String> out = <String>[];
  for (final RegExpMatch m in RegExp(
    r"[A-Za-z]+(?:['’-][A-Za-z]+)*",
  ).allMatches(text)) {
    final String w = m.group(0)!.toLowerCase().replaceAll('’', "'");
    if (w.length >= 2) out.add(w);
  }
  return out;
}
