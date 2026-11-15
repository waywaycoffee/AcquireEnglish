import 'package:common_learn_english/features/words/domain/vocab_card_kind.dart';
import 'package:common_learn_english/features/words/presentation/word_book_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies word / phrase / pattern by token count', () {
    expect(vocabCardKindForLexeme('hello'), VocabCardKind.word);
    expect(vocabCardKindForLexeme('look after'), VocabCardKind.phrase);
    expect(
      vocabCardKindForLexeme('would you mind if i'),
      VocabCardKind.pattern,
    );
  });

  test('WordEntry round-trips enrichment fields', () {
    const WordEntry entry = WordEntry(
      word: 'apple',
      favorite: true,
      kind: VocabCardKind.word,
      definitionCn: '苹果',
      phonetic: '/ˈæpl/',
      partOfSpeech: 'n.',
      definitionEn: 'a fruit',
      analysisCn: '常见水果名词',
      mnemonicCn: '爱婆 → apple',
      aiExampleEn: 'I ate an apple.',
      aiExampleCn: '我吃了一个苹果。',
      enrichmentStatus: VocabEnrichmentStatus.ready,
      occurrences: <WordOccurrence>[
        WordOccurrence(
          episodeId: 'ep1',
          course: 'c',
          episode: 'e',
          time: '00:01',
          sentence: 'An apple a day.',
          chinese: '一天一个苹果。',
          count: 1,
          lineKeys: <String>['1-2'],
          contexts: <WordContext>[
            WordContext(
              lineKey: '1-2',
              time: '00:01',
              sentence: 'An apple a day.',
              chinese: '一天一个苹果。',
              count: 1,
            ),
          ],
        ),
      ],
    );
    final WordEntry restored = WordEntry.fromJson(entry.toJson());
    expect(restored.mnemonicCn, '爱婆 → apple');
    expect(restored.aiExampleEn, 'I ate an apple.');
    expect(restored.sourceSentence, 'An apple a day.');
    expect(restored.enrichmentStatus, VocabEnrichmentStatus.ready);
    expect(restored.kind, VocabCardKind.word);
  });
}
