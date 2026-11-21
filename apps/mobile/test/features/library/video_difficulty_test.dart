import 'package:common_learn_english/features/library/domain/video_difficulty.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final Set<String> top = <String>{
    'the',
    'you',
    'i',
    'to',
    'a',
    'and',
    'is',
    'it',
    'in',
    'of',
    'that',
    'have',
    'for',
    'on',
    'with',
    'he',
    'she',
    'we',
    'they',
    'this',
    'what',
    'can',
    'do',
    'my',
    'me',
    'like',
    'go',
    'want',
    'good',
    'day',
    'hello',
    'friend',
    'school',
    'home',
    'time',
    'yes',
    'no',
    'please',
    'thank',
    'thanks',
    'okay',
    'ok',
    'very',
    'much',
    'how',
    'are',
    'your',
    'name',
  };

  test('parseCefrLevel reads tagged and estimated labels', () {
    expect(parseCefrLevel('B1'), 'B1');
    expect(parseCefrLevel('约 A2'), 'A2');
    expect(parseCefrLevel('c1 · 学术'), 'C1');
    expect(parseCefrLevel('自定义'), isNull);
  });

  test('easy dialogue maps to A1/A2', () {
    const String text = '''
Hello my friend. How are you today?
I am very good thank you. Do you want to go to school with me?
Yes please. What is your name?
''';
    final VideoDifficultyEstimate estimate = estimateVideoDifficulty(
      englishText: text,
      topFrequencyWords: top,
      fingerprint: 't1',
      computedAtMs: 1,
    );
    expect(estimate.tokenCount, greaterThan(10));
    expect(estimate.top3000Coverage, greaterThan(0.9));
    expect(<String>['A1', 'A2', 'B1'], contains(estimate.cefr));
  });

  test('rare vocabulary maps harder', () {
    const String text = '''
The epistemological ramifications of postmodern hermeneutics necessitate
a thoroughgoing reappraisal of ontological presuppositions.
Quantum entanglement circumvents classical locality constraints.
''';
    final VideoDifficultyEstimate estimate = estimateVideoDifficulty(
      englishText: text * 3,
      topFrequencyWords: top,
      fingerprint: 't2',
      computedAtMs: 1,
    );
    expect(estimate.top3000Coverage, lessThan(0.75));
    expect(cefrRank(estimate.cefr), greaterThanOrEqualTo(cefrRank('B2')));
  });
}
