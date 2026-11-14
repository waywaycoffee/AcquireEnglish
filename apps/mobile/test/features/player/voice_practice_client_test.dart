import 'package:common_learn_english/features/player/data/voice_practice_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeBaseUrl strips trailing slash and adds scheme', () {
    expect(
      VoicePracticeClient.normalizeBaseUrl('192.168.1.8:8765'),
      'http://192.168.1.8:8765',
    );
    expect(
      VoicePracticeClient.normalizeBaseUrl('http://127.0.0.1:8765/'),
      'http://127.0.0.1:8765',
    );
  });

  test('VoiceShadowResult parses overlap score', () {
    final VoiceShadowResult result = VoiceShadowResult.fromJson(
      <String, Object?>{
        'id': 'abc',
        'reference_text': 'Hello world',
        'transcript': 'Hello there',
        'duration': 1.5,
        'mock': false,
        'overlap': <String, Object?>{
          'score': 0.5,
          'precision': 0.5,
          'recall': 0.5,
          'missing_words': <String>['world'],
          'extra_words': <String>['there'],
          'reference_words': 2,
          'hypothesis_words': 2,
        },
        'label': 'test',
      },
    );
    expect(result.scorePercentLabel, '50%');
    expect(result.overlap.missingWords, <String>['world']);
    expect(result.transcript, 'Hello there');
  });
}
