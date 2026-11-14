import 'package:common_learn_english/features/player/data/oral_coach_pipeline_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeBaseUrl', () {
    expect(
      OralCoachPipelineClient.normalizeBaseUrl('192.168.1.8:8770'),
      'http://192.168.1.8:8770',
    );
  });

  test('turn result parses avatar cue', () {
    final OralCoachTurnResult turn = OralCoachTurnResult.fromJson(
      <String, Object?>{
        'transcript': 'hello',
        'coach_text': 'Nice work.',
        'difficulty': 'B1',
        'pronunciation': <String, Object?>{
          'overall': 0.8,
          'notes': 'ok',
        },
        'corrections': <String>['ending /s/'],
        'tts_url': '/api/tts/a.wav',
        'avatar': <String, Object?>{
          'action': 'livetalking_human',
          'text': 'Nice work.',
          'livetalking_url': 'http://127.0.0.1:8010',
        },
        'providers': <String, Object?>{'asr': 'mock'},
      },
      'http://127.0.0.1:8770',
    );
    expect(turn.scoreLabel, '80%');
    expect(turn.ttsUrl, 'http://127.0.0.1:8770/api/tts/a.wav');
    expect(turn.avatarAction, 'livetalking_human');
  });
}
