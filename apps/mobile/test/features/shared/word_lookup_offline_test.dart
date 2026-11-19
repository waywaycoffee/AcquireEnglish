import 'package:flutter_test/flutter_test.dart';
import 'package:common_learn_english/features/shared/data/word_lookup_service.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/shared/domain/word_lookup_entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('name has a real definition when AI is unavailable', () async {
    final service = WordLookupService(
      remoteLookupOverride:
          ({required rawWord, contextSentence, required settings}) async =>
              throw StateError('offline'),
    );
    final entry = await service.lookupWord(
      rawWord: 'Name',
      contextSentence: 'Hello my name is Luke.',
      settings: LearningSettingsState.defaults(),
    );
    expect(entry.sourceLabel, '离线词典');
    expect(entry.definitionCn, contains('名字'));
    expect(entry.definitionCn, isNot(contains('API')));
    expect(entry.usageEn, contains('AI 解析暂不可用'));
  });
  test(
    'public lexicon takes priority over AI and preserves metadata',
    () async {
      const WordLookupEntry shared = WordLookupEntry(
        word: 'happy',
        phonetic: 'ˈhæpi',
        type: 'adjective',
        definitionEn: 'Feeling pleasure.',
        usageEn: '',
        exampleSentenceEn: 'I am happy.',
        definitionCn: '快乐的',
        sourceLabel: '公共词库',
        level: '学龄前',
        audioUrl: 'https://example.test/happy/audio',
      );
      final WordLookupService service = WordLookupService(
        publicLookup: (String word, LearningSettingsState settings) async {
          expect(word, 'happy');
          return shared;
        },
        remoteLookupOverride:
            ({required rawWord, contextSentence, required settings}) async =>
                throw StateError('AI should not be called'),
      );
      final WordLookupEntry result = await service.lookupWord(
        rawWord: 'Happy',
        settings: LearningSettingsState.defaults(),
      );
      expect(result, same(shared));
      expect(
        WordLookupEntry.fromJson(result.toJson()).audioUrl,
        shared.audioUrl,
      );
    },
  );
}
