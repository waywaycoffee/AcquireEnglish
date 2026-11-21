import 'package:common_learn_english/features/digital_human/data/scene_word_recognizer.dart';
import 'package:common_learn_english/features/digital_human/domain/scene_word_label.dart';
import 'package:common_learn_english/features/shared/data/word_lookup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scene description lists labeled objects', () {
    final SceneWordRecognizer recognizer = SceneWordRecognizer(
      lookup: WordLookupService(
        publicLookup: (_, __) async => null,
        clientId: 'test',
        clientKind: 'anonymous',
      ),
    );
    final String text = recognizer.buildSceneDescription(const <SceneWordLabel>[
      SceneWordLabel(word: 'watermelon', chinese: '西瓜'),
      SceneWordLabel(word: 'bag', chinese: '袋子'),
    ]);
    expect(text.contains('watermelon'), isTrue);
    expect(text.contains('西瓜'), isTrue);
    expect(text.toLowerCase().contains('scene'), isTrue);
  });
}
