import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:go_router/go_router.dart';

import '../../learning_modules/british_ipa_course.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../player/domain/pronunciation_assessment.dart';
import '../../player/presentation/widgets/pronunciation_assessment_dialog.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/domain/word_lookup_entry.dart';
import '../../words/domain/word_morphology.dart';
import '../../words/presentation/widgets/phonics_syllable_blocks.dart';
import '../../words/presentation/word_review_settings_provider.dart';
import '../domain/daily_review.dart';
import 'daily_review_provider.dart';
import 'review_spelling_screen.dart';

class NewWordSession extends ConsumerStatefulWidget {
  const NewWordSession({required this.words, super.key});

  final List<ReviewSource> words;

  @override
  ConsumerState<NewWordSession> createState() => _NewWordSessionState();
}

class _NewWordSessionState extends ConsumerState<NewWordSession> {
  static const List<String> stages = <String>['刷', '选', '拼', '句', '扩'];
  static const List<String> spareMeanings = <String>[
    '安排会议',
    '解释原因',
    '选择路线',
    '收集证据',
    '减少开支',
    '维持秩序',
    '公布结果',
    '改善环境',
  ];
  late final List<ReviewSource> words = List<ReviewSource>.of(widget.words);
  late final WordPronunciationService speech = ref.read(
    wordPronunciationServiceProvider,
  );
  final Map<String, Future<WordLookupEntry>> lookups = {};
  final Set<String> saved = {};
  final Set<String> deferred = {};
  final Map<String, List<String>> firstFoils = {};
  final Map<(String, int), List<String>> questionOptions = {};
  final Set<String> mistakes = {};
  int stage = 0;
  int index = 0;
  int round = 0;
  int sentenceIndex = 0;
  bool sentenceFilled = false;
  int? score;
  bool busy = false;
  bool complete = false;
  bool phonicsOpen = false;
  List<PronunciationPhoneResult>? phones;
  String? feedback;

  ReviewSource get word => words[index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_play(word.question));
    });
  }

  @override
  void dispose() {
    unawaited(speech.stop());
    super.dispose();
  }

  Future<void> _play(String text) async {
    try {
      await speech.speak(text);
    } catch (_) {}
  }

  Future<WordLookupEntry> _lookup(String text) => lookups.putIfAbsent(
    text,
    () => ref
        .read(wordLookupServiceProvider)
        .lookupWord(
          rawWord: text,
          settings: ref.read(learningSettingsProvider),
        ),
  );

  void _advance() {
    setState(() {
      feedback = null;
      phonicsOpen = false;
      phones = null;
      sentenceIndex = 0;
      sentenceFilled = false;
      score = null;
      if (++index < words.length) return;
      index = 0;
      if (stage == 1 && round == 0) {
        round = 1;
      } else {
        stage++;
      }
    });
    if (stage < stages.length && !deferred.contains(word.key)) {
      unawaited(_play(word.question));
    } else {
      unawaited(speech.stop());
    }
  }

  String _meaning(ReviewSource source, WordLookupEntry? entry) {
    if (source.answer.trim().isNotEmpty) return source.answer.trim();
    return entry?.sourceLabel == '未配置' ? '' : entry?.definitionCn.trim() ?? '';
  }

  List<String> _choices(String answer) {
    final List<String> foils = firstFoils.putIfAbsent(word.key, () {
      final List<String> pool =
          <String>{
              for (final ReviewSource item in words) item.answer.trim(),
              ...spareMeanings,
            }.where((String item) => item.isNotEmpty && item != answer).toList()
            ..shuffle();
      return pool.take(6).toList();
    });
    return questionOptions.putIfAbsent((
      word.key,
      round,
    ), () => <String>[answer, ...foils.skip(round * 3).take(3)]..shuffle());
  }

  Future<void> _openSoundVideo(PronunciationPhoneResult sound) async {
    const Map<String, String> symbols = {
      'iy': 'iː',
      'ih': 'ɪ',
      'eh': 'e',
      'ae': 'æ',
      'uh': 'ʊ',
      'uw': 'uː',
      'sh': 'ʃ',
      'zh': 'ʒ',
      'ch': 'tʃ',
      'jh': 'dʒ',
      'th': 'θ',
      'dh': 'ð',
      'ng': 'ŋ',
      'hh': 'h',
      'ey': 'eɪ',
      'ay': 'aɪ',
      'oy': 'ɔɪ',
      'aw': 'aʊ',
      'ow': 'əʊ',
    };
    final String phone = sound.referencePhone.trim().toLowerCase().replaceAll(
      RegExp(r'[/\[\]0-2]'),
      '',
    );
    final BritishIpaLesson? lesson = BritishIpaCourse.lessons
        .where((lesson) => lesson.symbol == (symbols[phone] ?? phone))
        .firstOrNull;
    if (lesson == null || phone.isEmpty) {
      setState(() => feedback = '这个音素暂无对应视频，可先听整词示范。');
      return;
    }
    try {
      await speech.stop();
      if (!mounted) return;
      await ref.read(libraryCatalogProvider.notifier).ensureBritishIpaCourse();
      if (!mounted) return;
      final String id = BritishIpaCourse.episodeIdForPage(lesson.page);
      await context.push('/episodes/${Uri.encodeComponent(id)}?autoplay=1');
    } catch (_) {
      if (mounted) setState(() => feedback = '音标视频暂不可用，请重试。');
    }
  }

  Future<void> _assess(String text, {required bool spelling}) async {
    await speech.stop();
    if (!mounted) return;
    await showPronunciationAssessmentDialog(
      context,
      target: PronunciationAssessmentTarget.wordOnly(text),
      episodeId: null,
      onResult: (PronunciationAssessmentResult result) {
        if (!mounted) return;
        setState(() {
          score = result.scoreForReference(text);
          if (spelling) {
            phones = [
              for (final PronunciationWordResult item in result.words)
                ...item.phones,
            ];
            if (score == null || phones!.isEmpty) {
              feedback = '本次未获取音素评分，请重试。';
            } else if (!_pronunciationPassed) {
              feedback = '听示范后，再跟读一遍。';
              mistakes.add(word.key);
            } else {
              feedback = null;
            }
          }
        });
      },
    );
  }

  bool get _pronunciationPassed =>
      (score ?? 0) >= 60 &&
      (phones?.isNotEmpty ?? false) &&
      phones!.every(
        (PronunciationPhoneResult phone) =>
            phone.accuracy != null && phone.accuracy! >= 60,
      );

  Future<void> _spell(String meaning) async {
    final bool full = ref.read(wordReviewSettingsProvider).requireSpelling;
    final SpellStageResult? result = await Navigator.of(context).push(
      MaterialPageRoute<SpellStageResult>(
        builder: (_) => ReviewSpellingScreen(
          word: word.question,
          meaning: meaning,
          fillMissingLetters: !full,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      phonicsOpen = result.rating != fsrs.Rating.again;
      if (result.hadMistake) mistakes.add(word.key);
    });
    if (phonicsOpen) unawaited(_play(word.question));
  }

  Future<void> _finish() async {
    if (busy) return;
    setState(() {
      busy = true;
      feedback = null;
    });
    try {
      for (final ReviewSource source in words) {
        if (!mounted) return;
        final ReviewRecord? record = ref
            .read(dailyReviewProvider)
            .records[source.key];
        if (record == null ||
            !record.isNew ||
            saved.contains(source.key) ||
            deferred.contains(source.key))
          continue;
        await ref
            .read(dailyReviewProvider.notifier)
            .grade(
              source.key,
              mistakes.contains(source.key)
                  ? fsrs.Rating.hard
                  : fsrs.Rating.good,
              expectedReviews: record.reviews,
            );
        saved.add(source.key);
      }
      if (mounted) setState(() => complete = true);
    } catch (_) {
      if (mounted) setState(() => feedback = '部分进度未保存，请重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (int i = 0; i < stages.length; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      '${stages[i]}\n${i == 4
                          ? '待词根资料'
                          : complete || i < stage
                          ? '已完成'
                          : i == stage
                          ? '进行中'
                          : '待开始'}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: i == stage
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        fontWeight: i == stage ? FontWeight.bold : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: complete
              ? Center(child: Text('今日新学完成 · ${saved.length} 个词'))
              : stage == 0
              ? PageView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: words.length,
                  onPageChanged: (int page) {
                    setState(() => index = page);
                    unawaited(_play(word.question));
                  },
                  itemBuilder: (_, int page) => FutureBuilder<WordLookupEntry>(
                    future: _lookup(words[page].question),
                    builder: (_, snapshot) =>
                        _wordCard(words[page], snapshot.data),
                  ),
                )
              : ListView(
                  key: ValueKey((stage, index, round, sentenceIndex)),
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (stage < stages.length)
                      Text('${index + 1} / ${words.length}'),
                    if (stage < 5)
                      FutureBuilder<WordLookupEntry>(
                        future: _lookup(word.question),
                        builder: (_, snapshot) => _exercise(snapshot.data),
                      ),
                    if (stage >= 5)
                      FilledButton(
                        onPressed: busy ? null : _finish,
                        child: const Text('完成并保存'),
                      ),
                    if (feedback case final String message) Text(message),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _wordCard(ReviewSource source, WordLookupEntry? entry) {
    final MorphologyInsight morphology = analyzeWordMorphology(source.question);
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Text('${words.indexOf(source) + 1} / ${words.length} · 上下滑动'),
        ColoredVowelHeadword(word: source.question),
        if (entry?.phonetic.isNotEmpty ?? false) Text(entry!.phonetic),
        Text(
          _meaning(source, entry).isEmpty ? '暂无中文释义' : _meaning(source, entry),
        ),
        Text(
          source.english.isEmpty
              ? entry?.exampleSentenceEn ?? ''
              : source.english,
        ),
        if (source.chinese.isNotEmpty) Text(source.chinese),
        for (final AffixHit part in morphology.affixes)
          Text('${part.part} · ${part.meaningCn}'),
        TextButton(
          onPressed: () => _play(source.question),
          child: const Text('听示范'),
        ),
        TextButton(
          onPressed: () => _assess(source.question, spelling: false),
          child: const Text('跟读'),
        ),
        if (identical(source, words.last))
          FilledButton(
            onPressed: () {
              _advance();
            },
            child: const Text('开始释义四选一'),
          ),
      ],
    );
  }

  Widget _exercise(WordLookupEntry? entry) {
    final String meaning = _meaning(word, entry);
    if (deferred.contains(word.key)) {
      return TextButton(onPressed: _advance, child: const Text('已暂缓，继续'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stage == 1 || stage == 4) ColoredVowelHeadword(word: word.question),
        if (stage == 1) ...[
          Text('第 ${round + 1} / 2 轮'),
          if (meaning.isEmpty) ...[
            const Text('正在查找释义。若未找到，可以重新查词。'),
            TextButton(
              onPressed: () => setState(() => lookups.remove(word.question)),
              child: const Text('重新查词'),
            ),
            TextButton(
              onPressed: () {
                deferred.add(word.key);
                _advance();
              },
              child: const Text('暂缓此词'),
            ),
          ] else
            for (final String option in _choices(meaning))
              OutlinedButton(
                onPressed: () {
                  if (option == meaning) {
                    _advance();
                  } else {
                    setState(() {
                      mistakes.add(word.key);
                      feedback = '再想一想。';
                    });
                  }
                },
                child: Text(option),
              ),
        ],
        if (stage == 2 && !phonicsOpen)
          FilledButton(
            onPressed: () => _spell(meaning),
            child: const Text('开始拼写'),
          ),
        if (stage == 2 && phonicsOpen) ...[
          _SyllableMerge(word: word.question),
          PhonicsSyllableBlocks(word: word.question),
          if (entry?.phonetic.isNotEmpty ?? false) Text(entry!.phonetic),
          for (final PronunciationPhoneResult sound in phones ?? const [])
            ActionChip(
              label: Text(
                '${sound.referencePhone} · ${sound.accuracy?.round() ?? '未评分'}',
              ),
              backgroundColor: (sound.accuracy ?? 0) < 60
                  ? Colors.red.shade200
                  : null,
              onPressed: (sound.accuracy ?? 0) < 60
                  ? () => _openSoundVideo(sound)
                  : null,
            ),
          TextButton(
            onPressed: () => _play(word.question),
            child: const Text('听整词示范'),
          ),
          FilledButton(
            onPressed: () => _assess(word.question, spelling: true),
            child: const Text('跟读整词'),
          ),
          if (_pronunciationPassed)
            FilledButton(onPressed: _advance, child: const Text('下一词')),
        ],
        if (stage == 3) _sentences(entry),
        if (stage == 4) ...[
          for (final AffixHit part in analyzeWordMorphology(
            word.question,
          ).affixes)
            Text('${part.part} · ${part.meaningCn}'),
          const Text('同根词资料待导入。'),
          FilledButton(onPressed: _advance, child: const Text('下一词')),
        ],
      ],
    );
  }

  Widget _sentences(WordLookupEntry? entry) {
    final RegExp target = RegExp(
      '\\b${RegExp.escape(word.question)}\\b',
      caseSensitive: false,
    );
    final List<String> sentences = <String>{
      word.english,
      for (final ReviewSourceLink link in word.relatedSources) link.english,
      if (entry != null) entry.exampleSentenceEn,
    }.where(target.hasMatch).take(5).toList();
    if (sentences.isEmpty) {
      return TextButton(onPressed: _advance, child: const Text('暂无可练原句，继续'));
    }
    final String sentence = sentences[sentenceIndex];
    final List<String> candidates = <String>{
      word.question,
      for (final ReviewSource source in words) source.question,
      'study',
      'notice',
      'remember',
    }.take(4).toList()..shuffle();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('例句 ${sentenceIndex + 1} / ${sentences.length}'),
        Text(sentenceFilled ? sentence : sentence.replaceAll(target, '_____')),
        if (!sentenceFilled)
          for (final String candidate in candidates)
            OutlinedButton(
              onPressed: () => setState(() {
                sentenceFilled = candidate == word.question;
                if (!sentenceFilled) mistakes.add(word.key);
                feedback = sentenceFilled ? null : '再试一次。';
              }),
              child: Text(candidate),
            ),
        if (sentenceFilled)
          FilledButton(
            onPressed: () => _assess(sentence, spelling: false),
            child: const Text('跟读原句'),
          ),
        if (sentenceFilled && score != null) ...[
          Text('跟读评分 ${score!}'),
          FilledButton(
            onPressed: () {
              if (sentenceIndex + 1 == sentences.length) {
                _advance();
              } else {
                setState(() {
                  sentenceIndex++;
                  sentenceFilled = false;
                  score = null;
                });
              }
            },
            child: const Text('继续'),
          ),
        ],
      ],
    );
  }
}

class _SyllableMerge extends StatelessWidget {
  const _SyllableMerge({required this.word});

  final String word;

  @override
  Widget build(BuildContext context) {
    final List<String> syllables = splitEnglishSyllables(word);
    if (syllables.length < 2 || MediaQuery.disableAnimationsOf(context)) {
      return ColoredVowelHeadword(word: word);
    }
    return Semantics(
      label: word,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1, end: 0),
        duration: const Duration(milliseconds: 1050),
        curve: const Interval(0.35, 1, curve: Curves.easeInOut),
        builder: (context, separation, _) {
          if (separation == 0) return ColoredVowelHeadword(word: word);
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < syllables.length; i++) ...[
                  if (i > 0)
                    SizedBox(
                      width: 18 * separation,
                      child: Opacity(
                        opacity: separation,
                        child: const Center(child: Text('·')),
                      ),
                    ),
                  ColoredVowelHeadword(word: syllables[i]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
