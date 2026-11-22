import 'package:common_learn_english/features/digital_human/data/scene_word_recognizer.dart';
import 'package:common_learn_english/features/digital_human/domain/scene_word_label.dart';
import 'package:common_learn_english/features/reading/data/reading_gloss.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keepLearningTargets hides high-frequency and known words', () {
    final ReadingFrequencyLexicon lexicon = ReadingFrequencyLexicon(
      <String, int>{
        'person': 50,
        'hand': 80,
        'watermelon': 9000,
        'ladle': 15000,
      },
    );
    final List<SceneWordLabel> kept = SceneWordRecognizer.keepLearningTargets(
      const <SceneWordLabel>[
        SceneWordLabel(word: 'person'),
        SceneWordLabel(word: 'hand'),
        SceneWordLabel(word: 'watermelon'),
        SceneWordLabel(word: 'ladle'),
        SceneWordLabel(word: 'knownword'),
      ],
      lexicon: lexicon,
      freqThreshold: 3000,
      knownWords: <String>{'knownword'},
      focusWords: <String>{'hand'},
    );
    expect(
      kept.map((SceneWordLabel e) => e.word).toList(),
      <String>['hand', 'watermelon', 'ladle'],
    );
  });

  test('scenePhoto keeps common nouns and only drops known words', () {
    final ReadingFrequencyLexicon lexicon = ReadingFrequencyLexicon(
      <String, int>{
        'laptop': 1200,
        'stool': 8000,
        'person': 50,
      },
    );
    final List<SceneWordLabel> kept = SceneWordRecognizer.keepLearningTargets(
      const <SceneWordLabel>[
        SceneWordLabel(word: 'laptop'),
        SceneWordLabel(word: 'stool'),
        SceneWordLabel(word: 'person'),
        SceneWordLabel(word: 'knownword'),
      ],
      lexicon: lexicon,
      freqThreshold: 3000,
      knownWords: <String>{'knownword', 'person'},
      scenePhoto: true,
    );
    expect(
      kept.map((SceneWordLabel e) => e.word).toList(),
      <String>['laptop', 'stool'],
    );
  });
}
