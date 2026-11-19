import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../daily_review/presentation/daily_review_provider.dart';
import '../home/presentation/learning_dashboard_provider.dart';
import '../idle_jobs/idle_job_queue.dart';
import '../phrases/presentation/phrase_book_provider.dart';
import '../words/domain/sm2_scheduler.dart';
import '../words/domain/vocab_card_kind.dart';
import '../words/presentation/vocabulary_placement_provider.dart';
import '../words/presentation/word_book_provider.dart';

/// Demo course label — used to spot seeded rows in UI.
const String kDemoCourse = '演示课程';

const Set<String> kDemoWordKeys = <String>{
  'acquire',
  'subtitle',
  'whisper',
  'resilient',
  'nuance',
  'pragmatic',
  'catch up',
  'hang in there',
};

const Set<String> kDemoPhraseIds = <String>{
  'demo_phrase_1',
  'demo_phrase_2',
  'demo_phrase_3',
  'demo_phrase_4',
  'demo_phrase_5',
  'demo_phrase_6',
};

class DemoSeedReport {
  const DemoSeedReport({required this.lines});
  final List<String> lines;
  String get message => lines.join('\n');
}

WordOccurrence _occ({
  required String sentence,
  required String chinese,
  required String time,
}) {
  final WordContext ctx = WordContext(
    lineKey: 'demo_$time',
    time: time,
    sentence: sentence,
    chinese: chinese,
    count: 1,
  );
  return WordOccurrence(
    episodeId: 'demo_ep_1',
    course: kDemoCourse,
    episode: 'E01',
    time: time,
    sentence: sentence,
    chinese: chinese,
    count: 1,
    lineKeys: <String>[ctx.lineKey],
    contexts: <WordContext>[ctx],
  );
}

List<WordEntry> _demoWords() {
  final int dueSoon = DateTime.now()
      .subtract(const Duration(hours: 2))
      .millisecondsSinceEpoch;
  return <WordEntry>[
    WordEntry(
      word: 'acquire',
      favorite: true,
      kind: VocabCardKind.word,
      definitionCn: '获得；习得',
      phonetic: '/əˈkwaɪər/',
      partOfSpeech: 'v.',
      mnemonicCn: 'a + quire ≈ 去「求」得 → 获得',
      rootsAffixesCn: 'ac-（朝向）+ quir（寻求）',
      enrichmentStatus: VocabEnrichmentStatus.ready,
      mastery: WordMastery.learning,
      repetitions: 2,
      dueAtMs: dueSoon,
      occurrences: <WordOccurrence>[
        _occ(
          sentence: 'You can acquire English by watching shows.',
          chinese: '你可以通过看剧习得英语。',
          time: '00:01:12',
        ),
      ],
    ),
    WordEntry(
      word: 'subtitle',
      favorite: true,
      kind: VocabCardKind.word,
      definitionCn: '字幕',
      phonetic: '/ˈsʌbˌtaɪtl/',
      partOfSpeech: 'n.',
      mnemonicCn: 'sub（下面）+ title → 底下的标题＝字幕',
      enrichmentStatus: VocabEnrichmentStatus.ready,
      mastery: WordMastery.fresh,
      occurrences: <WordOccurrence>[
        _occ(
          sentence: 'Turn on the English subtitle.',
          chinese: '打开英文字幕。',
          time: '00:02:05',
        ),
      ],
    ),
    WordEntry(
      word: 'whisper',
      favorite: true,
      kind: VocabCardKind.word,
      definitionCn: '低语；耳语',
      phonetic: '/ˈwɪspər/',
      partOfSpeech: 'v./n.',
      enrichmentStatus: VocabEnrichmentStatus.pending,
      mastery: WordMastery.fresh,
      occurrences: <WordOccurrence>[
        _occ(
          sentence: 'She whispered the answer.',
          chinese: '她低声说出了答案。',
          time: '00:03:40',
        ),
      ],
    ),
    WordEntry(
      word: 'resilient',
      favorite: true,
      kind: VocabCardKind.word,
      definitionCn: '有韧性的；能恢复的',
      phonetic: '/rɪˈzɪliənt/',
      partOfSpeech: 'adj.',
      mnemonicCn: '像弹簧一样弹回来',
      enrichmentStatus: VocabEnrichmentStatus.ready,
      mastery: WordMastery.known,
      repetitions: 4,
      intervalDays: 7,
      dueAtMs: dueSoon,
      occurrences: <WordOccurrence>[
        _occ(
          sentence: 'Kids are surprisingly resilient.',
          chinese: '孩子们出奇地有韧性。',
          time: '00:05:18',
        ),
      ],
    ),
    WordEntry(
      word: 'nuance',
      favorite: true,
      kind: VocabCardKind.word,
      definitionCn: '细微差别',
      phonetic: '/ˈnuːɑːns/',
      partOfSpeech: 'n.',
      enrichmentStatus: VocabEnrichmentStatus.ready,
      mastery: WordMastery.learning,
      repetitions: 1,
      dueAtMs: dueSoon,
      occurrences: <WordOccurrence>[
        _occ(
          sentence: 'There is a nuance in his tone.',
          chinese: '他的语气里有细微差别。',
          time: '00:06:02',
        ),
      ],
    ),
    WordEntry(
      word: 'pragmatic',
      favorite: false,
      kind: VocabCardKind.word,
      definitionCn: '务实的',
      phonetic: '/præɡˈmætɪk/',
      partOfSpeech: 'adj.',
      enrichmentStatus: VocabEnrichmentStatus.none,
      mastery: WordMastery.fresh,
      occurrences: <WordOccurrence>[
        _occ(
          sentence: 'Let\'s be pragmatic about the plan.',
          chinese: '我们对这个计划务实一点吧。',
          time: '00:07:11',
        ),
      ],
    ),
    WordEntry(
      word: 'catch up',
      favorite: true,
      kind: VocabCardKind.phrase,
      definitionCn: '赶上；叙旧',
      enrichmentStatus: VocabEnrichmentStatus.ready,
      mnemonicCn: '追上进度 / 见面聊聊近况',
      mastery: WordMastery.learning,
      repetitions: 1,
      dueAtMs: dueSoon,
      occurrences: <WordOccurrence>[
        _occ(
          sentence: "Let's catch up this weekend.",
          chinese: '这周末一起叙叙旧吧。',
          time: '00:08:00',
        ),
      ],
    ),
    WordEntry(
      word: 'hang in there',
      favorite: true,
      kind: VocabCardKind.pattern,
      definitionCn: '坚持住；别放弃',
      enrichmentStatus: VocabEnrichmentStatus.ready,
      mastery: WordMastery.fresh,
      occurrences: <WordOccurrence>[
        _occ(
          sentence: 'Hang in there — you are almost done.',
          chinese: '坚持住，你快完成了。',
          time: '00:09:22',
        ),
      ],
    ),
  ];
}

List<PhraseEntry> _demoPhrases() {
  final String now = DateTime.now().toIso8601String();
  final String due = DateTime.now()
      .subtract(const Duration(hours: 3))
      .toIso8601String();
  return <PhraseEntry>[
    PhraseEntry(
      id: 'demo_phrase_1',
      english: "I'll get back to you.",
      chinese: '我稍后回复你。',
      course: kDemoCourse,
      episode: 'E01',
      time: '00:10:01',
      rating: 2,
      needsReview: true,
      today: true,
      episodeId: 'demo_ep_1',
      note: '演示·口语常用',
      collectedAt: now,
      nextReviewAt: due,
      reviewCount: 1,
    ),
    PhraseEntry(
      id: 'demo_phrase_2',
      english: 'That rings a bell.',
      chinese: '听起来耳熟。',
      course: kDemoCourse,
      episode: 'E01',
      time: '00:11:20',
      rating: 1,
      needsReview: true,
      today: true,
      episodeId: 'demo_ep_1',
      collectedAt: now,
    ),
    PhraseEntry(
      id: 'demo_phrase_3',
      english: 'Long story short,',
      chinese: '长话短说，',
      course: kDemoCourse,
      episode: 'E02',
      time: '00:02:44',
      rating: 3,
      needsReview: false,
      today: false,
      episodeId: 'demo_ep_2',
      collectedAt: now,
      nextReviewAt: DateTime.now()
          .add(const Duration(days: 3))
          .toIso8601String(),
      reviewCount: 2,
    ),
    PhraseEntry(
      id: 'demo_phrase_4',
      english: 'No worries.',
      chinese: '没关系。',
      course: kDemoCourse,
      episode: 'E02',
      time: '00:04:10',
      rating: 4,
      needsReview: false,
      today: false,
      episodeId: 'demo_ep_2',
      collectedAt: now,
      reviewCount: 3,
    ),
    PhraseEntry(
      id: 'demo_phrase_5',
      english: 'You are kidding me.',
      chinese: '你在开玩笑吧。',
      course: kDemoCourse,
      episode: 'E03',
      time: '00:01:05',
      rating: 1,
      needsReview: true,
      today: true,
      episodeId: 'demo_ep_3',
      collectedAt: now,
      nextReviewAt: due,
    ),
    PhraseEntry(
      id: 'demo_phrase_6',
      english: 'It depends.',
      chinese: '视情况而定。',
      course: kDemoCourse,
      episode: 'E03',
      time: '00:06:33',
      rating: 2,
      needsReview: true,
      today: true,
      episodeId: 'demo_ep_3',
      collectedAt: now,
    ),
  ];
}

Future<DemoSeedReport> injectDemoSeed(WidgetRef ref) async {
  final List<String> lines = <String>[];

  await ref.read(wordBookProvider.notifier).upsertEntries(_demoWords());
  lines.add('单词：已注入 ${kDemoWordKeys.length} 条（含收藏/助记/待补全）');

  await ref.read(phraseBookProvider.notifier).upsertEntries(_demoPhrases());
  lines.add('短语：已注入 ${kDemoPhraseIds.length} 条');

  await ref.read(vocabularyPlacementProvider.notifier).seedDemoRecommendations();
  lines.add('推荐词：已注入演示定级推荐（可走「背推荐单词」）');

  await ref.read(learningActivityProvider.notifier).seedDemoStreak(days: 5);
  lines.add('成长/首页：已注入近 5 日打卡（连续天）');

  // Let reviewSources rebuild, then mark some favorites due.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  final List<String> dueKeys = <String>[
    'word:acquire',
    'word:resilient',
    'word:nuance',
    'word:catch up',
    'phrase:demo_phrase_1',
    'phrase:demo_phrase_2',
    'phrase:demo_phrase_5',
  ];
  await ref.read(dailyReviewProvider.notifier).seedDueKeys(dueKeys);
  lines.add('复习：已写入到期 FSRS 记录（今日背词可见）');

  await IdleJobQueue.shared.enqueue(
    kind: IdleJobKind.vocabEnrich,
    key: 'demo:whisper',
  );
  await IdleJobQueue.shared.enqueue(
    kind: IdleJobKind.modelPrefetch,
    key: 'demo:whisper-model',
  );
  lines.add('空闲队列：已放入演示 pending 任务（设置里可看）');

  lines.add('图书馆/发现/ASR：需真实导入或网络，未伪造可播资源');
  return DemoSeedReport(lines: lines);
}

Future<DemoSeedReport> clearDemoSeed(WidgetRef ref) async {
  final List<String> lines = <String>[];

  await ref.read(wordBookProvider.notifier).removeWords(kDemoWordKeys);
  lines.add('单词：已清除演示词');

  await ref.read(phraseBookProvider.notifier).removeIds(kDemoPhraseIds);
  lines.add('短语：已清除演示句');

  await ref.read(vocabularyPlacementProvider.notifier).clearDemoRecommendations();
  lines.add('推荐词：已清除演示定级');

  await ref.read(learningActivityProvider.notifier).clearDemoStreakDays();
  lines.add('成长：已清除演示打卡天');

  final Set<String> reviewKeys = <String>{
    for (final String w in kDemoWordKeys) 'word:$w',
    for (final String id in kDemoPhraseIds) 'phrase:$id',
  };
  await ref.read(dailyReviewProvider.notifier).removeKeys(reviewKeys);
  lines.add('复习：已清除演示 FSRS 记录');

  await IdleJobQueue.shared.removeKeysStartingWith('demo:');
  lines.add('空闲队列：已清除演示任务');

  return DemoSeedReport(lines: lines);
}
