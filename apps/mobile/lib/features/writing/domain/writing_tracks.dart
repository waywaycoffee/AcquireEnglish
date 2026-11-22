/// Three writing levels: 中考 / 高考 / 雅思.

enum WritingTrackId {
  zhongkao,
  gaokao,
  ielts,
}

class WritingPromptSeed {
  const WritingPromptSeed({
    required this.title,
    required this.prompt,
    required this.rubric,
  });

  final String title;
  final String prompt;
  final String rubric;
}

class WritingTrack {
  const WritingTrack({
    required this.id,
    required this.title,
    required this.oneLiner,
    required this.defaultRubric,
    required this.focusBullets,
    required this.habits,
    required this.prompts,
    this.targetWords = 80,
  });

  final WritingTrackId id;
  final String title;
  final String oneLiner;
  final String defaultRubric;
  final List<String> focusBullets;
  final List<String> habits;
  final List<WritingPromptSeed> prompts;
  final int targetWords;

  String get storageId => id.name;
}

WritingTrackId? writingTrackFromRaw(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'zhongkao':
    case 'zk':
      return WritingTrackId.zhongkao;
    case 'gaokao':
    case 'gk':
      return WritingTrackId.gaokao;
    case 'ielts':
      return WritingTrackId.ielts;
    default:
      return null;
  }
}

/// Map exam family → writing track.
WritingTrackId writingTrackForFamily(String? familyId) {
  final String f = (familyId ?? '').toLowerCase();
  if (f.startsWith('ielts')) return WritingTrackId.ielts;
  if (f == 'zhongkao' ||
      f.startsWith('k12_j') ||
      f.startsWith('k12_g') ||
      f == 'ket' ||
      f == 'pet') {
    return WritingTrackId.zhongkao;
  }
  if (f == 'gaokao' || f.startsWith('k12_s')) {
    return WritingTrackId.gaokao;
  }
  return WritingTrackId.gaokao;
}

String resolveWritingRubric({
  required String requested,
  String familyId = '',
  WritingTrackId? track,
}) {
  final String r = requested.trim().toLowerCase();
  const Set<String> known = <String>{
    'zhongkao',
    'gaokao',
    'gaokao_continuation',
    'ielts_task2',
    'ielts_task1',
    'k12',
    'cet',
    'generic',
  };
  if (known.contains(r) && r != 'generic' && r != 'k12') return r;
  if (r == 'k12') {
    // Legacy: split by family/track.
    final WritingTrackId t = track ?? writingTrackForFamily(familyId);
    return t == WritingTrackId.zhongkao ? 'zhongkao' : 'gaokao';
  }
  if (r == 'generic' || r.isEmpty) {
    final WritingTrackId t = track ?? writingTrackForFamily(familyId);
    switch (t) {
      case WritingTrackId.zhongkao:
        return 'zhongkao';
      case WritingTrackId.gaokao:
        return 'gaokao';
      case WritingTrackId.ielts:
        return 'ielts_task2';
    }
  }
  return r.isEmpty ? 'generic' : r;
}

const WritingTrack kZhongkaoWritingTrack = WritingTrack(
  id: WritingTrackId.zhongkao,
  title: '中考写作',
  oneLiner: '写全、写对：要点齐全、少低级错即可拿分。',
  defaultRubric: 'zhongkao',
  targetWords: 80,
  focusBullets: <String>[
    '要点全覆盖第一；漏点大幅扣分',
    '时态、主谓、单复数是最大扣分项',
    '简单句为主，1～2 句从句即加分',
    '连接词：and / but / so / besides 够用',
    '约 80 词；应用文为主，观点直白即可',
  ],
  habits: <String>[
    '宁简勿错，不会的高级表达换成简单句',
    '两段/三段均可，不强制主题句',
    '基础词重复可接受，先保证正确',
  ],
  prompts: <WritingPromptSeed>[
    WritingPromptSeed(
      title: '邮件：介绍学校活动',
      rubric: 'zhongkao',
      prompt:
          '假设你是李华。请给英国笔友 Tom 写一封邮件，介绍下周的校园运动会：时间、地点、项目，并邀请他一起观看。约 80 词。',
    ),
    WritingPromptSeed(
      title: '通知：环保活动',
      rubric: 'zhongkao',
      prompt:
          '学校将举办“绿色校园”活动。请写一则通知，说明时间、地点、需要带的物品，以及报名方式。要点必须写全，约 80 词。',
    ),
  ],
);

const WritingTrack kGaokaoWritingTrack = WritingTrack(
  id: WritingTrackId.gaokao,
  title: '高考写作',
  oneLiner: '写全、写对 + 写活：句式变化、词汇替换、层次清晰。',
  defaultRubric: 'gaokao',
  targetWords: 100,
  focusBullets: <String>[
    '基础仍是要点齐全、少低级错',
    '句式多样性是上档关键：从句/非谓语/倒装等',
    '有意识同义替换，少重复 think/important/many',
    '段落有主题句，逻辑衔接更自然',
    '应用文 ~100 词；读后续写两段合计 ≥150 词',
  ],
  habits: <String>[
    '通篇简单句即使没错也难上一档',
    '应用文注意语气得体（邮件/演讲/建议信）',
    '读后续写练场景、动作、心理描写与情节合理',
  ],
  prompts: <WritingPromptSeed>[
    WritingPromptSeed(
      title: '建议信：学习方法',
      rubric: 'gaokao',
      prompt:
          '假定你是李华，你的英国朋友 Peter 来信询问如何提高英语写作。请回信给出两条具体建议并说明理由。约 100 词，注意句式变化。',
    ),
    WritingPromptSeed(
      title: '读后续写练习',
      rubric: 'gaokao_continuation',
      prompt:
          '续写：On a rainy evening, Anna found a lost puppy near the bus stop. She hesitated...\n'
          '要求写两段，合计 150 词以上：补全情节，加入动作、心理与场景描写，结尾合理。',
    ),
  ],
);

const WritingTrack kIeltsWritingTrack = WritingTrack(
  id: WritingTrackId.ielts,
  title: '雅思写作',
  oneLiner: '论证逻辑 + 任务回应优先；语言是第二维度。',
  defaultRubric: 'ielts_task2',
  targetWords: 250,
  focusBullets: <String>[
    '四大维度同等重要：TR / CC / LR / GRA',
    '论点必须展开：解释 + 推导/泛例，不能只抛观点',
    '常需辩证/让步，忌一边倒空夸',
    '拒绝生硬模板与机械堆连接词',
    'Task2 ≥250 词；Task1 客观描述图表，勿主观评价',
  ],
  habits: <String>[
    '改掉高考堆华丽句、套句的习惯',
    '审题抓住 all/always/only 等限定词',
    '词汇：准确的同义替换 > 生僻词',
  ],
  prompts: <WritingPromptSeed>[
    WritingPromptSeed(
      title: 'Task 2：在线学习',
      rubric: 'ielts_task2',
      prompt:
          'Some people believe online learning will replace classroom learning. '
          'To what extent do you agree or disagree?\n'
          'Write at least 250 words. Paraphrase the question; develop each point with explanation/example.',
    ),
    WritingPromptSeed(
      title: 'Task 1：线图趋势',
      rubric: 'ielts_task1',
      prompt:
          'The line graph shows the number of international students in three countries from 2010 to 2020. '
          'Summarise the information by selecting and reporting the main features, and make comparisons where relevant. '
          'Write at least 150 words. Do NOT give personal opinions.',
    ),
  ],
);

const List<WritingTrack> kWritingTracks = <WritingTrack>[
  kZhongkaoWritingTrack,
  kGaokaoWritingTrack,
  kIeltsWritingTrack,
];

WritingTrack writingTrackById(WritingTrackId id) {
  switch (id) {
    case WritingTrackId.zhongkao:
      return kZhongkaoWritingTrack;
    case WritingTrackId.gaokao:
      return kGaokaoWritingTrack;
    case WritingTrackId.ielts:
      return kIeltsWritingTrack;
  }
}
