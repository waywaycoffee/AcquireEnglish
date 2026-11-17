import 'package:flutter_test/flutter_test.dart';
import 'package:common_learn_english/features/shared/data/word_lookup_service.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('name has a real definition when AI is unavailable', () async {
    final service = WordLookupService(remoteLookupOverride: ({required rawWord, contextSentence, required settings}) async => throw StateError('offline'));
    final entry = await service.lookupWord(rawWord: 'Name', contextSentence: 'Hello my name is Luke.', settings: LearningSettingsState.defaults());
    expect(entry.sourceLabel, '离线词典');
    expect(entry.definitionCn, contains('名字'));
    expect(entry.definitionCn, isNot(contains('API')));
    expect(entry.usageEn, contains('AI 解析暂不可用'));
  });
}
