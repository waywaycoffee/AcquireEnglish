/// Subtitle teaching-mark taxonomy (no Flutter deps — safe for line models).
enum SubtitleChunkKind {
  /// Formulaic multi-word unit from chunk lexicon / syllabus (语块).
  chunk,

  /// Common English phrase / phrasal verb (词组).
  phrase,

  /// Favorite word from the user's word book (生词).
  vocab,
}

extension SubtitleChunkKindLabel on SubtitleChunkKind {
  String get labelCn => switch (this) {
    SubtitleChunkKind.chunk => '语块',
    SubtitleChunkKind.phrase => '词组',
    SubtitleChunkKind.vocab => '生词',
  };

  static SubtitleChunkKind fromName(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'phrase':
      case 'phrasal':
      case '词组':
        return SubtitleChunkKind.phrase;
      case 'vocab':
      case 'vocabulary':
      case 'new_word':
      case 'newword':
      case '生词':
        return SubtitleChunkKind.vocab;
      // Legacy「用法」lexicon rows were formulaic patterns → 语块.
      case 'usage':
      case 'pattern':
      case '用法':
      case 'chunk':
      case '语块':
      default:
        return SubtitleChunkKind.chunk;
    }
  }
}

class SubtitleChunkEntry {
  const SubtitleChunkEntry({
    required this.phrase,
    required this.tokens,
    required this.kind,
    this.source = '',
  });

  final String phrase;
  final List<String> tokens;
  final SubtitleChunkKind kind;

  /// Provenance: `lexicon` | `syllabus` | `phrase_book` | `word_book` | …
  final String source;
}

class SubtitleChunkSpan {
  const SubtitleChunkSpan({
    required this.start,
    required this.endExclusive,
    required this.kind,
    required this.phrase,
    this.source = '',
  });

  final int start;
  final int endExclusive;
  final SubtitleChunkKind kind;
  final String phrase;
  final String source;

  bool contains(int index) => index >= start && index < endExclusive;
}

/// One lexicon / word-book hit attached to a subtitle line.
class SubtitleLineMark {
  const SubtitleLineMark({
    required this.kind,
    required this.phrase,
    required this.startToken,
    required this.endTokenExclusive,
    this.source = '',
  });

  final SubtitleChunkKind kind;
  final String phrase;
  final int startToken;
  final int endTokenExclusive;
  final String source;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        'phrase': phrase,
        'start': startToken,
        'end': endTokenExclusive,
        if (source.isNotEmpty) 'source': source,
      };

  factory SubtitleLineMark.fromJson(Map<dynamic, dynamic> json) {
    return SubtitleLineMark(
      kind: SubtitleChunkKindLabel.fromName('${json['kind'] ?? ''}'),
      phrase: '${json['phrase'] ?? ''}'.trim(),
      startToken: (json['start'] as num?)?.toInt() ?? 0,
      endTokenExclusive: (json['end'] as num?)?.toInt() ?? 0,
      source: '${json['source'] ?? ''}'.trim(),
    );
  }
}
