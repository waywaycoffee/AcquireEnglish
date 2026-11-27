/// Offline word-root catalog models (docs/wordroot v2 → roots_app.json).

enum WordRootSenseSource { manual, derived, unknown }

WordRootSenseSource parseWordRootSenseSource(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'manual':
      return WordRootSenseSource.manual;
    case 'derived':
      return WordRootSenseSource.derived;
    default:
      return WordRootSenseSource.unknown;
  }
}

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
    this.exampleCount = 0,
    this.examplesRaw = '',
  });

  /// Accepts both v1 export keys and v2 roots_app.json keys.
  factory WordRootEntry.fromJson(Map<String, dynamic> json) {
    final String type = '${json['type'] ?? ''}'.trim();
    final String levelRaw = '${json['level'] ?? ''}'.trim();
    final String level = switch (levelRaw) {
      'core' => '高频',
      'advanced' => '进阶',
      _ => levelRaw,
    };
    return WordRootEntry(
      id: '${json['id'] ?? json['root_id'] ?? ''}'.trim(),
      root: '${json['root'] ?? json['root_text'] ?? ''}'.trim(),
      variants: '${json['variants'] ?? json['root_alt'] ?? ''}'.trim(),
      type: type,
      typeCn: '${json['typeCn'] ?? ''}'.trim().isNotEmpty
          ? '${json['typeCn']}'.trim()
          : switch (type) {
              'prefix' => '前缀',
              'suffix' => '后缀',
              _ => '词根',
            },
      cn: '${json['cn'] ?? json['cn_meaning'] ?? ''}'.trim(),
      en: '${json['en'] ?? ''}'.trim(),
      lang: '${json['lang'] ?? ''}'.trim(),
      etym: '${json['etym'] ?? json['short_etym'] ?? ''}'.trim(),
      level: level,
      exampleCount: (json['exampleCount'] as num?)?.toInt() ?? 0,
      examplesRaw: '${json['examples'] ?? ''}'.trim(),
    );
  }

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
    this.wordId = '',
    this.glossVariants = '',
    this.embeddedRels = const <WordRootRel>[],
  });

  factory WordRootWord.fromJson(Map<String, dynamic> json) {
    // v2 roots_app.json word object
    if (json.containsKey('cn_def') || json.containsKey('word_id')) {
      final String word = '${json['word'] ?? ''}'.trim().toLowerCase();
      final List<WordRootRel> embedded = <WordRootRel>[];
      final List<String> rids = <String>[];
      final Object? rootsRaw = json['roots'];
      if (rootsRaw is List) {
        for (final Object? item in rootsRaw) {
          if (item is! Map) continue;
          final Map<String, dynamic> m = Map<String, dynamic>.from(item);
          final WordRootRel rel = WordRootRel.fromEmbedded(word, m);
          if (rel.rootId.isNotEmpty) {
            embedded.add(rel);
            rids.add(rel.rootId);
          }
        }
      }
      final String levelRaw = '${json['word_level'] ?? ''}'.trim();
      return WordRootWord(
        word: word,
        gloss: '${json['cn_def'] ?? ''}'.trim(),
        level: switch (levelRaw) {
          'core' => '高频',
          'advanced' => '进阶',
          _ => levelRaw,
        },
        rootIds: List<String>.unmodifiable(rids),
        wordId: '${json['word_id'] ?? ''}'.trim(),
        embeddedRels: List<WordRootRel>.unmodifiable(embedded),
      );
    }

    // v1 compact export
    final List<String> rids = <String>[];
    final Object? raw = json['rids'];
    if (raw is List) {
      for (final Object? item in raw) {
        final String id = '$item'.trim();
        if (id.isNotEmpty) rids.add(id);
      }
    }
    return WordRootWord(
      word: '${json['w'] ?? json['word'] ?? ''}'.trim().toLowerCase(),
      gloss: '${json['g'] ?? json['gloss'] ?? ''}'.trim(),
      level: '${json['lv'] ?? json['level'] ?? ''}'.trim(),
      rootIds: List<String>.unmodifiable(rids),
      glossVariants: '${json['variants'] ?? ''}'.trim(),
    );
  }

  final String word;
  final String gloss;
  final String level;
  final List<String> rootIds;
  final String wordId;
  final String glossVariants;
  final List<WordRootRel> embeddedRels;
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
    this.senseSource = WordRootSenseSource.unknown,
    this.type = '',
  });

  factory WordRootRel.fromJson(Map<String, dynamic> json) => WordRootRel(
        word: '${json['w'] ?? json['word'] ?? ''}'.trim().toLowerCase(),
        rootId: '${json['rid'] ?? json['root_id'] ?? ''}'.trim(),
        root: '${json['root'] ?? json['root_text'] ?? ''}'.trim(),
        typeCn: '${json['typeCn'] ?? ''}'.trim(),
        matchedForm: '${json['form'] ?? json['matched_form'] ?? ''}'.trim(),
        position: _normalizePosition('${json['pos'] ?? json['position'] ?? ''}'),
        rootCn: '${json['rcn'] ?? json['root_cn_meaning'] ?? json['cn_meaning'] ?? ''}'.trim(),
        rootSense: '${json['sense'] ?? json['root_sense'] ?? ''}'.trim(),
        wordGloss: '${json['wg'] ?? json['word_gloss'] ?? ''}'.trim(),
        senseSource: parseWordRootSenseSource(
          '${json['sense_source'] ?? json['root_sense_source'] ?? ''}',
        ),
        type: '${json['type'] ?? ''}'.trim(),
      );

  /// Nested root object under a v2 word entry.
  factory WordRootRel.fromEmbedded(String word, Map<String, dynamic> json) {
    final String type = '${json['type'] ?? ''}'.trim();
    return WordRootRel(
      word: word,
      rootId: '${json['root_id'] ?? ''}'.trim(),
      root: '${json['root_text'] ?? ''}'.trim(),
      typeCn: switch (type) {
        'prefix' => '前缀',
        'suffix' => '后缀',
        _ => '词根',
      },
      matchedForm: '${json['form'] ?? ''}'.trim(),
      position: _normalizePosition('${json['position'] ?? ''}'),
      rootCn: '${json['cn_meaning'] ?? ''}'.trim(),
      rootSense: '${json['root_sense'] ?? ''}'.trim(),
      wordGloss: '',
      senseSource: parseWordRootSenseSource('${json['root_sense_source'] ?? ''}'),
      type: type,
    );
  }

  final String word;
  final String rootId;
  final String root;
  final String typeCn;
  final String matchedForm;
  final String position;
  final String rootCn;
  final String rootSense;
  final String wordGloss;
  final WordRootSenseSource senseSource;
  final String type;

  static String _normalizePosition(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'head':
      case '词首':
        return '词首';
      case 'middle':
      case '词中':
        return '词中';
      case 'tail':
      case '词尾':
        return '词尾';
      default:
        return raw.trim();
    }
  }
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
    this.senseSource = WordRootSenseSource.unknown,
  });

  final String rootText;
  final String cnMeaning;
  final String type;
  final String typeCn;
  final String position;
  final String matchedForm;
  final String rootSense;
  final String rootId;
  final WordRootSenseSource senseSource;

  /// Prefer contextual sense for formula when present.
  String get displayMeaning {
    final String sense = rootSense.trim();
    if (sense.isNotEmpty) return sense;
    return cnMeaning;
  }

  bool get hasContextualSense => rootSense.trim().isNotEmpty;

  bool get isManualSense => senseSource == WordRootSenseSource.manual;

  bool get isDerivedSense => senseSource == WordRootSenseSource.derived;
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
    this.wordId = '',
  });

  final String word;
  final String gloss;
  final String level;
  final List<WordRootParsePart> parse;
  final List<WordRootWord> sameRootWords;
  final bool isManual;
  final String warning;
  final String wordId;

  bool get allManualSense =>
      parse.isNotEmpty &&
      parse.every((WordRootParsePart p) => p.isManualSense);

  bool get anyDerivedSense =>
      parse.any((WordRootParsePart p) => p.isDerivedSense);

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
      wordId: wordId,
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
