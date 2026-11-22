import 'package:common_learn_english/features/exam/domain/exam_pack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('derives cloze and grammar from pack json', () {
    final ExamPack pack = ExamPack.fromJson(<String, dynamic>{
      'family_id': 'gaokao',
      'title': 'T',
      'cefr': 'B1',
      'sections': <String, dynamic>{
        'vocab': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'g1',
            'prompt': 'She ____ to school yesterday.',
            'options': <String>['go', 'goes', 'went', 'going'],
            'answer': 'went',
          },
          <String, dynamic>{
            'id': 'v1',
            'prompt': 'The word abandon means ____.',
            'options': <String>['give up', 'pick up', 'look up', 'make up'],
            'answer': 'give up',
          },
        ],
        'reading': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'c1',
            'title': 'Cloze demo',
            'passage': 'Many students ____ clubs every week.',
            'questions': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'b1',
                'prompt': 'Blank #1',
                'options': <String>['join', 'joins', 'joined', 'joining'],
                'answer': 'join',
              },
            ],
          },
        ],
        'listening': <dynamic>[],
        'writing': <dynamic>[],
        'speaking': <dynamic>[],
      },
      'mock': <String, dynamic>{'sections': <String>[], 'duration_minutes': 60},
    });

    expect(pack.cloze, isNotEmpty);
    expect(pack.cloze.first.questions, hasLength(1));
    expect(pack.grammar, isNotEmpty);
    expect(grammarTagForPrompt('She ____ to school yesterday.'), '时态');
  });
}
