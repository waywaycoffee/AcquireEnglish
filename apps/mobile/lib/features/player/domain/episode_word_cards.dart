import '../../phrases/presentation/phrase_book_provider.dart';
import '../../words/presentation/word_book_provider.dart';
import '../presentation/player_mock_state.dart';

/// Shadow Talk–style episode vocabulary card kinds.
enum EpisodeCardKind { word, phrase, sentence }

extension EpisodeCardKindLabel on EpisodeCardKind {
  String get label {
    switch (this) {
      case EpisodeCardKind.word:
        return '单词';
      case EpisodeCardKind.phrase:
        return '短语';
      case EpisodeCardKind.sentence:
        return '短句';
    }
  }
}

class EpisodeWordCard {
  const EpisodeWordCard({
    required this.id,
    required this.text,
    required this.kind,
    required this.favorited,
    required this.source,
    this.meaningCn,
    this.phonetic,
    this.partOfSpeech,
    this.exampleEn,
    this.exampleCn,
    this.time,
    this.startMs,
    this.endMs,
    this.tags = const <String>[],
  });

  final String id;
  final String text;
  final EpisodeCardKind kind;
  final bool favorited;

  /// `favorite` from word/phrase book, or `suggested` from this episode's lines.
  final String source;
  final String? meaningCn;
  final String? phonetic;
  final String? partOfSpeech;
  final String? exampleEn;
  final String? exampleCn;
  final String? time;
  final int? startMs;
  final int? endMs;
  final List<String> tags;
}

/// Builds a Shadow Talk–like episode vocabulary deck.
///
/// Priority: favorited words/phrases for [episodeId], then content-word
/// suggestions mined from [lines] (capped) so empty favorites still show cards.
List<EpisodeWordCard> buildEpisodeWordCards({
  required String episodeId,
  required List<PlayerSubtitleLine> lines,
  required List<WordEntry> words,
  required List<PhraseEntry> phrases,
  int maxSuggested = 18,
}) {
  final Map<String, EpisodeWordCard> byKey = <String, EpisodeWordCard>{};

  void put(EpisodeWordCard card) {
    final String key = card.text.trim().toLowerCase();
    if (key.isEmpty) return;
    final EpisodeWordCard? existing = byKey[key];
    if (existing == null) {
      byKey[key] = card;
      return;
    }
    // Prefer favorited / richer metadata.
    if (!existing.favorited && card.favorited) {
      byKey[key] = card;
      return;
    }
    if ((existing.meaningCn == null || existing.meaningCn!.isEmpty) &&
        card.meaningCn != null &&
        card.meaningCn!.isNotEmpty) {
      byKey[key] = card.copyWith(
        favorited: existing.favorited || card.favorited,
        source: existing.favorited ? existing.source : card.source,
      );
    }
  }

  for (final WordEntry entry in words) {
    final List<WordOccurrence> hits = entry.occurrences
        .where((WordOccurrence o) => o.episodeId == episodeId)
        .toList(growable: false);
    if (hits.isEmpty && !entry.favorite) continue;
    if (hits.isEmpty) continue;
    final WordOccurrence first = hits.first;
    final WordContext? ctx = first.contexts.isEmpty
        ? null
        : first.contexts.first;
    put(
      EpisodeWordCard(
        id: 'word:${entry.word}',
        text: entry.word,
        kind: _kindForText(entry.word),
        favorited: entry.favorite,
        source: 'favorite',
        meaningCn: entry.definitionCn ?? entry.offlineDefinitionCn,
        exampleEn: ctx?.sentence ?? first.sentence,
        exampleCn: ctx?.chinese ?? first.chinese,
        time: ctx?.time ?? first.time,
        startMs: _parseStartMs(
          ctx?.lineKey ?? (first.lineKeys.isEmpty ? null : first.lineKeys.first),
        ),
        endMs: _parseEndMs(
          ctx?.lineKey ?? (first.lineKeys.isEmpty ? null : first.lineKeys.first),
        ),
      ),
    );
  }

  for (final PhraseEntry phrase in phrases) {
    final bool matchesEpisode =
        phrase.episodeId == episodeId ||
        (phrase.episodeId == null &&
            lines.any(
              (PlayerSubtitleLine line) =>
                  line.english.trim().toLowerCase() ==
                      phrase.english.trim().toLowerCase() ||
                  line.startTime == phrase.time ||
                  line.startTime == phrase.startTime,
            ));
    if (!matchesEpisode) continue;
    put(
      EpisodeWordCard(
        id: 'phrase:${phrase.id}',
        text: phrase.english,
        kind: _kindForText(phrase.english),
        favorited: true,
        source: 'favorite',
        meaningCn: phrase.chinese.isEmpty ? null : phrase.chinese,
        exampleEn: phrase.english,
        exampleCn: phrase.chinese.isEmpty ? null : phrase.chinese,
        time: phrase.startTime ?? phrase.time,
        startMs: _msFromClock(phrase.startTime ?? phrase.time),
        endMs: _msFromClock(phrase.endTime),
      ),
    );
  }

  if (byKey.length < 6 && lines.isNotEmpty) {
    final List<EpisodeWordCard> suggested = _suggestFromLines(
      lines: lines,
      limit: maxSuggested,
      existing: byKey.keys.toSet(),
    );
    for (final EpisodeWordCard card in suggested) {
      put(card);
    }
  }

  final List<EpisodeWordCard> result = byKey.values.toList(growable: false);
  result.sort((EpisodeWordCard a, EpisodeWordCard b) {
    if (a.favorited != b.favorited) {
      return a.favorited ? -1 : 1;
    }
    final int kindCmp = a.kind.index.compareTo(b.kind.index);
    if (kindCmp != 0) return kindCmp;
    final int aMs = a.startMs ?? 1 << 30;
    final int bMs = b.startMs ?? 1 << 30;
    if (aMs != bMs) return aMs.compareTo(bMs);
    return a.text.toLowerCase().compareTo(b.text.toLowerCase());
  });
  return result;
}

extension on EpisodeWordCard {
  EpisodeWordCard copyWith({
    bool? favorited,
    String? source,
    String? meaningCn,
  }) {
    return EpisodeWordCard(
      id: id,
      text: text,
      kind: kind,
      favorited: favorited ?? this.favorited,
      source: source ?? this.source,
      meaningCn: meaningCn ?? this.meaningCn,
      phonetic: phonetic,
      partOfSpeech: partOfSpeech,
      exampleEn: exampleEn,
      exampleCn: exampleCn,
      time: time,
      startMs: startMs,
      endMs: endMs,
      tags: tags,
    );
  }
}

EpisodeCardKind _kindForText(String raw) {
  final List<String> tokens = _tokenize(raw);
  if (tokens.length >= 5) return EpisodeCardKind.sentence;
  if (tokens.length >= 2) return EpisodeCardKind.phrase;
  return EpisodeCardKind.word;
}

List<EpisodeWordCard> _suggestFromLines({
  required List<PlayerSubtitleLine> lines,
  required int limit,
  required Set<String> existing,
}) {
  const Set<String> stop = <String>{
    'a',
    'an',
    'the',
    'and',
    'or',
    'but',
    'to',
    'of',
    'in',
    'on',
    'at',
    'for',
    'with',
    'is',
    'are',
    'was',
    'were',
    'be',
    'been',
    'being',
    'am',
    'i',
    'you',
    'he',
    'she',
    'it',
    'we',
    'they',
    'this',
    'that',
    'these',
    'those',
    'my',
    'your',
    'his',
    'her',
    'our',
    'their',
    'me',
    'him',
    'them',
    'as',
    'by',
    'from',
    'up',
    'out',
    'so',
    'if',
    'not',
    'no',
    'do',
    'does',
    'did',
    'have',
    'has',
    'had',
    'just',
    'now',
    'then',
    'here',
    'there',
    'can',
    'could',
    'will',
    'would',
    'should',
    'lets',
    "let's",
    'into',
    'about',
    'over',
    'under',
    'again',
    'also',
    'very',
    'too',
    'all',
    'some',
    'any',
    'more',
    'most',
    'other',
    'than',
    'when',
    'what',
    'which',
    'who',
    'how',
    'where',
    'why',
  };

  final Map<String, _SuggestionHit> hits = <String, _SuggestionHit>{};

  for (final PlayerSubtitleLine line in lines) {
    final List<String> tokens = _tokenize(line.english);
    // Multi-word teaching chunks: "this is called X" / short noun phrases.
    for (int i = 0; i < tokens.length; i++) {
      final String token = tokens[i].toLowerCase();
      if (token.length < 4 ||
          stop.contains(token) ||
          token.contains("'") ||
          token.contains('’')) {
        continue;
      }
      final _SuggestionHit hit = hits.putIfAbsent(
        token,
        () => _SuggestionHit(token: token, line: line),
      );
      hit.count += 1;

      if (i + 1 < tokens.length) {
        final String next = tokens[i + 1].toLowerCase();
        if (next.length >= 3 && !stop.contains(next)) {
          final String phrase = '$token $next';
          if (!existing.contains(phrase)) {
            final _SuggestionHit phraseHit = hits.putIfAbsent(
              phrase,
              () => _SuggestionHit(token: phrase, line: line, isPhrase: true),
            );
            phraseHit.count += 1;
          }
        }
      }
    }

    // Short teaching sentences as sentence cards.
    if (tokens.length >= 4 && tokens.length <= 8) {
      final String sentence = line.english.trim();
      final String key = sentence.toLowerCase();
      if (!existing.contains(key) &&
          RegExp(
            r'^(so |and |now )?(this is|that is|we (do )?say|we don.?t say|it.?s called)',
            caseSensitive: false,
          ).hasMatch(sentence)) {
        hits.putIfAbsent(
          key,
          () => _SuggestionHit(
            token: sentence,
            line: line,
            isSentence: true,
            count: 3,
          ),
        );
      }
    }
  }

  final List<_SuggestionHit> ranked = hits.values.toList()
    ..sort((_SuggestionHit a, _SuggestionHit b) {
      if (a.count != b.count) return b.count.compareTo(a.count);
      return b.token.length.compareTo(a.token.length);
    });

  final List<EpisodeWordCard> out = <EpisodeWordCard>[];
  for (final _SuggestionHit hit in ranked) {
    if (out.length >= limit) break;
    if (existing.contains(hit.token.toLowerCase())) continue;
    if (!hit.isPhrase && !hit.isSentence && hit.token.length < 5 && hit.count < 2) {
      continue;
    }
    out.add(
      EpisodeWordCard(
        id: 'suggested:${hit.token}',
        text: hit.token,
        kind: hit.isSentence
            ? EpisodeCardKind.sentence
            : hit.isPhrase
            ? EpisodeCardKind.phrase
            : EpisodeCardKind.word,
        favorited: false,
        source: 'suggested',
        exampleEn: hit.line.english,
        exampleCn: hit.line.chinese.isEmpty ? null : hit.line.chinese,
        time: hit.line.startTime,
        startMs: hit.line.startMs,
        endMs: hit.line.endMs,
      ),
    );
  }
  return out;
}

class _SuggestionHit {
  _SuggestionHit({
    required this.token,
    required this.line,
    this.isPhrase = false,
    this.isSentence = false,
    this.count = 0,
  });

  final String token;
  final PlayerSubtitleLine line;
  final bool isPhrase;
  final bool isSentence;
  int count;
}

List<String> _tokenize(String text) {
  return RegExp(r"[A-Za-z']+")
      .allMatches(text)
      .map((Match m) => m.group(0)!)
      .where((String t) => t.isNotEmpty)
      .toList(growable: false);
}

int? _parseStartMs(String? lineKey) {
  if (lineKey == null) return null;
  final Match? match = RegExp(r'^(\d+)').firstMatch(lineKey);
  return match == null ? null : int.tryParse(match.group(1)!);
}

int? _parseEndMs(String? lineKey) {
  if (lineKey == null) return null;
  final Match? match = RegExp(r'^(\d+)-(\d+)').firstMatch(lineKey);
  return match == null ? null : int.tryParse(match.group(2)!);
}

int? _msFromClock(String? clock) {
  if (clock == null || clock.trim().isEmpty) return null;
  final String value = clock.trim();
  final List<String> parts = value.split(':');
  if (parts.length == 2) {
    final int? m = int.tryParse(parts[0]);
    final double? s = double.tryParse(parts[1]);
    if (m == null || s == null) return null;
    return ((m * 60) + s).round() * 1000;
  }
  if (parts.length == 3) {
    final int? h = int.tryParse(parts[0]);
    final int? m = int.tryParse(parts[1]);
    final double? s = double.tryParse(parts[2]);
    if (h == null || m == null || s == null) return null;
    return ((h * 3600) + (m * 60) + s).round() * 1000;
  }
  return int.tryParse(value);
}
