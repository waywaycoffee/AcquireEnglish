import 'package:common_learn_english/features/digital_human/data/oral_coach_pipeline_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeBaseUrl', () {
    expect(
      OralCoachPipelineClient.normalizeBaseUrl('192.168.1.8:8770'),
      'http://192.168.1.8:8770',
    );
    expect(
      OralCoachPipelineClient.normalizeBaseUrl(
        'https://acquireenglish.caurlhairai.com/coach/',
      ),
      'https://acquireenglish.curlhairai.com/coach',
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
          'action': 'livetalking_connect',
          'text': 'Nice work.',
          'livetalking_url': 'http://127.0.0.1:8010',
        },
        'providers': <String, Object?>{'asr': 'mock'},
      },
      'http://127.0.0.1:8770',
    );
    expect(turn.scoreLabel, '80%');
    expect(turn.ttsUrl, 'http://127.0.0.1:8770/api/tts/a.wav');
    expect(turn.avatarAction, 'livetalking_connect');
    expect(turn.avatarText, 'Nice work.');
    expect(turn.livetalkingUrl, 'http://127.0.0.1:8010');
  });

  test('turn result parses diagnosis and Chinese fallback', () {
    final OralCoachTurnResult withDiag = OralCoachTurnResult.fromJson(
      <String, Object?>{
        'transcript': '我刚才去了一趟超市',
        'coach_text': 'Hold the mic and say it again.',
        'diagnosis': <String, Object?>{
          'source': '我刚才去了一趟超市',
          'literal_en': 'I just went to the supermarket.',
          'idiomatic_en': 'I just popped to the supermarket.',
          'tip': 'popped to 更口语',
        },
      },
      'http://127.0.0.1:8770',
    );
    expect(withDiag.diagnosis?.idiomaticEn, 'I just popped to the supermarket.');
    expect(withDiag.diagnosis?.literalEn, 'I just went to the supermarket.');

    final OralCoachTurnResult chineseFallback = OralCoachTurnResult.fromJson(
      <String, Object?>{
        'transcript': '我刚才去了一趟超市',
        'coach_text': 'ok',
      },
      'http://127.0.0.1:8770',
    );
    expect(chineseFallback.diagnosis?.source, '我刚才去了一趟超市');
    expect(chineseFallback.diagnosis?.isUseful, isTrue);
  });

  test('tts_url joins subpath base and scheme-relative URLs', () {
    final OralCoachTurnResult relative = OralCoachTurnResult.fromJson(
      <String, Object?>{
        'transcript': 'hi',
        'coach_text': 'ok',
        'tts_url': 'api/tts/b.wav',
      },
      'https://acquireenglish.curlhairai.com/coach',
    );
    expect(
      relative.ttsUrl,
      'https://acquireenglish.curlhairai.com/coach/api/tts/b.wav',
    );

    final OralCoachTurnResult schemeRelative = OralCoachTurnResult.fromJson(
      <String, Object?>{
        'transcript': 'hi',
        'coach_text': 'ok',
        'tts_url': '//cdn.example.com/x.wav',
      },
      'https://acquireenglish.curlhairai.com/coach',
    );
    expect(schemeRelative.ttsUrl, 'https://cdn.example.com/x.wav');
  });
}
