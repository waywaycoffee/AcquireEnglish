/// Reading-comprehension strategy: question types, traps, and the three-step method.

enum ExamRcQuestionType {
  detail,
  mainIdea,
  inference,
  vocab,
  attitude,
  unknown,
}

extension ExamRcQuestionTypeX on ExamRcQuestionType {
  String get labelCn => switch (this) {
    ExamRcQuestionType.detail => '细节题',
    ExamRcQuestionType.mainIdea => '主旨题',
    ExamRcQuestionType.inference => '推断题',
    ExamRcQuestionType.vocab => '词义猜测',
    ExamRcQuestionType.attitude => '态度题',
    ExamRcQuestionType.unknown => '综合题',
  };

  String get tipCn => switch (this) {
    ExamRcQuestionType.detail => '用题干关键词回原文定位，答案多在定位句附近。',
    ExamRcQuestionType.mainIdea => '综合首尾段与各段首句，避免以偏概全。',
    ExamRcQuestionType.inference => '答案非原句照搬，但必须有原文依据；警惕绝对化。',
    ExamRcQuestionType.vocab => '看前后句的举例、对比、因果来猜词义。',
    ExamRcQuestionType.attitude => '找情感色彩词；考试里少见极端态度。',
    ExamRcQuestionType.unknown => '先判断题型，再选对应方法。',
  };

  static ExamRcQuestionType fromStorage(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'detail':
        return ExamRcQuestionType.detail;
      case 'mainIdea':
      case 'main_idea':
        return ExamRcQuestionType.mainIdea;
      case 'inference':
        return ExamRcQuestionType.inference;
      case 'vocab':
        return ExamRcQuestionType.vocab;
      case 'attitude':
        return ExamRcQuestionType.attitude;
      default:
        return ExamRcQuestionType.unknown;
    }
  }

  String get storageValue => name;
}

enum ExamRcTrapKind {
  invent,
  swap,
  partial,
  absolute,
}

extension ExamRcTrapKindX on ExamRcTrapKind {
  String get labelCn => switch (this) {
    ExamRcTrapKind.invent => '无中生有',
    ExamRcTrapKind.swap => '偷换概念',
    ExamRcTrapKind.partial => '以偏概全',
    ExamRcTrapKind.absolute => '绝对化表达',
  };

  String get tipCn => switch (this) {
    ExamRcTrapKind.invent => '选项看起来合理，但原文根本没提。',
    ExamRcTrapKind.swap => '把 A 的特点说成 B，或张冠李戴。',
    ExamRcTrapKind.partial => '用一个细节/例子概括全文主旨。',
    ExamRcTrapKind.absolute => '出现 all / never / must / only 等绝对词，多半是错项。',
  };
}

ExamRcQuestionType detectExamRcQuestionType(String stem) {
  final String s = stem.toLowerCase();
  if (RegExp(
    r'\b(main idea|best title|mainly about|main purpose|primarily about)\b',
  ).hasMatch(s)) {
    return ExamRcQuestionType.mainIdea;
  }
  if (RegExp(
    r'\b(infer(?:s|red|ence)?|imply|implies|implied|suggest(?:s|ed)?|conclude(?:s|d)?|implication|can be concluded)\b',
  ).hasMatch(s)) {
    return ExamRcQuestionType.inference;
  }
  if (RegExp(
    r'\b(means|meaning|refers to|underlined|closest in meaning|what does .+ mean)\b',
  ).hasMatch(s)) {
    return ExamRcQuestionType.vocab;
  }
  if (RegExp(r'\b(attitude|tone|feel about|author.+think)\b').hasMatch(s)) {
    return ExamRcQuestionType.attitude;
  }
  if (RegExp(
    r'\b(according to|which of the following|mentioned|because|when|where|who|how many|in \d{4})\b',
  ).hasMatch(s)) {
    return ExamRcQuestionType.detail;
  }
  return ExamRcQuestionType.unknown;
}

/// Locator keywords from a stem: years, numbers, proper-ish tokens, core verbs.
List<String> extractExamRcLocators(String stem) {
  final List<String> out = <String>[];
  final Set<String> seen = <String>{};
  void add(String raw) {
    final String t = raw.trim();
    if (t.length < 2 || !seen.add(t.toLowerCase())) return;
    out.add(t);
  }

  for (final Match m in RegExp(r'\b(19|20)\d{2}\b').allMatches(stem)) {
    add(m.group(0)!);
  }
  for (final Match m in RegExp(r'\b\d+(?:\.\d+)?%?\b').allMatches(stem)) {
    add(m.group(0)!);
  }
  for (final Match m in RegExp(r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b').allMatches(
    stem,
  )) {
    add(m.group(0)!);
  }
  for (final Match m
      in RegExp(
        r'\b(suggest|attitude|purpose|according|imply|infer|conclude|means|title)\b',
        caseSensitive: false,
      ).allMatches(stem)) {
    add(m.group(0)!);
  }
  if (out.isEmpty) {
    for (final Match m in RegExp(r"[A-Za-z][A-Za-z'-]{3,}").allMatches(stem)) {
      final String w = m.group(0)!.toLowerCase();
      if (const <String>{
        'that',
        'this',
        'with',
        'from',
        'what',
        'which',
        'when',
        'where',
        'does',
        'following',
        'passage',
        'author',
        'according',
        'about',
        'their',
        'there',
        'have',
        'been',
      }.contains(w)) {
        continue;
      }
      add(m.group(0)!);
      if (out.length >= 6) break;
    }
  }
  return out.take(8).toList(growable: false);
}

List<ExamRcTrapKind> suggestTrapsForWrongOption(String option) {
  final String s = option.toLowerCase();
  final List<ExamRcTrapKind> traps = <ExamRcTrapKind>[];
  if (RegExp(r'\b(all|never|must|only|always|every|none)\b').hasMatch(s)) {
    traps.add(ExamRcTrapKind.absolute);
  }
  if (traps.isEmpty) {
    traps.add(ExamRcTrapKind.invent);
  }
  return traps;
}

class ExamRcSkillLesson {
  const ExamRcSkillLesson({
    required this.title,
    required this.body,
    this.bullets = const <String>[],
  });

  final String title;
  final String body;
  final List<String> bullets;
}

/// Fixed course content from the product reading-strategy brief.
const List<ExamRcSkillLesson> kExamRcSkillLessons = <ExamRcSkillLesson>[
  ExamRcSkillLesson(
    title: '总原则',
    body: '想提高阅读理解得分，关键不是把每个词都读懂，而是掌握高效解题方法。'
        '与其通读全文再做题，不如带着问题找答案。',
    bullets: <String>[
      '目标：精准打击，省时高效',
      '顺序：先题干，后文章',
    ],
  ),
  ExamRcSkillLesson(
    title: '三步走① 先看题干',
    body: '先别读文章，花约 30 秒扫题干（先不看选项），圈出定位词。',
    bullets: <String>[
      '特殊词：人名、地名、机构、年份、数字',
      '核心词：主要动词/名词，如 suggest、attitude、main purpose',
    ],
  ),
  ExamRcSkillLesson(
    title: '三步走② 带着问题略读',
    body: '带着关键词快速浏览，抓大意与结构。',
    bullets: <String>[
      '首段与尾段：中心思想或作者观点',
      '每段首句与尾句：常是段落大意',
      '转折/强调词后：but、however、indeed、especially',
    ],
  ),
  ExamRcSkillLesson(
    title: '三步走③ 精准定位比对',
    body: '用关键词回原文定位，精读该句及前后句，再比对选项。'
        '正确答案常是同义替换，而不是原词照抄。',
  ),
  ExamRcSkillLesson(
    title: '五大题型',
    body: '做题前先判断类型，再用对应方法。',
    bullets: <String>[
      '细节题：关键词定位，答案在附近',
      '主旨题：首尾段+段首句，忌以偏概全',
      '推断题：有依据的保守推理，忌绝对化',
      '词义题：上下文逻辑猜词',
      '态度题：找情感词，多为客观/谨慎肯定',
    ],
  ),
  ExamRcSkillLesson(
    title: '干扰项套路',
    body: '出题人常设坑，见到以下情况要警惕。',
    bullets: <String>[
      '无中生有',
      '偷换概念',
      '以偏概全',
      '绝对化表达',
    ],
  ),
  ExamRcSkillLesson(
    title: '提分小结',
    body: '改顺序、识题型、警惕陷阱，再坚持限时练习与错题复盘。',
    bullets: <String>[
      '养成「先题干，后文章」',
      '每天限时练习，保持手感',
    ],
  ),
];
