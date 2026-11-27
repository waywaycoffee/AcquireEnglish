/// Offline word-root catalog models (from docs/wordroot → roots_full.json).

class WordRootEntry {
  const WordRootEntry({
    required this.id,
    required this.root,
    required this.variants,
    required this.type,
    required this.typeCn,
    required this.cn,
    required this.en,
    required this.lang,
    required this.etym,
    required this.level,
    required this.exampleCount,
    required this.examplesRaw,
  });

  factory WordRootEntry.fromJson(Map<String, dynamic> json) => WordRootEntry(
        id: '${json['id'] ?? ''}'.trim(),
        root: '${json['root'] ?? ''}'.trim(),
        variants: '${json['variants'] ?? ''}'.trim(),
        type: '${json['type'] ?? ''}'.trim(),
        typeCn: '${json['typeCn'] ?? ''}'.trim(),
        cn: '${json['cn'] ?? ''}'.trim(),
        en: '${json['en'] ?? ''}'.trim(),
        lang: '${json['lang'] ?? ''}'.trim(),
        etym: '${json['etym'] ?? ''}'.trim(),
        level: '${json['level'] ?? ''}'.trim(),
        exampleCount: (json['exampleCount'] as num?)?.toInt() ?? 0,
        examplesRaw: '${json['examples'] ?? ''}'.trim(),
      );

  final String id;
  final String root;
  final String variants;
  final String type;
  final String typeCn;
  final String cn;
  final String en;
  final String lang;
  final String etym;
  final String level;
  final int exampleCount;
  final String examplesRaw;

  bool get isPrefix => type == 'prefix' || typeCn == '前缀';
  bool get isSuffix => type == 'suffix' || typeCn == '后缀';

  List<String> get variantForms {
    final List<String> out = <String>[root];
    for (final String part in variants.split(RegExp(r'[,;/]'))) {
      final String t = part.trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }
}

class WordRootWord {
  const WordRootWord({
    required this.word,
    required this.gloss,
    required this.level,
    required this.rootIds,
    this.glossVariants = '',
  });

  factory WordRootWord.fromJson(Map<String, dynamic> json) {
    final List<String> rids = <String>[];
    final Object? raw = json['rids'];
    if (raw is List) {
      for (final Object? item in raw) {
        final String id = '$item'.trim();
        if (id.isNotEmpty) rids.add(id);
      }
    }
    return WordRootWord(
      word: '${json['w'] ?? ''}'.trim().toLowerCase(),
      gloss: '${json['g'] ?? ''}'.trim(),
      level: '${json['lv'] ?? ''}'.trim(),
      rootIds: List<String>.unmodifiable(rids),
      glossVariants: '${json['variants'] ?? ''}'.trim(),
    );
  }

  final String word;
  final String gloss;
  final String level;
  final List<String> rootIds;
  final String glossVariants;
}

class WordRootRel {
  const WordRootRel({
    required this.word,
    required this.rootId,
    required this.root,
    required this.typeCn,
    required this.matchedForm,
    required this.position,
    required this.rootCn,
    required this.rootSense,
    required this.wordGloss,
  });

  factory WordRootRel.fromJson(Map<String, dynamic> json) => WordRootRel(
        word: '${json['w'] ?? ''}'.trim().toLowerCase(),
        rootId: '${json['rid'] ?? ''}'.trim(),
        root: '${json['root'] ?? ''}'.trim(),
        typeCn: '${json['typeCn'] ?? ''}'.trim(),
        matchedForm: '${json['form'] ?? ''}'.trim(),
        position: '${json['pos'] ?? ''}'.trim(),
        rootCn: '${json['rcn'] ?? ''}'.trim(),
        rootSense: '${json['sense'] ?? ''}'.trim(),
        wordGloss: '${json['wg'] ?? ''}'.trim(),
      );

  final String word;
  final String rootId;
  final String root;
  final String typeCn;
  final String matchedForm;
  final String position;
  final String rootCn;
  final String rootSense;
  final String wordGloss;
}

class WordRootParsePart {
  const WordRootParsePart({
    required this.rootText,
    required this.cnMeaning,
    required this.type,
    required this.typeCn,
    required this.position,
    required this.matchedForm,
    required this.rootSense,
    required this.rootId,
  });

  final String rootText;
  final String cnMeaning;
  final String type;
  final String typeCn;
  final String position;
  final String matchedForm;
  /// Per-word sense of this root inside [word] (from word_root_rel.root_sense).
  /// Empty until curated; fall back to [cnMeaning] (root's general gloss).
  final String rootSense;
  final String rootId;

  /// Prefer contextual [rootSense]; otherwise the root's general [cnMeaning].
  String get displayMeaning {
    final String sense = rootSense.trim();
    if (sense.isNotEmpty) return sense;
    return cnMeaning;
  }

  bool get hasContextualSense => rootSense.trim().isNotEmpty;
}

class WordRootDetail {
  const WordRootDetail({
    required this.word,
    required this.gloss,
    required this.level,
    required this.parse,
    required this.sameRootWords,
    this.isManual = true,
    this.warning = '',
  });

  final String word;
  final String gloss;
  final String level;
  final List<WordRootParsePart> parse;
  final List<WordRootWord> sameRootWords;

  /// True when parse comes from curated word_root_rel (may still lack root_sense).
  final bool isManual;

  /// Shown when [isManual] is false (rule/morphology guess only).
  final String warning;

  String get parseFormula {
    if (parse.isEmpty) return '';
    return parse
        .map(
          (WordRootParsePart p) =>
              '${p.matchedForm.isNotEmpty ? p.matchedForm : p.rootText}'
              '(${p.displayMeaning})',
        )
        .join(' + ');
  }

  WordRootDetail copyWith({
    List<WordRootParsePart>? parse,
    List<WordRootWord>? sameRootWords,
    bool? isManual,
    String? warning,
  }) {
    return WordRootDetail(
      word: word,
      gloss: gloss,
      level: level,
      parse: parse ?? this.parse,
      sameRootWords: sameRootWords ?? this.sameRootWords,
      isManual: isManual ?? this.isManual,
      warning: warning ?? this.warning,
    );
  }
}

class WordRootSpellCandidate {
  const WordRootSpellCandidate({
    required this.word,
    required this.distance,
    required this.gloss,
    required this.level,
  });

  final String word;
  final int distance;
  final String gloss;
  final String level;
}
