/// Auto-built custom book from favorited / collected words (情景记忆).
const String kSceneMemoryBookId = 'scene_memory';

const String kSceneMemoryBookTitle = '情景记忆';

bool isSceneMemoryBookId(String id) =>
    id.trim() == kSceneMemoryBookId;

enum SyllabusBookKind {
  word,
  pattern,
  foundation;

  static SyllabusBookKind fromName(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'pattern':
      case 'sentence':
      case '短语':
      case '句型':
        return SyllabusBookKind.pattern;
      case 'foundation':
      case 'phonics':
      case 'ipa':
      case '零基础':
      case '音标':
      case '自然拼读':
        return SyllabusBookKind.foundation;
      default:
        return SyllabusBookKind.word;
    }
  }

  String get storageName => switch (this) {
    SyllabusBookKind.word => 'word',
    SyllabusBookKind.pattern => 'pattern',
    SyllabusBookKind.foundation => 'foundation',
  };

  String get labelCn => switch (this) {
    SyllabusBookKind.word => '词书',
    SyllabusBookKind.pattern => '句型书',
    SyllabusBookKind.foundation => '零基础',
  };
}

class SyllabusWord {
  const SyllabusWord({required this.word, this.gloss = ''});

  factory SyllabusWord.fromJson(Map<String, dynamic> json) => SyllabusWord(
    word: '${json['word'] ?? ''}'.trim().toLowerCase(),
    gloss: '${json['gloss'] ?? ''}'.trim(),
  );

  final String word;
  final String gloss;

  Map<String, Object?> toJson() => <String, Object?>{
    'word': word,
    'gloss': gloss,
  };
}

class SyllabusBook {
  const SyllabusBook({
    required this.id,
    required this.title,
    required this.examTag,
    required this.words,
    this.disclaimer = '',
    this.builtin = true,
    this.kind = SyllabusBookKind.word,
  });

  factory SyllabusBook.fromJson(
    Map<String, dynamic> json, {
    bool builtin = true,
  }) {
    final List<SyllabusWord> words = <SyllabusWord>[];
    final Object? raw = json['words'];
    if (raw is List) {
      for (final Object? item in raw) {
        if (item is Map) {
          final SyllabusWord word = SyllabusWord.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (word.word.isNotEmpty) words.add(word);
        } else if (item is String && item.trim().isNotEmpty) {
          words.add(SyllabusWord(word: item.trim().toLowerCase()));
        }
      }
    }
    return SyllabusBook(
      id: '${json['id'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      examTag: '${json['examTag'] ?? ''}'.trim(),
      disclaimer: '${json['disclaimer'] ?? ''}'.trim(),
      words: List<SyllabusWord>.unmodifiable(words),
      builtin: json['builtin'] as bool? ?? builtin,
      kind: SyllabusBookKind.fromName('${json['kind'] ?? ''}'),
    );
  }

  final String id;
  final String title;
  final String examTag;
  final String disclaimer;
  final List<SyllabusWord> words;
  final bool builtin;
  final SyllabusBookKind kind;

  int get wordCount => words.length;

  bool get isPatternBook => kind == SyllabusBookKind.pattern;

  bool get isFoundationBook => kind == SyllabusBookKind.foundation;

  SyllabusBook copyWith({
    String? id,
    String? title,
    String? examTag,
    String? disclaimer,
    List<SyllabusWord>? words,
    bool? builtin,
    SyllabusBookKind? kind,
  }) {
    return SyllabusBook(
      id: id ?? this.id,
      title: title ?? this.title,
      examTag: examTag ?? this.examTag,
      disclaimer: disclaimer ?? this.disclaimer,
      words: words ?? this.words,
      builtin: builtin ?? this.builtin,
      kind: kind ?? this.kind,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'examTag': examTag,
    'disclaimer': disclaimer,
    'builtin': builtin,
    'kind': kind.storageName,
    'words': words.map((SyllabusWord w) => w.toJson()).toList(),
  };
}

/// Parse CSV/TXT word lists: one word per line, or `word,gloss`.
/// When [allowPhrases] is true, keeps multi-word lines for 句型书 import.
List<SyllabusWord> parseSyllabusImport(
  String raw, {
  bool allowPhrases = false,
}) {
  final List<SyllabusWord> out = <SyllabusWord>[];
  final Set<String> seen = <String>{};
  for (final String line in raw.split(RegExp(r'\r?\n'))) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    String word;
    String gloss = '';
    final int comma = trimmed.indexOf(',');
    if (comma > 0) {
      word = trimmed.substring(0, comma).trim();
      gloss = trimmed.substring(comma + 1).trim();
    } else if (trimmed.contains('\t')) {
      final List<String> parts = trimmed.split('\t');
      word = parts.first.trim();
      gloss = parts.length > 1 ? parts[1].trim() : '';
    } else {
      word = trimmed;
    }
    if (allowPhrases) {
      word = word
          .toLowerCase()
          .replaceAll(RegExp(r"[^a-z'\s]+"), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    } else {
      word = word.toLowerCase().replaceAll(RegExp("[^a-z'-]"), '');
    }
    if (word.length < 2 || !seen.add(word)) continue;
    out.add(SyllabusWord(word: word, gloss: gloss));
  }
  return out;
}

String syllabusReviewKey(String bookId, String word) =>
    'syllabus:$bookId:${word.trim().toLowerCase()}';
