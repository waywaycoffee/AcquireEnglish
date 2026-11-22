import 'package:common_learn_english/features/writing/domain/writing_tracks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps families to three writing tracks', () {
    expect(writingTrackForFamily('zhongkao'), WritingTrackId.zhongkao);
    expect(writingTrackForFamily('k12_j3'), WritingTrackId.zhongkao);
    expect(writingTrackForFamily('gaokao'), WritingTrackId.gaokao);
    expect(writingTrackForFamily('k12_s3'), WritingTrackId.gaokao);
    expect(writingTrackForFamily('ielts_ac'), WritingTrackId.ielts);
  });

  test('resolves rubrics for three levels', () {
    expect(
      resolveWritingRubric(requested: 'generic', track: WritingTrackId.zhongkao),
      'zhongkao',
    );
    expect(
      resolveWritingRubric(requested: 'k12', familyId: 'zhongkao'),
      'zhongkao',
    );
    expect(
      resolveWritingRubric(requested: 'k12', familyId: 'gaokao'),
      'gaokao',
    );
    expect(
      resolveWritingRubric(requested: 'generic', track: WritingTrackId.ielts),
      'ielts_task2',
    );
    expect(
      resolveWritingRubric(requested: 'gaokao_continuation'),
      'gaokao_continuation',
    );
  });
}
