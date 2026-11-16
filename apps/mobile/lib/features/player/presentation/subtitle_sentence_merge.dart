import 'bilingual_subtitle_helpers.dart';
import 'player_mock_state.dart';
import 'subtitle_word_alignment.dart';

/// Max gap between adjacent ASR cues that may still form one sentence.
/// Slightly generous so Whisper crumbs like "There is" + "a lot of water"
/// become one study sentence instead of two chips.
/// Slightly wider than before so Whisper crumbs coalesce into study sentences
/// (SmartSub-style sentence tidy without full VAD).
const int kSubtitleSentenceMergeGapMs = 1600;

/// One learning-facing sentence built from ASR, with Chinese attached by time.
class SubtitleSentence {
  const SubtitleSentence({
    required this.startMs,
    required this.endMs,
    required this.english,
    required this.chinese,
    required this.fragmentStartMs,
    required this.fragmentEndMs,
    this.words = const <PlayerSubtitleWord>[],
  });

  final int startMs;
  final int endMs;
  final String english;
  final String chinese;
  final List<int> fragmentStartMs;
  final List<int> fragmentEndMs;

  /// Word-level timings from Whisper/cloud ASR (required for green karaoke).
  final List<PlayerSubtitleWord> words;

  String get startTime => _clock(startMs);

  PlayerSubtitleLine toLine() {
    return PlayerSubtitleLine(
      startTime: startTime,
      english: english,
      chinese: chinese,
      startMs: startMs,
      endMs: endMs,
      words: words,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'startMs': startMs,
      'endMs': endMs,
      'english': english,
      'chinese': chinese,
      'fragmentStartMs': fragmentStartMs,
      'fragmentEndMs': fragmentEndMs,
      if (words.isNotEmpty)
        'words': words
            .map(
              (PlayerSubtitleWord word) => <String, Object?>{
                'text': word.text,
                'startMs': word.startMs,
                'endMs': word.endMs,
                if (word.confidence != null) 'confidence': word.confidence,
              },
            )
            .toList(growable: false),
    };
  }

  static SubtitleSentence? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final int? startMs = _asInt(raw['startMs']);
    final int? endMs = _asInt(raw['endMs']);
    final String english = '${raw['english'] ?? ''}'.trim();
    if (startMs == null || endMs == null || endMs <= startMs) {
      return null;
    }
    if (english.isEmpty && '${raw['chinese'] ?? ''}'.trim().isEmpty) {
      return null;
    }
    return SubtitleSentence(
      startMs: startMs,
      endMs: endMs,
      english: english,
      chinese: '${raw['chinese'] ?? ''}'.trim(),
      fragmentStartMs: _asIntList(raw['fragmentStartMs']),
      fragmentEndMs: _asIntList(raw['fragmentEndMs']),
      words: _asWords(raw['words']),
    );
  }
}

/// Official Chinese cue plus the ASR English that overlaps that window.
class SubtitleFragment {
  const SubtitleFragment({
    required this.startMs,
    required this.endMs,
    required this.english,
    required this.chinese,
    this.words = const <PlayerSubtitleWord>[],
  });

  final int startMs;
  final int endMs;
  final String english;
  final String chinese;
  final List<PlayerSubtitleWord> words;

  String get startTime => _clock(startMs);

  PlayerSubtitleLine toLine() {
    return PlayerSubtitleLine(
      startTime: startTime,
      english: english,
      chinese: chinese,
      startMs: startMs,
      endMs: endMs,
      words: words,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'startMs': startMs,
      'endMs': endMs,
      'english': english,
      'chinese': chinese,
      if (words.isNotEmpty)
        'words': words
            .map(
              (PlayerSubtitleWord word) => <String, Object?>{
                'text': word.text,
                'startMs': word.startMs,
                'endMs': word.endMs,
                if (word.confidence != null) 'confidence': word.confidence,
              },
            )
            .toList(growable: false),
    };
  }

  static SubtitleFragment? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final int? startMs = _asInt(raw['startMs']);
    final int? endMs = _asInt(raw['endMs']);
    if (startMs == null || endMs == null || endMs <= startMs) {
      return null;
    }
    return SubtitleFragment(
      startMs: startMs,
      endMs: endMs,
      english: '${raw['english'] ?? ''}'.trim(),
      chinese: '${raw['chinese'] ?? ''}'.trim(),
      words: _asWords(raw['words']),
    );
  }
}

class MergedSubtitleBundle {
  const MergedSubtitleBundle({
    required this.sentences,
    required this.fragments,
  });

  final List<SubtitleSentence> sentences;
  final List<SubtitleFragment> fragments;

  List<PlayerSubtitleLine> get sentenceLines =>
      sentences.map((SubtitleSentence s) => s.toLine()).toList(growable: false);

  List<PlayerSubtitleLine> get fragmentLines => fragments
      .map((SubtitleFragment f) => f.toLine())
      .toList(growable: false);

  /// Fragments under each sentence, keyed by sentence [startMs].
  Map<int, List<PlayerSubtitleLine>> fragmentsBySentenceStartMs() {
    final Map<int, List<PlayerSubtitleLine>> out =
        <int, List<PlayerSubtitleLine>>{};
    for (final SubtitleSentence sentence in sentences) {
      final List<PlayerSubtitleLine> kids = <PlayerSubtitleLine>[];
      for (final SubtitleFragment fragment in fragments) {
        final bool listed =
            sentence.fragmentStartMs.contains(fragment.startMs) ||
            (sentence.fragmentStartMs.isNotEmpty &&
                sentence.fragmentEndMs.isNotEmpty &&
                _rangesOverlap(
                  fragment.startMs,
                  fragment.endMs,
                  sentence.fragmentStartMs,
                  sentence.fragmentEndMs,
                ));
        final bool overlapsSentence =
            _overlapMs(
              sentence.startMs,
              sentence.endMs,
              fragment.startMs,
              fragment.endMs,
            ) >
            0;
        if (listed || overlapsSentence) {
          kids.add(fragment.toLine());
        }
      }
      kids.sort(
        (PlayerSubtitleLine a, PlayerSubtitleLine b) =>
            a.startMs.compareTo(b.startMs),
      );
      if (kids.isNotEmpty) {
        out[sentence.startMs] = kids;
      }
    }
    return out;
  }
}

bool _rangesOverlap(
  int startMs,
  int endMs,
  List<int> starts,
  List<int> ends,
) {
  final int n = starts.length < ends.length ? starts.length : ends.length;
  for (int i = 0; i < n; i++) {
    if (_overlapMs(startMs, endMs, starts[i], ends[i]) > 0) {
      return true;
    }
  }
  return false;
}

/// Merge ASR cues into complete English sentences, then attach Chinese by time.
MergedSubtitleBundle mergeAsrIntoSentences({
  required List<PlayerSubtitleLine> asrLines,
  List<PlayerSubtitleLine> chineseLines = const <PlayerSubtitleLine>[],
  int maxGapMs = kSubtitleSentenceMergeGapMs,
}) {
  final List<PlayerSubtitleLine> asr = asrLines
      .where(
        (PlayerSubtitleLine line) =>
            line.endMs > line.startMs &&
            looksEnglish(line.english) &&
            !looksChinese(line.english),
      )
      .toList(growable: false)
    ..sort(
      (PlayerSubtitleLine a, PlayerSubtitleLine b) =>
          a.startMs.compareTo(b.startMs),
    );

  final List<PlayerSubtitleLine> chinese = chineseLines
      .map(_normalizeChineseCue)
      .where(
        (PlayerSubtitleLine line) =>
            line.endMs > line.startMs && looksChinese(line.chinese),
      )
      .toList(growable: false)
    ..sort(
      (PlayerSubtitleLine a, PlayerSubtitleLine b) =>
          a.startMs.compareTo(b.startMs),
    );

  final List<List<PlayerSubtitleLine>> groups = <List<PlayerSubtitleLine>>[];
  for (final PlayerSubtitleLine line in asr) {
    if (groups.isEmpty) {
      groups.add(<PlayerSubtitleLine>[line]);
      continue;
    }
    final List<PlayerSubtitleLine> current = groups.last;
    final PlayerSubtitleLine last = current.last;
    final int gap = line.startMs - last.endMs;
    if (_shouldMergeEnglishCues(
      previous: last.english,
      next: line.english,
      gapMs: gap,
      maxGapMs: maxGapMs,
    )) {
      current.add(line);
    } else {
      groups.add(<PlayerSubtitleLine>[line]);
    }
  }

  final List<SubtitleSentence> rawSentences = <SubtitleSentence>[];
  for (final List<PlayerSubtitleLine> group in groups) {
    final int startMs = group.first.startMs;
    final int endMs = group.last.endMs;
    final String english = _joinEnglish(
      group.map((PlayerSubtitleLine line) => line.english),
    );
    final List<PlayerSubtitleLine> overlapped = chinese
        .where(
          (PlayerSubtitleLine cue) =>
              _overlapMs(startMs, endMs, cue.startMs, cue.endMs) > 0,
        )
        .toList(growable: false);
    final String zh = overlapped
        .map((PlayerSubtitleLine cue) => cue.chinese.trim())
        .where((String text) => text.isNotEmpty)
        .join(' ');
    rawSentences.add(
      SubtitleSentence(
        startMs: startMs,
        endMs: endMs,
        english: english,
        chinese: zh,
        fragmentStartMs: overlapped
            .map((PlayerSubtitleLine cue) => cue.startMs)
            .toList(growable: false),
        fragmentEndMs: overlapped
            .map((PlayerSubtitleLine cue) => cue.endMs)
            .toList(growable: false),
        words: group
            .expand((PlayerSubtitleLine line) => line.words)
            .toList(growable: false),
      ),
    );
  }
  final List<SubtitleSentence> coalesced = _coalesceIncompleteSentences(
    rawSentences,
    maxGapMs: maxGapMs,
  );
  // Re-align Whisper word timings onto the merged English. Concatenating raw
  // crumb words often leaves a length mismatch vs space-split display tokens,
  // so karaoke index never paints green on the active sentence.
  final List<SubtitleSentence> sentences = _reattachWordTimings(
    sentences: coalesced,
    asrLines: asr,
  );

  final List<SubtitleFragment> fragments = <SubtitleFragment>[];
  if (chinese.isNotEmpty) {
    for (final PlayerSubtitleLine cue in chinese) {
      final String en = _bestOverlappingEnglish(asr, cue.startMs, cue.endMs);
      fragments.add(
        SubtitleFragment(
          startMs: cue.startMs,
          endMs: cue.endMs,
          english: en,
          chinese: cue.chinese,
        ),
      );
    }
  } else {
    for (final PlayerSubtitleLine line in asr) {
      fragments.add(
        SubtitleFragment(
          startMs: line.startMs,
          endMs: line.endMs,
          english: line.english.trim(),
          chinese: '',
          words: line.words,
        ),
      );
    }
  }

  return MergedSubtitleBundle(sentences: sentences, fragments: fragments);
}

/// Map ASR word clocks onto each merged sentence's space-split English 1:1.
List<SubtitleSentence> _reattachWordTimings({
  required List<SubtitleSentence> sentences,
  required List<PlayerSubtitleLine> asrLines,
}) {
  if (sentences.isEmpty) {
    return sentences;
  }
  final List<PlayerSubtitleWord> pool = <PlayerSubtitleWord>[
    ...asrLines.expand((PlayerSubtitleLine line) => line.words),
    ...sentences.expand((SubtitleSentence sentence) => sentence.words),
  ];
  return sentences
      .map((SubtitleSentence sentence) {
        final List<PlayerSubtitleWord> nearby = pool
            .where(
              (PlayerSubtitleWord word) =>
                  word.endMs > sentence.startMs - 800 &&
                  word.startMs < sentence.endMs + 800,
            )
            .toList(growable: false);
        return SubtitleSentence(
          startMs: sentence.startMs,
          endMs: sentence.endMs,
          english: sentence.english,
          chinese: sentence.chinese,
          fragmentStartMs: sentence.fragmentStartMs,
          fragmentEndMs: sentence.fragmentEndMs,
          words: fitWordTimingsToDisplayEnglish(
            english: sentence.english,
            timedWords: nearby.isNotEmpty ? nearby : sentence.words,
            startMs: sentence.startMs,
            endMs: sentence.endMs,
          ),
        );
      })
      .toList(growable: false);
}

PlayerSubtitleLine _normalizeChineseCue(PlayerSubtitleLine line) {
  final String zh = line.chinese.trim().isNotEmpty
      ? line.chinese.trim()
      : (looksChinese(line.english) ? line.english.trim() : '');
  return PlayerSubtitleLine(
    startTime: line.startTime,
    english: '',
    chinese: zh,
    startMs: line.startMs,
    endMs: line.endMs,
    words: line.words,
  );
}

final RegExp _abbreviationEnd = RegExp(
  r'\b(Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|etc|U\.S|U\.K|e\.g|i\.e)\.$',
  caseSensitive: false,
);

bool _englishEndsSentence(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return false;
  }
  if (_abbreviationEnd.hasMatch(text)) {
    return false;
  }
  // Allow closing quote after end punctuation.
  return RegExp(r'[.?!…]["”]?$').hasMatch(text);
}

bool _englishLooksContinuation(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return false;
  }
  final String first = text[0];
  return RegExp(r'[a-z]').hasMatch(first);
}

bool _englishLooksIncomplete(String raw) {
  final String text = raw.trim();
  if (text.isEmpty) {
    return true;
  }
  if (_englishEndsSentence(text)) {
    return false;
  }
  if (RegExp(r'[,:;—–-]$').hasMatch(text)) {
    return true;
  }
  return RegExp(
    r'\b(and|or|but|that|which|who|whom|whose|to|of|for|with|in|on|at|a|an|the|as|if|when|while|because|so)$',
    caseSensitive: false,
  ).hasMatch(text);
}

bool _shouldMergeEnglishCues({
  required String previous,
  required String next,
  required int gapMs,
  required int maxGapMs,
}) {
  if (gapMs > maxGapMs) {
    return false;
  }
  if (!_englishEndsSentence(previous)) {
    return true;
  }
  // False period (abbr) already handled. Rare: Whisper ends mid-thought with
  // "." then continues lowercase — keep merging for a complete sentence.
  return _englishLooksContinuation(next);
}

List<SubtitleSentence> _coalesceIncompleteSentences(
  List<SubtitleSentence> input, {
  required int maxGapMs,
}) {
  if (input.length < 2) {
    return input;
  }
  final List<SubtitleSentence> out = <SubtitleSentence>[];
  for (final SubtitleSentence sentence in input) {
    if (out.isEmpty) {
      out.add(sentence);
      continue;
    }
    final SubtitleSentence prev = out.last;
    final int gap = sentence.startMs - prev.endMs;
    final bool merge =
        gap <= maxGapMs &&
        (_englishLooksIncomplete(prev.english) ||
            (_englishLooksContinuation(sentence.english) &&
                !_englishEndsSentence(prev.english)));
    if (!merge) {
      out.add(sentence);
      continue;
    }
    out[out.length - 1] = SubtitleSentence(
      startMs: prev.startMs,
      endMs: sentence.endMs,
      english: _joinEnglish(<String>[prev.english, sentence.english]),
      chinese: <String>[prev.chinese, sentence.chinese]
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .join(' '),
      fragmentStartMs: <int>[
        ...prev.fragmentStartMs,
        ...sentence.fragmentStartMs,
      ],
      fragmentEndMs: <int>[...prev.fragmentEndMs, ...sentence.fragmentEndMs],
      words: <PlayerSubtitleWord>[...prev.words, ...sentence.words],
    );
  }
  return out;
}

String _joinEnglish(Iterable<String> parts) {
  final StringBuffer out = StringBuffer();
  for (final String part in parts) {
    final String text = part.trim();
    if (text.isEmpty) {
      continue;
    }
    if (out.isEmpty) {
      out.write(text);
      continue;
    }
    final String prev = out.toString();
    final bool prevEndsSpace = prev.endsWith(' ') || prev.endsWith('\n');
    final bool nextStartsPunct = RegExp(r'^[,.;:!?…]').hasMatch(text);
    if (!prevEndsSpace && !nextStartsPunct) {
      out.write(' ');
    }
    out.write(text);
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _bestOverlappingEnglish(
  List<PlayerSubtitleLine> asr,
  int startMs,
  int endMs,
) {
  String best = '';
  int bestOverlap = 0;
  for (final PlayerSubtitleLine line in asr) {
    final int overlap = _overlapMs(startMs, endMs, line.startMs, line.endMs);
    if (overlap > bestOverlap) {
      bestOverlap = overlap;
      best = line.english.trim();
    }
  }
  return best;
}

int _overlapMs(int aStart, int aEnd, int bStart, int bEnd) {
  final int start = aStart > bStart ? aStart : bStart;
  final int end = aEnd < bEnd ? aEnd : bEnd;
  final int overlap = end - start;
  return overlap > 0 ? overlap : 0;
}

String _clock(int milliseconds) {
  final int clamped = milliseconds < 0 ? 0 : milliseconds;
  final int totalSeconds = clamped ~/ 1000;
  final int minutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse('$value');
}

List<int> _asIntList(Object? value) {
  if (value is! List) {
    return const <int>[];
  }
  final List<int> out = <int>[];
  for (final Object? item in value) {
    final int? n = _asInt(item);
    if (n != null) {
      out.add(n);
    }
  }
  return out;
}

List<PlayerSubtitleWord> _asWords(Object? value) {
  if (value is! List) {
    return const <PlayerSubtitleWord>[];
  }
  final List<PlayerSubtitleWord> out = <PlayerSubtitleWord>[];
  for (final Object? item in value) {
    if (item is! Map) {
      continue;
    }
    final String text = '${item['text'] ?? ''}'.trim();
    final int? startMs = _asInt(item['startMs']);
    final int? endMs = _asInt(item['endMs']);
    if (text.isEmpty || startMs == null || endMs == null || endMs <= startMs) {
      continue;
    }
    final double? confidence = item['confidence'] is num
        ? (item['confidence'] as num).toDouble()
        : null;
    out.add(
      PlayerSubtitleWord(
        text: text,
        startMs: startMs,
        endMs: endMs,
        confidence: confidence,
      ),
    );
  }
  return out;
}
