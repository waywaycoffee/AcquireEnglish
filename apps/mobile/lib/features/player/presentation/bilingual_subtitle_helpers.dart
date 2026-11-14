import 'player_mock_state.dart';
import 'subtitle_language_sanitize.dart';
import 'subtitle_word_alignment.dart';

enum MissingSubtitleSide { none, english, chinese, both }

/// True when subtitle cues run meaningfully past the media duration.
///
/// Catches 合集/缓存串台 where a longer unrelated SRT was saved under the
/// current BV folder (path fingerprint still matches).
bool subtitleTimelineExceedsMedia({
  required int subtitleEndMs,
  required int mediaDurationMs,
  int slackMs = 60000,
}) {
  if (mediaDurationMs <= 0 || subtitleEndMs <= 0) {
    return false;
  }
  return subtitleEndMs > mediaDurationMs + slackMs;
}

int subtitleLinesEndMs(Iterable<PlayerSubtitleLine> lines) {
  int endMs = 0;
  for (final PlayerSubtitleLine line in lines) {
    if (line.endMs > endMs) {
      endMs = line.endMs;
    }
  }
  return endMs;
}

enum BilingualPipelinePhase {
  idle,
  ocrRunning,
  ocrSlow,
  translating,
  asrProofreading,
  completed,
  cancelled,
}

class OcrCueText {
  const OcrCueText({this.english = '', this.chinese = ''});

  final String english;
  final String chinese;

  bool get isEmpty => english.trim().isEmpty && chinese.trim().isEmpty;

  OcrCueText merge(OcrCueText other) {
    return OcrCueText(
      english: english.trim().isNotEmpty ? english : other.english,
      chinese: chinese.trim().isNotEmpty ? chinese : other.chinese,
    );
  }
}

final RegExp _latinWord = RegExp(r"[A-Za-z]{2,}");
final RegExp _latinToken = RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)?");
final RegExp _chineseChar = RegExp(r'[\u4e00-\u9fff]');

/// Frequent hardsub words used to re-split OCR glue like `andright` / `haveleafs`.
/// Longest-first matching; keep this list lowercase.
const List<String> _ocrEnglishLexicon = <String>[
  'something',
  'everything',
  'anything',
  'somewhere',
  'everyone',
  'together',
  'because',
  'through',
  'without',
  'another',
  'around',
  'before',
  'between',
  'against',
  'already',
  'always',
  'almost',
  'across',
  'after',
  'about',
  'people',
  'person',
  'really',
  'should',
  'would',
  'could',
  'there',
  'their',
  'these',
  'those',
  'where',
  'which',
  'while',
  'other',
  'right',
  'night',
  'light',
  'water',
  'house',
  'trees',
  'leaves',
  'leafs',
  'going',
  'doing',
  'being',
  'having',
  'looking',
  'thinking',
  'talking',
  'walking',
  'little',
  'great',
  'first',
  'still',
  'never',
  'again',
  'under',
  'over',
  'into',
  'onto',
  'from',
  'with',
  'this',
  'that',
  'they',
  'them',
  'then',
  'than',
  'when',
  'what',
  'will',
  'were',
  'been',
  'have',
  'has',
  'had',
  'been',
  'just',
  'like',
  'some',
  'more',
  'most',
  'much',
  'many',
  'very',
  'also',
  'am',
  'any',
  'cut',
  'tree',
  'wood',
  'down',
  'branch',
  'branches',
  'only',
  'even',
  'here',
  'back',
  'down',
  'come',
  'came',
  'know',
  'knew',
  'think',
  'want',
  'need',
  'make',
  'made',
  'take',
  'took',
  'give',
  'gave',
  'look',
  'good',
  'well',
  'time',
  'year',
  'gate',
  'tree',
  'leaf',
  'now',
  'and',
  'the',
  'for',
  'are',
  'but',
  'not',
  'you',
  'all',
  'can',
  'her',
  'was',
  'one',
  'our',
  'out',
  'day',
  'get',
  'has',
  'him',
  'his',
  'how',
  'man',
  'new',
  'old',
  'see',
  'two',
  'way',
  'who',
  'boy',
  'did',
  'its',
  'let',
  'put',
  'say',
  'she',
  'too',
  'use',
  'dad',
  'mom',
  'yes',
  'off',
  'a',
  'i',
  'an',
  'as',
  'at',
  'be',
  'by',
  'do',
  'go',
  'if',
  'in',
  'is',
  'it',
  'me',
  'my',
  'no',
  'of',
  'on',
  'or',
  'so',
  'to',
  'up',
  'us',
  'we',
];

final Set<String> _ocrEnglishLexiconSet = _ocrEnglishLexicon.toSet();

bool looksEnglish(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return false;
  }
  final int latin = _latinWord.allMatches(text).length;
  final int chinese = _chineseChar.allMatches(text).length;
  return latin > 0 && latin >= chinese;
}

/// True when OCR likely dropped spaces (`agate`, `andright`, `haveleafs`).
///
/// A normal sentence with short words is not glued. Glued means a token
/// splits into two known words, or a long spaceless blob.
bool ocrEnglishLooksGlued(String raw) {
  final String text = raw.trim();
  if (text.isEmpty || !looksEnglish(text)) {
    return false;
  }
  final List<RegExpMatch> tokens = _latinToken.allMatches(text).toList();
  if (tokens.isEmpty) {
    return false;
  }
  int letters = 0;
  for (final RegExpMatch match in tokens) {
    final String token = match.group(0) ?? '';
    letters += token.length;
    final String lower = token.toLowerCase();
    if (token.length < 4 || _ocrEnglishLexiconSet.contains(lower)) {
      continue;
    }
    final List<String>? parts = _segmentEnglishWord(lower);
    if (parts != null && parts.length >= 2) {
      return true;
    }
  }
  final int spaces = RegExp(r'\s').allMatches(text).length;
  if (letters >= 8 && spaces == 0) {
    final String lower = (tokens.first.group(0) ?? '').toLowerCase();
    return !_ocrEnglishLexiconSet.contains(lower);
  }
  return false;
}

/// OCR English safe enough to show or to replace a translation.
///
/// Rejects glued tokens (`andright`) and short nonsense (`Uam`).
bool isReliableOcrEnglish(String raw) {
  final String text = repairOcrEnglishSpacing(raw).trim();
  if (!looksEnglish(text) || ocrEnglishLooksGlued(text)) {
    return false;
  }
  for (final Match match in _latinToken.allMatches(text)) {
    final String token = (match.group(0) ?? '').toLowerCase();
    if (token.length <= 3 && !_ocrEnglishLexiconSet.contains(token)) {
      return false;
    }
  }
  return true;
}

const Set<String> _functionWords = <String>{
  'a',
  'an',
  'the',
  'to',
  'of',
  'and',
  'is',
  'am',
  'i',
  'it',
  'in',
  'on',
  'for',
  'you',
  'we',
  'he',
  'she',
  'be',
  'do',
  'my',
  'me',
  'so',
  'or',
  'as',
  'at',
  'by',
  'if',
  'up',
  'us',
  'not',
  'did',
  'any',
  'was',
  'are',
  'but',
  'his',
  'her',
  'its',
  'our',
  'out',
};

/// Hardsub English safe to write over a translation.
///
/// Real on-screen lines pass. A short unknown token (`Iarn`, `Uam`) does not.
bool isVideoFaithfulEnglish(String raw) {
  if (!isReliableOcrEnglish(raw)) {
    return false;
  }
  final String text = repairOcrEnglishSpacing(raw);
  for (final Match match in _latinToken.allMatches(text)) {
    final String token = (match.group(0) ?? '').toLowerCase();
    if (_ocrEnglishLexiconSet.contains(token)) {
      continue;
    }
    if (token.length <= 4) {
      return false;
    }
  }
  return true;
}

Set<String> _contentWords(String raw) {
  return _latinToken
      .allMatches(raw.toLowerCase())
      .map((Match match) => match.group(0) ?? '')
      .where(
        (String token) => token.length > 1 && !_functionWords.contains(token),
      )
      .toSet();
}

int _englishWordCount(String raw) {
  return raw.trim().isEmpty ? 0 : raw.trim().split(RegExp(r'\s+')).length;
}

bool _sameEnglishText(String a, String b) {
  final String left = a.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final String right = b.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return left.isNotEmpty && left == right;
}

/// [video] is a clipped piece of [full], not a different sentence.
bool _isShorterFragment(String video, String full) {
  if (_englishWordCount(video) + 3 >= _englishWordCount(full)) {
    return false;
  }
  final Set<String> videoWords = _contentWords(video);
  final Set<String> fullWords = _contentWords(full);
  if (videoWords.isEmpty) {
    return false;
  }
  return videoWords.every(fullWords.contains);
}

bool _sentencesAgree(String a, String b) {
  final Set<String> left = _contentWords(a);
  final Set<String> right = _contentWords(b);
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  final int overlap = left.intersection(right).length;
  final int smaller = left.length < right.length ? left.length : right.length;
  return overlap >= 2 && overlap / smaller >= 0.5;
}

/// Whether [ocr] should replace an existing English line.
///
/// Same-sentence wording stays. Only a real hardsub that says something else
/// counts as a major error. Junk OCR never wins.
bool shouldPreferOcrProof(String current, String ocr) {
  if (!isVideoFaithfulEnglish(ocr)) {
    return false;
  }
  if (!looksEnglish(current) || looksChinese(current)) {
    return true;
  }
  if (_sameEnglishText(current, ocr)) {
    return false;
  }
  if (_englishWordCount(ocr) < 4 || _isShorterFragment(ocr, current)) {
    return false;
  }
  if (_sentencesAgree(current, ocr)) {
    return false;
  }
  return true;
}

/// Spoken ASR is the video's English. Prefer it over a Chinese→English
/// paraphrase whenever the wording differs, unless ASR is only a clipped
/// fragment of the current line.
bool shouldPreferAsrProof(String current, String asr) {
  final String spoken = asr.trim();
  if (!looksEnglish(spoken) || looksChinese(spoken)) {
    return false;
  }
  if (!looksEnglish(current) ||
      looksChinese(current) ||
      ocrEnglishLooksGlued(current)) {
    return true;
  }
  if (_sameEnglishText(current, spoken)) {
    return false;
  }
  if (_isShorterFragment(spoken, current)) {
    return false;
  }
  return true;
}

/// Keep lines the learner edited by hand. Later OCR/ASR passes must not
/// overwrite that English.
List<PlayerSubtitleLine> keepManualEnglish({
  required List<PlayerSubtitleLine> lines,
  required Map<int, String> manualEnglishByStartMs,
}) {
  if (manualEnglishByStartMs.isEmpty) {
    return lines;
  }
  return <PlayerSubtitleLine>[
    for (final PlayerSubtitleLine line in lines)
      if ((manualEnglishByStartMs[line.startMs] ?? '').trim().isEmpty)
        line
      else
        PlayerSubtitleLine(
          startTime: line.startTime,
          english: manualEnglishByStartMs[line.startMs]!.trim(),
          chinese: line.chinese,
          startMs: line.startMs,
          endMs: line.endMs,
          words: line.words,
        ),
  ];
}

/// Keep Chinese the learner edited by hand across later auto fills.
List<PlayerSubtitleLine> keepManualChinese({
  required List<PlayerSubtitleLine> lines,
  required Map<int, String> manualChineseByStartMs,
}) {
  if (manualChineseByStartMs.isEmpty) {
    return lines;
  }
  return <PlayerSubtitleLine>[
    for (final PlayerSubtitleLine line in lines)
      if ((manualChineseByStartMs[line.startMs] ?? '').trim().isEmpty)
        line
      else
        PlayerSubtitleLine(
          startTime: line.startTime,
          english: line.english,
          chinese: manualChineseByStartMs[line.startMs]!.trim(),
          startMs: line.startMs,
          endMs: line.endMs,
          words: line.words,
        ),
  ];
}

/// Repair missing spaces in OCR English (punctuation + glued common words).
String repairOcrEnglishSpacing(String raw) {
  String text = raw.trim();
  if (text.isEmpty) {
    return text;
  }
  // "gate,and" / "now.Then" → restore punctuation gaps.
  text = text.replaceAllMapped(
    RegExp(r'([,.;:!?])([A-Za-z])'),
    (Match m) => '${m.group(1)} ${m.group(2)}',
  );
  // camelCase leftovers from OCR: "andRight" → "and Right"
  text = text.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (Match m) => '${m.group(1)} ${m.group(2)}',
  );
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final StringBuffer out = StringBuffer();
  int cursor = 0;
  while (cursor < text.length) {
    final Match? match = _latinToken.matchAsPrefix(text, cursor);
    if (match == null) {
      out.write(text[cursor]);
      cursor += 1;
      continue;
    }
    final String token = match.group(0)!;
    out.write(_segmentGluedEnglishToken(token));
    cursor = match.end;
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _segmentGluedEnglishToken(String token) {
  if (token.length < 4) {
    return token;
  }
  final String lower = token.toLowerCase();
  if (_ocrEnglishLexiconSet.contains(lower)) {
    return token;
  }
  final List<String>? parts = _segmentEnglishWord(lower);
  if (parts == null || parts.length < 2) {
    return token;
  }
  // Preserve original capitalization on the first piece only.
  final StringBuffer rebuilt = StringBuffer();
  int offset = 0;
  for (int i = 0; i < parts.length; i++) {
    final String part = parts[i];
    final String slice = token.substring(offset, offset + part.length);
    if (i > 0) {
      rebuilt.write(' ');
    }
    rebuilt.write(slice);
    offset += part.length;
  }
  return rebuilt.toString();
}

List<String>? _segmentEnglishWord(String lower) {
  if (lower.isEmpty) {
    return const <String>[];
  }
  if (_ocrEnglishLexiconSet.contains(lower)) {
    return <String>[lower];
  }
  final int maxLen = lower.length < 12 ? lower.length : 12;
  for (int len = maxLen; len >= 1; len--) {
    if (len >= lower.length) {
      continue;
    }
    final String head = lower.substring(0, len);
    if (!_ocrEnglishLexiconSet.contains(head)) {
      continue;
    }
    // Prefer multi-letter heads; allow "a"/"i" only when remainder also segments.
    if (len == 1 && head != 'a' && head != 'i') {
      continue;
    }
    final List<String>? tail = _segmentEnglishWord(lower.substring(len));
    if (tail == null) {
      continue;
    }
    if (tail.isEmpty) {
      continue;
    }
    return <String>[head, ...tail];
  }
  return null;
}

bool looksChinese(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return false;
  }
  return _chineseChar.hasMatch(text);
}

/// Split OCR block lines into EN / ZH buckets.
OcrCueText splitOcrTextBlocks(List<String> blocks) {
  final StringBuffer english = StringBuffer();
  final StringBuffer chinese = StringBuffer();
  void appendEnglish(String value) {
    if (value.isEmpty) {
      return;
    }
    if (english.isNotEmpty) {
      english.write(' ');
    }
    english.write(value);
  }

  void appendChinese(String value) {
    if (value.isEmpty) {
      return;
    }
    if (chinese.isNotEmpty) {
      chinese.write(' ');
    }
    chinese.write(value);
  }

  for (final String raw in blocks) {
    final String line = raw.trim();
    if (line.isEmpty) {
      continue;
    }
    final bool hasLatin = _latinWord.hasMatch(line);
    final bool hasChinese = _chineseChar.hasMatch(line);
    if (hasLatin && hasChinese) {
      // Mixed line: keep Latin as EN, CJK as ZH when possible.
      final String enPart = repairOcrEnglishSpacing(
        line
            .replaceAll(_chineseChar, ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
      );
      final String zhPart = line
          .replaceAll(_latinWord, ' ')
          .replaceAll(RegExp(r"[A-Za-z0-9’'\-]+"), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      appendEnglish(enPart);
      appendChinese(zhPart);
    } else if (hasLatin) {
      appendEnglish(repairOcrEnglishSpacing(line));
    } else if (hasChinese) {
      appendChinese(line);
    }
  }
  return OcrCueText(english: english.toString(), chinese: chinese.toString());
}

/// Whether working English disagrees with overlapping ASR cues often enough
/// that the Chinese/ZH→EN timeline should be discarded.
bool workingEnglishMismatchesAsr({
  required List<PlayerSubtitleLine> working,
  required List<PlayerSubtitleLine> asrLines,
  double disagreeRatio = 0.4,
}) {
  if (asrLines.isEmpty) {
    return false;
  }
  if (working.isEmpty) {
    return true;
  }
  int compared = 0;
  int disagree = 0;
  for (final PlayerSubtitleLine line in working) {
    if (!looksEnglish(line.english) || looksChinese(line.english)) {
      continue;
    }
    final PlayerSubtitleLine? asr = _bestOverlappingLine(asrLines, line);
    if (asr == null || !looksEnglish(asr.english)) {
      continue;
    }
    compared += 1;
    if (!_sameEnglishText(line.english, asr.english) &&
        !_sentencesAgree(line.english, asr.english)) {
      disagree += 1;
    }
  }
  if (compared < 3) {
    // Too few comparable cues: trust ASR when cue counts diverge sharply.
    return (asrLines.length - working.length).abs() >= 5 ||
        asrLines.length >= working.length * 2;
  }
  return disagree / compared >= disagreeRatio;
}

/// Rebuild bilingual cues from the ASR clock; attach Chinese by time overlap.
///
/// Use this when speech and on-screen English disagree — ZH→EN paraphrases and
/// 串台 Chinese timelines must not keep the wrong timestamps.
List<PlayerSubtitleLine> rebuildBilingualFromAsrLines({
  required List<PlayerSubtitleLine> working,
  required List<PlayerSubtitleLine> asrLines,
}) {
  if (asrLines.isEmpty) {
    return List<PlayerSubtitleLine>.of(working);
  }
  final List<PlayerSubtitleLine> rebuilt = <PlayerSubtitleLine>[
    for (final PlayerSubtitleLine asr in asrLines)
      PlayerSubtitleLine(
        startTime: asr.startTime,
        english: looksEnglish(asr.english)
            ? asr.english.trim()
            : (_bestOverlappingChineseOrEnglish(working, asr).$1),
        chinese: (() {
          final String zh = _bestOverlappingChineseOrEnglish(working, asr).$2;
          if (zh.isNotEmpty) {
            return zh;
          }
          return looksChinese(asr.chinese) ? asr.chinese : '';
        })(),
        startMs: asr.startMs,
        endMs: asr.endMs,
        words: asr.words,
      ),
  ];
  return sanitizeSubtitleLanguageFields(rebuilt);
}

/// Fuse ASR (cleaner sentences) onto OCR/working cues while keeping Chinese.
///
/// Prefer ASR English when OCR looks glued or ASR offers a fuller phrase.
List<PlayerSubtitleLine> fuseOcrWithAsrLines({
  required List<PlayerSubtitleLine> working,
  required List<PlayerSubtitleLine> asrLines,
}) {
  if (asrLines.isEmpty) {
    return List<PlayerSubtitleLine>.of(working);
  }
  if (working.isEmpty) {
    return List<PlayerSubtitleLine>.of(asrLines);
  }

  // Speech↔text mismatch or sparse/glued OCR: ASR owns the timeline.
  if (workingEnglishMismatchesAsr(working: working, asrLines: asrLines)) {
    return rebuildBilingualFromAsrLines(working: working, asrLines: asrLines);
  }

  final bool workingMostlyGlued =
      working
          .where((PlayerSubtitleLine line) => looksEnglish(line.english))
          .map((PlayerSubtitleLine line) => ocrEnglishLooksGlued(line.english))
          .where((bool glued) => glued)
          .length >=
      2;
  final bool workingSparse = working.length <= 3 && asrLines.length >= 5;

  // Sparse OCR fragments: take ASR as the timeline, attach Chinese by overlap.
  if (workingSparse || workingMostlyGlued) {
    return rebuildBilingualFromAsrLines(working: working, asrLines: asrLines);
  }

  final List<PlayerSubtitleLine> merged = <PlayerSubtitleLine>[];
  for (final PlayerSubtitleLine line in working) {
    final PlayerSubtitleLine? asr = _bestOverlappingLine(asrLines, line);
    if (asr == null || !looksEnglish(asr.english)) {
      merged.add(
        PlayerSubtitleLine(
          startTime: line.startTime,
          english: repairOcrEnglishSpacing(line.english),
          chinese: line.chinese,
          startMs: line.startMs,
          endMs: line.endMs,
          words: line.words,
        ),
      );
      continue;
    }
    final String repaired = repairOcrEnglishSpacing(line.english);
    final bool preferAsr = shouldPreferAsrProof(repaired, asr.english);
    merged.add(
      PlayerSubtitleLine(
        startTime: line.startTime,
        english: preferAsr ? asr.english.trim() : repaired,
        chinese: looksChinese(line.chinese)
            ? line.chinese
            : (looksChinese(asr.chinese) ? asr.chinese : line.chinese),
        startMs: line.startMs,
        endMs: line.endMs,
        words: preferAsr && asr.words.isNotEmpty ? asr.words : line.words,
      ),
    );
  }
  return sanitizeSubtitleLanguageFields(merged);
}

(String, String) _bestOverlappingChineseOrEnglish(
  List<PlayerSubtitleLine> working,
  PlayerSubtitleLine asr,
) {
  final PlayerSubtitleLine? hit = _bestOverlappingLine(working, asr);
  if (hit == null) {
    return ('', '');
  }
  final String english = looksEnglish(hit.english)
      ? repairOcrEnglishSpacing(hit.english)
      : '';
  final String chinese = looksChinese(hit.chinese)
      ? hit.chinese
      : (looksChinese(hit.english) ? hit.english : '');
  return (english, chinese);
}

PlayerSubtitleLine? _bestOverlappingLine(
  List<PlayerSubtitleLine> candidates,
  PlayerSubtitleLine target,
) {
  PlayerSubtitleLine? best;
  int bestOverlap = 0;
  for (final PlayerSubtitleLine line in candidates) {
    final int start = line.startMs > target.startMs
        ? line.startMs
        : target.startMs;
    final int end = line.endMs < target.endMs ? line.endMs : target.endMs;
    final int overlap = end - start;
    if (overlap > bestOverlap) {
      bestOverlap = overlap;
      best = line;
    }
  }
  return bestOverlap > 200 ? best : null;
}

MissingSubtitleSide detectMissingSubtitleSide(List<PlayerSubtitleLine> lines) {
  if (lines.isEmpty) {
    return MissingSubtitleSide.both;
  }
  int englishHits = 0;
  int chineseHits = 0;
  for (final PlayerSubtitleLine line in lines) {
    // Glued / junk OCR (`Uam…`) is not usable English — keep translating.
    if (isReliableOcrEnglish(line.english)) {
      englishHits += 1;
    }
    if (looksChinese(line.chinese) ||
        (!looksEnglish(line.english) && looksChinese(line.english))) {
      chineseHits += 1;
    }
  }
  final int total = lines.length;
  final bool anyMissingEnglish = englishHits < total;
  final bool anyMissingChinese = chineseHits < total;
  // Learning product: keep filling until EVERY cue has real English when a
  // Chinese track exists. Partial OCR crumbs must not stop ZH→EN / OCR fill.
  if (anyMissingEnglish &&
      anyMissingChinese &&
      englishHits == 0 &&
      chineseHits == 0) {
    return MissingSubtitleSide.both;
  }
  if (anyMissingEnglish && chineseHits > 0) {
    return MissingSubtitleSide.english;
  }
  if (anyMissingChinese && englishHits > 0) {
    return MissingSubtitleSide.chinese;
  }
  if (englishHits == 0 && chineseHits == 0) {
    return MissingSubtitleSide.both;
  }
  if (englishHits == 0) {
    return MissingSubtitleSide.english;
  }
  if (chineseHits == 0) {
    return MissingSubtitleSide.chinese;
  }
  return MissingSubtitleSide.none;
}

bool needsBilingualFill(List<PlayerSubtitleLine> lines) {
  return detectMissingSubtitleSide(lines) != MissingSubtitleSide.none;
}

/// Count how many lines gained the previously-missing side after a merge.
int countFilledMissingSide({
  required List<PlayerSubtitleLine> before,
  required List<PlayerSubtitleLine> after,
  required MissingSubtitleSide missing,
}) {
  if (missing == MissingSubtitleSide.none || after.isEmpty) {
    return 0;
  }
  int filled = 0;
  final int n = after.length < before.length ? after.length : before.length;
  for (int i = 0; i < n; i++) {
    final PlayerSubtitleLine a = before[i];
    final PlayerSubtitleLine b = after[i];
    switch (missing) {
      case MissingSubtitleSide.english:
        if (!looksEnglish(a.english) && looksEnglish(b.english)) {
          filled += 1;
        }
      case MissingSubtitleSide.chinese:
        if (!looksChinese(a.chinese) && looksChinese(b.chinese)) {
          filled += 1;
        }
      case MissingSubtitleSide.both:
        if ((!looksEnglish(a.english) && looksEnglish(b.english)) ||
            (!looksChinese(a.chinese) && looksChinese(b.chinese))) {
          filled += 1;
        }
      case MissingSubtitleSide.none:
        break;
    }
  }
  // New OCR-only cues appended after seed lines.
  for (int i = n; i < after.length; i++) {
    final PlayerSubtitleLine line = after[i];
    if (looksEnglish(line.english) || looksChinese(line.chinese)) {
      filled += 1;
    }
  }
  return filled;
}

/// Merge one OCR sample into the subtitle timeline.
///
/// Timing rules (video clock = [positionMs]):
/// 1. Prefer the cue that currently contains the playhead.
/// 2. Else extend a nearby cue that already shows the same OCR English.
/// 3. Else patch the closest cue within [toleranceMs].
/// 4. Else append a new cue anchored at the observation time.
///
/// OCR English always follows the video timeline: while the same hardsub is
/// visible, [endMs] grows with each sample so the overlay stays in sync.
List<PlayerSubtitleLine> mergeOcrCueIntoLines({
  required List<PlayerSubtitleLine> lines,
  required int positionMs,
  required OcrCueText cue,
  int toleranceMs = 1800,
  int holdMs = 1800,
  int leadMs = 200,
  int extendGapMs = 1200,

  /// When Chinese cues already exist, OCR only proofreads translated English.
  /// It must not invent a new (often broken) English line first.
  bool proofreadOnly = false,
}) {
  if (cue.isEmpty) {
    return List<PlayerSubtitleLine>.of(lines);
  }
  final List<PlayerSubtitleLine> next = List<PlayerSubtitleLine>.of(lines);
  final String cueEnglish = repairOcrEnglishSpacing(cue.english.trim());
  final String cueChinese = cue.chinese.trim();
  final bool hasOcrEnglish = looksEnglish(cueEnglish);
  final int observedEnd = positionMs + holdMs;

  int containingIndex = -1;
  int containingDistance = 1 << 30;
  int nearbyIndex = -1;
  int nearbyDistance = 1 << 30;
  for (int i = 0; i < next.length; i++) {
    final PlayerSubtitleLine line = next[i];
    if (positionMs >= line.startMs && positionMs <= line.endMs) {
      final int mid = (line.startMs + line.endMs) ~/ 2;
      final int distance = (mid - positionMs).abs();
      if (distance < containingDistance) {
        containingDistance = distance;
        containingIndex = i;
      }
    }
    if (positionMs >= line.startMs - toleranceMs &&
        positionMs <= line.endMs + toleranceMs) {
      final int mid = (line.startMs + line.endMs) ~/ 2;
      final int distance = (mid - positionMs).abs();
      if (distance < nearbyDistance) {
        nearbyDistance = distance;
        nearbyIndex = i;
      }
    }
  }

  // Same English hardsub still on screen → stretch that cue on the video clock.
  if (hasOcrEnglish) {
    int extendIndex = -1;
    int extendDistance = 1 << 30;
    for (int i = 0; i < next.length; i++) {
      final PlayerSubtitleLine line = next[i];
      if (!_ocrEnglishSame(line.english, cueEnglish)) {
        continue;
      }
      final bool nearTail =
          positionMs >= line.startMs - leadMs &&
          positionMs <= line.endMs + extendGapMs;
      if (!nearTail) {
        continue;
      }
      final int distance = (positionMs - line.endMs).abs();
      if (distance < extendDistance) {
        extendDistance = distance;
        extendIndex = i;
      }
    }
    if (extendIndex >= 0 &&
        (containingIndex < 0 || extendIndex == containingIndex)) {
      final PlayerSubtitleLine current = next[extendIndex];
      final int endMs = observedEnd > current.endMs
          ? observedEnd
          : current.endMs;
      final String? english = _englishAfterOcrProof(
        current: current.english,
        ocr: cueEnglish,
        proofreadOnly: proofreadOnly,
      );
      if (english == null) {
        if (_ocrEnglishSame(current.english, cueEnglish)) {
          next[extendIndex] = PlayerSubtitleLine(
            startTime: current.startTime,
            english: current.english,
            chinese: cueChinese.isNotEmpty ? cueChinese : current.chinese,
            startMs: current.startMs,
            endMs: endMs,
            words: current.words,
          );
        }
        return sanitizeSubtitleLanguageFields(next);
      }
      next[extendIndex] = PlayerSubtitleLine(
        startTime: current.startTime,
        english: english,
        chinese: cueChinese.isNotEmpty ? cueChinese : current.chinese,
        startMs: current.startMs,
        endMs: endMs,
        words: current.words,
      );
      return sanitizeSubtitleLanguageFields(next);
    }
  }

  final int bestIndex = containingIndex >= 0 ? containingIndex : nearbyIndex;
  if (bestIndex >= 0) {
    final PlayerSubtitleLine current = next[bestIndex];
    final bool currentEnglishIsChineseOnly =
        !looksEnglish(current.english) && looksChinese(current.english);
    // Unreliable OCR (`Uam…`) never overwrites a translation. When Chinese
    // cues exist, OCR only proofreads English that translation already wrote.
    final String? proved = _englishAfterOcrProof(
      current: current.english,
      ocr: hasOcrEnglish ? cueEnglish : '',
      proofreadOnly: proofreadOnly,
    );
    final String english = proved ?? current.english;
    final String chinese =
        cueChinese.isNotEmpty &&
            (current.chinese.trim().isEmpty ||
                current.chinese.trim() == current.english.trim())
        ? cueChinese
        : (current.chinese.trim().isNotEmpty
              ? current.chinese
              : (currentEnglishIsChineseOnly
                    ? current.english
                    : current.chinese));
    // Keep official cue start; extend end so hardsub stays visible with video.
    final int endMs = hasOcrEnglish && observedEnd > current.endMs
        ? observedEnd
        : current.endMs;
    next[bestIndex] = PlayerSubtitleLine(
      startTime: current.startTime,
      english: english,
      chinese: chinese,
      startMs: current.startMs,
      endMs: endMs,
      words: current.words,
    );
    return sanitizeSubtitleLanguageFields(next);
  }

  // Chinese-timed courses keep the official cue list; don't append OCR crumbs.
  if (proofreadOnly || (hasOcrEnglish && !isReliableOcrEnglish(cueEnglish))) {
    return sanitizeSubtitleLanguageFields(next);
  }
  // No nearby timeline cue — anchor a new one at the observation clock.
  final int startMs = positionMs < leadMs ? 0 : positionMs - leadMs;
  final String appendEnglish = hasOcrEnglish ? cueEnglish : '';
  next.add(
    PlayerSubtitleLine(
      startTime: _formatClock(startMs),
      english: appendEnglish,
      chinese: cueChinese,
      startMs: startMs,
      endMs: observedEnd > startMs + 400 ? observedEnd : startMs + 400,
    ),
  );
  next.sort(
    (PlayerSubtitleLine a, PlayerSubtitleLine b) =>
        a.startMs.compareTo(b.startMs),
  );
  return sanitizeSubtitleLanguageFields(next);
}

/// Null means "do not change English".
String? _englishAfterOcrProof({
  required String current,
  required String ocr,
  required bool proofreadOnly,
}) {
  final String next = ocr.trim();
  if (!isReliableOcrEnglish(next)) {
    return null;
  }
  final bool currentIsEnglish = looksEnglish(current) && !looksChinese(current);
  if (proofreadOnly && !currentIsEnglish) {
    return null;
  }
  if (currentIsEnglish && !shouldPreferOcrProof(current, next)) {
    return null;
  }
  return next;
}

bool _ocrEnglishSame(String a, String b) {
  final String left = a.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final String right = b.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  return left == right;
}

List<PlayerSubtitleLine> fillMissingSideByTranslation({
  required List<PlayerSubtitleLine> lines,
  required MissingSubtitleSide missing,
  required List<String> translations,
}) {
  if (missing == MissingSubtitleSide.none || translations.isEmpty) {
    return lines;
  }
  final List<PlayerSubtitleLine> next = <PlayerSubtitleLine>[];
  int cursor = 0;
  for (final PlayerSubtitleLine line in lines) {
    final String translated = cursor < translations.length
        ? translations[cursor].trim()
        : '';
    cursor += 1;
    if (translated.isEmpty) {
      next.add(line);
      continue;
    }
    switch (missing) {
      case MissingSubtitleSide.english:
        next.add(
          PlayerSubtitleLine(
            startTime: line.startTime,
            english: _englishForChineseCue(
              current: line.english,
              translated: translated,
              chinese: line.chinese,
            ),
            chinese: looksChinese(line.chinese)
                ? line.chinese
                : (looksChinese(line.english) ? line.english : line.chinese),
            startMs: line.startMs,
            endMs: line.endMs,
            words: line.words,
          ),
        );
      case MissingSubtitleSide.chinese:
        next.add(
          PlayerSubtitleLine(
            startTime: line.startTime,
            english: line.english,
            chinese: looksChinese(line.chinese) ? line.chinese : translated,
            startMs: line.startMs,
            endMs: line.endMs,
            words: line.words,
          ),
        );
      case MissingSubtitleSide.both:
        // Prefer treating [translated] as English when the source cue was
        // Chinese-only — never copy the English string into chinese.
        final String nextEnglish = _englishForChineseCue(
          current: line.english,
          translated: translated,
          chinese: line.chinese.isNotEmpty ? line.chinese : line.english,
        );
        final String nextChinese = looksChinese(line.chinese)
            ? line.chinese
            : (looksChinese(line.english) ? line.english : '');
        next.add(
          PlayerSubtitleLine(
            startTime: line.startTime,
            english: nextEnglish,
            chinese: nextChinese,
            startMs: line.startMs,
            endMs: line.endMs,
            words: line.words,
          ),
        );
      case MissingSubtitleSide.none:
        next.add(line);
    }
  }
  return next;
}

/// English on a Chinese cue is that cue's translation. A fluent sentence about
/// something else must not stay just because it looks like English.
String _englishForChineseCue({
  required String current,
  required String translated,
  required String chinese,
}) {
  final String next = translated.trim();
  if (next.isEmpty || looksChinese(next)) {
    return current;
  }
  if (!looksChinese(chinese)) {
    return isReliableOcrEnglish(current) ? current : next;
  }
  if (!looksEnglish(current) || looksChinese(current)) {
    return next;
  }
  if (_sameEnglishText(current, next) || _sentencesAgree(current, next)) {
    return current;
  }
  return next;
}

List<String> sourceTextsForTranslation({
  required List<PlayerSubtitleLine> lines,
  required MissingSubtitleSide missing,
}) {
  return lines
      .map((PlayerSubtitleLine line) {
        switch (missing) {
          case MissingSubtitleSide.english:
            return looksChinese(line.chinese)
                ? line.chinese
                : (looksChinese(line.english) ? line.english : line.chinese);
          case MissingSubtitleSide.chinese:
            return line.english;
          case MissingSubtitleSide.both:
            return line.english.isNotEmpty ? line.english : line.chinese;
          case MissingSubtitleSide.none:
            return '';
        }
      })
      .toList(growable: false);
}

String _formatClock(int milliseconds) {
  final int totalSeconds = milliseconds ~/ 1000;
  final int minutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
