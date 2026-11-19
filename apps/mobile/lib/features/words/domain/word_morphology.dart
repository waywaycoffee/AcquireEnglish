/// Local morphology helpers: syllable/phonics blocks, roots/affixes, etymology hints.

class PhonicsSegment {
  const PhonicsSegment({
    required this.text,
    required this.kind,
    required this.colorIndex,
  });

  final String text;
  /// `onset` | `vowel` | `coda` | `syllable`
  final String kind;
  final int colorIndex;
}

class AffixHit {
  const AffixHit({
    required this.part,
    required this.kind,
    required this.meaningCn,
    required this.examples,
  });

  final String part;
  /// `prefix` | `root` | `suffix`
  final String kind;
  final String meaningCn;
  final List<String> examples;
}

class MorphologyInsight {
  const MorphologyInsight({
    required this.segments,
    required this.affixes,
    required this.etymologyHintCn,
  });

  final List<PhonicsSegment> segments;
  final List<AffixHit> affixes;
  final String etymologyHintCn;
}

const List<int> kPhonicsPalette = <int>[
  0xFFDBEAFE, // blue
  0xFFDCFCE7, // green
  0xFFFEF3C7, // amber
  0xFFFCE7F3, // pink
  0xFFE0E7FF, // indigo
  0xFFFFEDD5, // orange
];

/// Split an English word into syllable-ish chunks for colored blocks.
List<String> splitEnglishSyllables(String raw) {
  final String word = raw.trim().toLowerCase().replaceAll(RegExp(r"[^a-z']"), '');
  if (word.isEmpty) {
    return const <String>[];
  }
  if (word.length <= 3) {
    return <String>[word];
  }

  // Prefer vowel-group boundaries: ba-na-na, teach-er, won-der-ful.
  final List<int> vowelStarts = <int>[];
  for (int i = 0; i < word.length; i++) {
    if (_isVowel(word[i], prev: i > 0 ? word[i - 1] : null)) {
      if (i == 0 || !_isVowel(word[i - 1], prev: i > 1 ? word[i - 2] : null)) {
        vowelStarts.add(i);
      }
    }
  }
  if (vowelStarts.length <= 1) {
    return <String>[word];
  }

  final List<String> parts = <String>[];
  int start = 0;
  for (int v = 1; v < vowelStarts.length; v++) {
    final int vowelIndex = vowelStarts[v];
    // Keep at least one consonant with the next syllable when possible (CVC-CV).
    int cut = vowelIndex;
    if (cut - 1 > start && !_isVowel(word[cut - 1], prev: word[cut - 2])) {
      cut = vowelIndex - 1;
    }
    if (cut <= start) {
      continue;
    }
    parts.add(word.substring(start, cut));
    start = cut;
  }
  parts.add(word.substring(start));
  return parts.where((String p) => p.isNotEmpty).toList(growable: false);
}

List<PhonicsSegment> buildPhonicsSegments(String raw) {
  final List<String> syllables = splitEnglishSyllables(raw);
  final List<PhonicsSegment> out = <PhonicsSegment>[];
  for (int i = 0; i < syllables.length; i++) {
    final String syl = syllables[i];
    final int color = i % kPhonicsPalette.length;
    // Further tint vowel nucleus inside long syllables.
    final Match? vowel = RegExp(r"[aeiouy]+", caseSensitive: false).firstMatch(syl);
    if (vowel == null || syl.length <= 2) {
      out.add(PhonicsSegment(text: syl, kind: 'syllable', colorIndex: color));
      continue;
    }
    final int vs = vowel.start;
    final int ve = vowel.end;
    if (vs > 0) {
      out.add(
        PhonicsSegment(
          text: syl.substring(0, vs),
          kind: 'onset',
          colorIndex: color,
        ),
      );
    }
    out.add(
      PhonicsSegment(
        text: syl.substring(vs, ve),
        kind: 'vowel',
        colorIndex: color,
      ),
    );
    if (ve < syl.length) {
      out.add(
        PhonicsSegment(
          text: syl.substring(ve),
          kind: 'coda',
          colorIndex: color,
        ),
      );
    }
  }
  return out;
}

List<AffixHit> matchRootsAndAffixes(String raw) {
  final String word = raw.trim().toLowerCase().replaceAll(RegExp(r"[^a-z']"), '');
  if (word.length < 3) {
    return const <AffixHit>[];
  }
  final List<AffixHit> hits = <AffixHit>[];
  final Set<String> seen = <String>{};

  void add(AffixHit hit) {
    final String key = '${hit.kind}:${hit.part}';
    if (seen.add(key)) {
      hits.add(hit);
    }
  }

  for (final MapEntry<String, String> e in _kPrefixes.entries) {
    if (word.startsWith(e.key) && word.length - e.key.length >= 2) {
      add(
        AffixHit(
          part: e.key,
          kind: 'prefix',
          meaningCn: e.value,
          examples: _examplesFor(e.key),
        ),
      );
    }
  }
  for (final MapEntry<String, String> e in _kSuffixes.entries) {
    if (word.endsWith(e.key) && word.length - e.key.length >= 2) {
      add(
        AffixHit(
          part: e.key,
          kind: 'suffix',
          meaningCn: e.value,
          examples: _examplesFor(e.key),
        ),
      );
    }
  }
  for (final MapEntry<String, String> e in _kRoots.entries) {
    if (word.contains(e.key) && e.key.length >= 3) {
      add(
        AffixHit(
          part: e.key,
          kind: 'root',
          meaningCn: e.value,
          examples: _examplesFor(e.key),
        ),
      );
    }
  }
  // Prefer longer / more informative hits first.
  hits.sort((AffixHit a, AffixHit b) => b.part.length.compareTo(a.part.length));
  return hits.take(6).toList(growable: false);
}

String localEtymologyHint(String raw, List<AffixHit> affixes) {
  final String word = raw.trim().toLowerCase();
  final String? known = _kEtymologyHints[word];
  if (known != null && known.isNotEmpty) {
    return known;
  }
  if (affixes.isEmpty) {
    return '暂无内置溯源；收藏后可用 AI 生成词源简述。';
  }
  final List<String> bits = affixes
      .map((AffixHit a) {
        final String label = switch (a.kind) {
          'prefix' => '前缀',
          'suffix' => '后缀',
          _ => '词根',
        };
        return '$label ${a.part}（${a.meaningCn}）';
      })
      .toList(growable: false);
  return '构词提示：${bits.join('；')}。完整词源可在 AI 词卡中生成。';
}

MorphologyInsight analyzeWordMorphology(String raw) {
  final List<PhonicsSegment> segments = buildPhonicsSegments(raw);
  final List<AffixHit> affixes = matchRootsAndAffixes(raw);
  return MorphologyInsight(
    segments: segments,
    affixes: affixes,
    etymologyHintCn: localEtymologyHint(raw, affixes),
  );
}

bool _isVowel(String ch, {String? prev}) {
  final String c = ch.toLowerCase();
  if ('aeiou'.contains(c)) {
    return true;
  }
  // Treat 'y' as vowel except at word start (yellow).
  if (c == 'y' && prev != null) {
    return true;
  }
  return false;
}

List<String> _examplesFor(String part) =>
    _kExamples[part] ?? const <String>[];

const Map<String, String> _kPrefixes = <String, String>{
  'anti': '反对 / 抗',
  'auto': '自己 / 自动',
  'bi': '二 / 双',
  'co': '共同',
  'de': '向下 / 除去',
  'dis': '不 / 相反',
  'en': '使… / 进入',
  'ex': '出 / 前',
  'fore': '预先 / 前面',
  'il': '不',
  'im': '不 / 进入',
  'in': '不 / 进入',
  'inter': '之间',
  'micro': '微',
  'mis': '错误',
  'multi': '多',
  'non': '非',
  'over': '过度 / 在上',
  'pre': '预先',
  'pro': '向前 / 支持',
  're': '再 / 回',
  'semi': '半',
  'sub': '下 / 次',
  'super': '超',
  'tele': '远',
  'trans': '穿越 / 转变',
  'tri': '三',
  'un': '不 / 解开',
  'under': '不足 / 在下',
};

const Map<String, String> _kSuffixes = <String, String>{
  'able': '能够…的',
  'ible': '能够…的',
  'al': '…的 / 相关',
  'ance': '状态 / 行为',
  'ence': '状态 / 行为',
  'er': '人 / 更',
  'or': '人 / 物',
  'ful': '充满…的',
  'ic': '…的',
  'ical': '…的',
  'ing': '进行 / …的',
  'ion': '行为 / 状态',
  'tion': '行为 / 状态',
  'sion': '行为 / 状态',
  'ism': '主义 / 特征',
  'ist': '从事…的人',
  'ity': '性质',
  'ive': '有…倾向',
  'ize': '使…化',
  'ise': '使…化',
  'less': '没有…的',
  'ly': '以…方式',
  'ment': '行为 / 结果',
  'ness': '性质 / 状态',
  'ous': '充满…的',
  'ship': '身份 / 关系',
  'ward': '朝向',
};

const Map<String, String> _kRoots = <String, String>{
  'aud': '听',
  'bio': '生命',
  'chron': '时间',
  'dict': '说',
  'duc': '引导',
  'duct': '引导',
  'form': '形状',
  'geo': '地球',
  'graph': '写 / 画',
  'hydr': '水',
  'ject': '投掷',
  'log': '说 / 学',
  'meter': '测量',
  'morph': '形态',
  'path': '感受 / 疾病',
  'phil': '爱',
  'phon': '声音',
  'port': '搬运',
  'press': '压',
  'rupt': '断',
  'scrib': '写',
  'script': '写',
  'sens': '感觉',
  'sent': '感觉',
  'spect': '看',
  'struct': '建造',
  'tele': '远',
  'therm': '热',
  'tract': '拉',
  'vent': '来',
  'vert': '转',
  'vis': '看',
  'vid': '看',
  'voc': '声音 / 召唤',
};

const Map<String, List<String>> _kExamples = <String, List<String>>{
  're': <String>['rewrite', 'return', 'review'],
  'un': <String>['unhappy', 'unlock', 'unfair'],
  'pre': <String>['preview', 'prepare', 'predict'],
  'dis': <String>['dislike', 'disagree', 'discover'],
  'tion': <String>['action', 'nation', 'education'],
  'ment': <String>['movement', 'development'],
  'able': <String>['readable', 'comfortable'],
  'spect': <String>['inspect', 'respect', 'spectacle'],
  'port': <String>['import', 'export', 'transport'],
  'struct': <String>['construct', 'structure'],
  'graph': <String>['photograph', 'autograph'],
  'phon': <String>['telephone', 'phonics'],
  'bio': <String>['biology', 'biography'],
  'dict': <String>['predict', 'dictionary'],
  'vis': <String>['visible', 'vision', 'visit'],
};

const Map<String, String> _kEtymologyHints = <String, String>{
  'education': '来自拉丁 educare「引导出来」：e-/ex-（出）+ duc（引导）。',
  'telephone': '希腊 tele「远」+ phone「声音」：远距离传声。',
  'biology': '希腊 bios「生命」+ -logy「学问」。',
  'transport': '拉丁 trans「穿越」+ portare「搬运」。',
  'inspect': '拉丁 in「向内」+ specere「看」：仔细查看。',
  'predict': '拉丁 prae「预先」+ dicere「说」：预先说出。',
  'photograph': '希腊 phos「光」+ graphein「写/画」。',
  'dictionary': '拉丁 dictio「词语 / 说话」相关，后指词典。',
  'structure': '拉丁 struere「建造」派生。',
  'wonderful': 'wonder「惊奇」+ -ful「充满…的」。',
};
